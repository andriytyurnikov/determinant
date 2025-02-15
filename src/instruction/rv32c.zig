/// RV32C compressed instruction expansion.
/// Every 16-bit compressed instruction maps to an existing RV32I instruction.
/// This module imports instruction.zig (consumes types) but instruction.zig does NOT import this.
const instruction = @import("../instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;

/// Expand a 16-bit compressed instruction into its equivalent 32-bit Instruction.
/// The `raw` field stores the 16-bit value zero-extended to u32.
pub fn expand(half: u16) error{IllegalInstruction}!Instruction {
    return switch (@as(u2, @truncate(half))) {
        0b00 => expandQ0(half),
        0b01 => expandQ1(half),
        0b10 => expandQ2(half),
        0b11 => error.IllegalInstruction, // not compressed
    };
}

/// Map 3-bit compressed register field to x8–x15.
fn cReg(r: u3) u5 {
    return @as(u5, r) + 8;
}

/// Extract bits [15:13] — the funct3 field for compressed instructions.
fn funct3(half: u16) u3 {
    return @truncate(half >> 13);
}

// ============================================================
// Quadrant 0: bits [1:0] = 0b00
// ============================================================

fn expandQ0(half: u16) error{IllegalInstruction}!Instruction {
    const f3 = funct3(half);
    return switch (f3) {
        // C.ADDI4SPN: addi rd', x2, nzuimm
        0b000 => {
            const nzu = ciw_nzuimm(half);
            if (nzu == 0) return error.IllegalInstruction;
            return .{
                .op = .{ .i = .ADDI },
                .rd = cReg(@truncate(half >> 2)),
                .rs1 = 2, // x2 = sp
                .imm = @intCast(nzu),
                .raw = @as(u32, half),
            };
        },
        // C.LW: lw rd', offset(rs1')
        0b010 => .{
            .op = .{ .i = .LW },
            .rd = cReg(@truncate(half >> 2)),
            .rs1 = cReg(@truncate(half >> 7)),
            .imm = @intCast(clsw_offset(half)),
            .raw = @as(u32, half),
        },
        // C.SW: sw rs2', offset(rs1')
        0b110 => .{
            .op = .{ .i = .SW },
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = cReg(@truncate(half >> 2)),
            .imm = @intCast(clsw_offset(half)),
            .raw = @as(u32, half),
        },
        else => error.IllegalInstruction,
    };
}

/// CIW-format nzuimm for C.ADDI4SPN.
/// Bits: [12:11] → [5:4], [10:7] → [9:6], [6] → [2], [5] → [3]
fn ciw_nzuimm(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x30) | // bits [12:11] → nzuimm[5:4]
        ((b >> 1) & 0x3C0) | // bits [10:7] → nzuimm[9:6]
        ((b >> 4) & 0x4) | // bit [6] → nzuimm[2]
        ((b >> 2) & 0x8); // bit [5] → nzuimm[3]
}

/// CL/CS-format word offset for C.LW/C.SW.
/// Bits: [12:10] → offset[5:3], [6] → offset[2], [5] → offset[6]
fn clsw_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x38) | // bits [12:10] → offset[5:3]
        ((b >> 4) & 0x4) | // bit [6] → offset[2]
        ((b << 1) & 0x40); // bit [5] → offset[6]
}

// ============================================================
// Quadrant 1: bits [1:0] = 0b01
// ============================================================

fn expandQ1(half: u16) error{IllegalInstruction}!Instruction {
    const f3 = funct3(half);
    return switch (f3) {
        // C.NOP / C.ADDI: addi rd, rd, nzimm
        0b000 => {
            const rd_val: u5 = @truncate(half >> 7);
            const imm = ci_imm(half);
            // C.NOP when rd=0 (hint when nzimm!=0, but decodes fine)
            // C.ADDI when rd!=0 (hint when nzimm=0, but decodes fine)
            return .{
                .op = .{ .i = .ADDI },
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = imm,
                .raw = @as(u32, half),
            };
        },
        // C.JAL: jal x1, offset (RV32 only)
        0b001 => .{
            .op = .{ .i = .JAL },
            .rd = 1, // ra
            .imm = cj_offset(half),
            .raw = @as(u32, half),
        },
        // C.LI: addi rd, x0, imm
        0b010 => {
            const rd_val: u5 = @truncate(half >> 7);
            // rd=0 is hint, decodes normally
            return .{
                .op = .{ .i = .ADDI },
                .rd = rd_val,
                .rs1 = 0,
                .imm = ci_imm(half),
                .raw = @as(u32, half),
            };
        },
        // C.ADDI16SP / C.LUI
        0b011 => {
            const rd_val: u5 = @truncate(half >> 7);
            if (rd_val == 2) {
                // C.ADDI16SP: addi x2, x2, nzimm
                const imm = ci_addi16sp_imm(half);
                if (imm == 0) return error.IllegalInstruction;
                return .{
                    .op = .{ .i = .ADDI },
                    .rd = 2,
                    .rs1 = 2,
                    .imm = imm,
                    .raw = @as(u32, half),
                };
            } else {
                // C.LUI: lui rd, nzimm
                const imm = ci_lui_imm(half);
                if (imm == 0) return error.IllegalInstruction;
                // rd=0 is hint, decodes normally
                return .{
                    .op = .{ .i = .LUI },
                    .rd = rd_val,
                    .imm = imm,
                    .raw = @as(u32, half),
                };
            }
        },
        // C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND
        0b100 => expandQ1Alu(half),
        // C.J: jal x0, offset
        0b101 => .{
            .op = .{ .i = .JAL },
            .rd = 0,
            .imm = cj_offset(half),
            .raw = @as(u32, half),
        },
        // C.BEQZ: beq rs1', x0, offset
        0b110 => .{
            .op = .{ .i = .BEQ },
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = cb_offset(half),
            .raw = @as(u32, half),
        },
        // C.BNEZ: bne rs1', x0, offset
        0b111 => .{
            .op = .{ .i = .BNE },
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = cb_offset(half),
            .raw = @as(u32, half),
        },
    };
}

/// Expand Q1 ALU instructions (funct3=0b100).
fn expandQ1Alu(half: u16) error{IllegalInstruction}!Instruction {
    const funct2: u2 = @truncate(half >> 10);
    const rd_rs1 = cReg(@truncate(half >> 7));

    return switch (funct2) {
        // C.SRLI
        0b00 => {
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            return .{
                .op = .{ .i = .SRLI },
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .raw = @as(u32, half),
            };
        },
        // C.SRAI
        0b01 => {
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            return .{
                .op = .{ .i = .SRAI },
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .raw = @as(u32, half),
            };
        },
        // C.ANDI
        0b10 => .{
            .op = .{ .i = .ANDI },
            .rd = rd_rs1,
            .rs1 = rd_rs1,
            .imm = ci_imm(half),
            .raw = @as(u32, half),
        },
        // C.SUB, C.XOR, C.OR, C.AND
        0b11 => {
            const funct1: u1 = @truncate(half >> 12);
            const funct2b: u2 = @truncate(half >> 5);
            const rs2_val = cReg(@truncate(half >> 2));
            if (funct1 != 0) return error.IllegalInstruction; // bit 12=1 reserved on RV32C
            return switch (funct2b) {
                0b00 => .{ .op = .{ .i = .SUB }, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .raw = @as(u32, half) },
                0b01 => .{ .op = .{ .i = .XOR }, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .raw = @as(u32, half) },
                0b10 => .{ .op = .{ .i = .OR }, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .raw = @as(u32, half) },
                0b11 => .{ .op = .{ .i = .AND }, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .raw = @as(u32, half) },
            };
        },
    };
}

/// CI-format signed 6-bit immediate.
/// bit[12] → imm[5], bits[6:2] → imm[4:0], sign-extended.
fn ci_imm(half: u16) i32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    const raw: u6 = @truncate((hi << 5) | lo);
    return @as(i6, @bitCast(raw));
}

/// CI-format unsigned 6-bit shamt (for shifts).
/// bit[12] → shamt[5], bits[6:2] → shamt[4:0]
fn ci_shamt(half: u16) u32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    return (hi << 5) | lo;
}

/// C.ADDI16SP immediate.
/// bit[12] → imm[9], bits[6:2] → imm[4|6|8:7|5], sign-extended.
fn ci_addi16sp_imm(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 3) & 0x200) | // bit[12] → imm[9]
        ((b >> 2) & 0x10) | // bit[6] → imm[4]
        ((b << 1) & 0x40) | // bit[5] → imm[6]
        ((b << 4) & 0x180) | // bits[4:3] → imm[8:7]
        ((b << 3) & 0x20); // bit[2] → imm[5]
    const raw10: u10 = @truncate(raw);
    return @as(i10, @bitCast(raw10));
}

/// C.LUI immediate (upper 20 bits).
/// bit[12] → imm[17], bits[6:2] → imm[16:12], sign-extended to 32, shifted left 12.
fn ci_lui_imm(half: u16) i32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    const raw: u6 = @truncate((hi << 5) | lo);
    const sign_ext: i32 = @as(i6, @bitCast(raw));
    // Shift left by 12 to produce the upper immediate
    return sign_ext << 12;
}

/// CJ-format offset for C.J/C.JAL.
/// Bits: [12] → [11], [11] → [4], [10:9] → [9:8], [8] → [10], [7] → [6], [6] → [7], [5:3] → [3:1], [2] → [5]
fn cj_offset(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 1) & 0x800) | // bit[12] → offset[11]
        ((b << 2) & 0x400) | // bit[8] → offset[10]
        ((b >> 1) & 0x300) | // bits[10:9] → offset[9:8]
        ((b << 1) & 0x80) | // bit[6] → offset[7]
        ((b >> 1) & 0x40) | // bit[7] → offset[6]
        ((b >> 7) & 0x10) | // bit[11] → offset[4]
        ((b >> 2) & 0xE) | // bits[5:3] → offset[3:1]
        ((b << 3) & 0x20); // bit[2] → offset[5]
    const raw12: u12 = @truncate(raw);
    return @as(i12, @bitCast(raw12));
}

/// CB-format offset for C.BEQZ/C.BNEZ.
/// Bits: [12] → [8], [11:10] → [4:3], [6] → [7], [5] → [6], [4:3] → [2:1], [2] → [5]
fn cb_offset(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 4) & 0x100) | // bit[12] → offset[8]
        ((b << 1) & 0xC0) | // bits[6:5] → offset[7:6]
        ((b << 3) & 0x20) | // bit[2] → offset[5]
        ((b >> 7) & 0x18) | // bits[11:10] → offset[4:3]
        ((b >> 2) & 0x6); // bits[4:3] → offset[2:1]
    const raw9: u9 = @truncate(raw);
    return @as(i9, @bitCast(raw9));
}

// ============================================================
// Quadrant 2: bits [1:0] = 0b10
// ============================================================

fn expandQ2(half: u16) error{IllegalInstruction}!Instruction {
    const f3 = funct3(half);
    return switch (f3) {
        // C.SLLI: slli rd, rd, shamt
        0b000 => {
            const rd_val: u5 = @truncate(half >> 7);
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            // rd=0 is hint, decodes normally
            return .{
                .op = .{ .i = .SLLI },
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = @intCast(shamt & 0x1F),
                .raw = @as(u32, half),
            };
        },
        // C.LWSP: lw rd, offset(x2)
        0b010 => {
            const rd_val: u5 = @truncate(half >> 7);
            if (rd_val == 0) return error.IllegalInstruction;
            return .{
                .op = .{ .i = .LW },
                .rd = rd_val,
                .rs1 = 2, // sp
                .imm = @intCast(ci_lwsp_offset(half)),
                .raw = @as(u32, half),
            };
        },
        // C.JR, C.MV, C.EBREAK, C.JALR, C.ADD
        0b100 => {
            const bit12: u1 = @truncate(half >> 12);
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);

            if (bit12 == 0) {
                if (rs2_val == 0) {
                    // C.JR: jalr x0, 0(rs1)
                    if (rd_rs1 == 0) return error.IllegalInstruction;
                    return .{
                        .op = .{ .i = .JALR },
                        .rd = 0,
                        .rs1 = rd_rs1,
                        .imm = 0,
                        .raw = @as(u32, half),
                    };
                } else {
                    // C.MV: add rd, x0, rs2
                    // rd=0 is hint, decodes normally
                    return .{
                        .op = .{ .i = .ADD },
                        .rd = rd_rs1,
                        .rs1 = 0,
                        .rs2 = rs2_val,
                        .raw = @as(u32, half),
                    };
                }
            } else {
                if (rs2_val == 0) {
                    if (rd_rs1 == 0) {
                        // C.EBREAK
                        return .{
                            .op = .{ .i = .EBREAK },
                            .raw = @as(u32, half),
                        };
                    } else {
                        // C.JALR: jalr x1, 0(rs1)
                        return .{
                            .op = .{ .i = .JALR },
                            .rd = 1, // ra
                            .rs1 = rd_rs1,
                            .imm = 0,
                            .raw = @as(u32, half),
                        };
                    }
                } else {
                    // C.ADD: add rd, rd, rs2
                    // rd=0 is hint, decodes normally
                    return .{
                        .op = .{ .i = .ADD },
                        .rd = rd_rs1,
                        .rs1 = rd_rs1,
                        .rs2 = rs2_val,
                        .raw = @as(u32, half),
                    };
                }
            }
        },
        // C.SWSP: sw rs2, offset(x2)
        0b110 => .{
            .op = .{ .i = .SW },
            .rs1 = 2, // sp
            .rs2 = @truncate(half >> 2),
            .imm = @intCast(css_swsp_offset(half)),
            .raw = @as(u32, half),
        },
        else => error.IllegalInstruction,
    };
}

/// C.LWSP offset: bit[12] → offset[5], bits[6:4] → offset[4:2], bits[3:2] → offset[7:6]
fn ci_lwsp_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x20) | // bit[12] → offset[5]
        ((b >> 2) & 0x1C) | // bits[6:4] → offset[4:2]
        ((b << 4) & 0xC0); // bits[3:2] → offset[7:6]
}

/// C.SWSP offset: bits[12:9] → offset[5:2], bits[8:7] → offset[7:6]
fn css_swsp_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x3C) | // bits[12:9] → offset[5:2]
        ((b >> 1) & 0xC0); // bits[8:7] → offset[7:6]
}

test {
    _ = @import("rv32c_test.zig");
}
