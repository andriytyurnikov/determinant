/// RV32C compressed instruction expansion.
/// Every 16-bit compressed instruction maps to an existing RV32I instruction.
/// Unlike other extensions, rv32c has its own Opcode enum for decode/display purposes only —
/// it is NOT part of the instructions.Opcode tagged union (no execution path, no format).
const fmt = @import("format.zig");
const rv32i = @import("rv32i.zig");

/// RV32C compressed instruction opcodes (26 variants).
/// Used for self-documenting decode and display (e.g. showing "C.LW" instead of "LW").
pub const Opcode = enum {
    // Quadrant 0
    C_ADDI4SPN,
    C_LW,
    C_SW,
    // Quadrant 1
    C_ADDI, // includes C.NOP (rd=0, imm=0)
    C_JAL,
    C_LI,
    C_ADDI16SP,
    C_LUI,
    C_SRLI,
    C_SRAI,
    C_ANDI,
    C_SUB,
    C_XOR,
    C_OR,
    C_AND,
    C_J,
    C_BEQZ,
    C_BNEZ,
    // Quadrant 2
    C_SLLI,
    C_LWSP,
    C_JR,
    C_MV,
    C_EBREAK,
    C_JALR,
    C_ADD,
    C_SWSP,

    pub fn meta(comptime self: Opcode) struct { name_str: []const u8 } {
        return .{ .name_str = comptime dotName(@tagName(self)) };
    }

    pub fn name(self: Opcode) []const u8 {
        return fmt.opcodeName(Opcode, self);
    }

    fn dotName(comptime tag: []const u8) []const u8 {
        comptime {
            if (tag.len < 2 or tag[0] != 'C' or tag[1] != '_')
                @compileError("expected C_ prefix on rv32c opcode tag");
            var buf: [tag.len]u8 = tag[0..tag.len].*;
            buf[1] = '.';
            const final = buf;
            return &final;
        }
    }
};

/// Expanded compressed instruction — uses rv32i.Opcode directly (sibling-only dependency).
/// The decoder wraps this into a full Instruction with .op = .{ .i = exp.op }.
pub const Expanded = struct {
    op: rv32i.Opcode,
    rd: u5 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm: i32 = 0,
    raw: u32,
};

/// Decode a 16-bit compressed instruction into its Opcode.
/// Only fails on truly invalid bit combinations (unknown funct3, reserved funct2b).
/// Does NOT validate operand constraints (nzuimm=0, shamt[5]=1) — that stays in expand().
pub fn decode(half: u16) error{IllegalInstruction}!Opcode {
    return switch (@as(u2, @truncate(half))) {
        0b00 => decodeQ0(half),
        0b01 => decodeQ1(half),
        0b10 => decodeQ2(half),
        0b11 => error.IllegalInstruction, // not compressed
    };
}

fn decodeQ0(half: u16) error{IllegalInstruction}!Opcode {
    return switch (funct3(half)) {
        0b000 => .C_ADDI4SPN,
        0b010 => .C_LW,
        0b110 => .C_SW,
        else => error.IllegalInstruction,
    };
}

fn decodeQ1(half: u16) error{IllegalInstruction}!Opcode {
    return switch (funct3(half)) {
        0b000 => .C_ADDI,
        0b001 => .C_JAL,
        0b010 => .C_LI,
        0b011 => {
            const rd_val: u5 = @truncate(half >> 7);
            return if (rd_val == 2) .C_ADDI16SP else .C_LUI;
        },
        0b100 => decodeQ1Alu(half),
        0b101 => .C_J,
        0b110 => .C_BEQZ,
        0b111 => .C_BNEZ,
    };
}

fn decodeQ1Alu(half: u16) error{IllegalInstruction}!Opcode {
    const funct2: u2 = @truncate(half >> 10);
    return switch (funct2) {
        0b00 => .C_SRLI,
        0b01 => .C_SRAI,
        0b10 => .C_ANDI,
        0b11 => {
            const funct1: u1 = @truncate(half >> 12);
            if (funct1 != 0) return error.IllegalInstruction; // bit 12=1 reserved on RV32C
            const funct2b: u2 = @truncate(half >> 5);
            return switch (funct2b) {
                0b00 => .C_SUB,
                0b01 => .C_XOR,
                0b10 => .C_OR,
                0b11 => .C_AND,
            };
        },
    };
}

fn decodeQ2(half: u16) error{IllegalInstruction}!Opcode {
    return switch (funct3(half)) {
        0b000 => .C_SLLI,
        0b010 => .C_LWSP,
        0b100 => {
            const bit12: u1 = @truncate(half >> 12);
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            if (bit12 == 0) {
                return if (rs2_val == 0) .C_JR else .C_MV;
            } else {
                if (rs2_val == 0) {
                    return if (rd_rs1 == 0) .C_EBREAK else .C_JALR;
                } else {
                    return .C_ADD;
                }
            }
        },
        0b110 => .C_SWSP,
        else => error.IllegalInstruction,
    };
}

/// Expand a 16-bit compressed instruction into its equivalent Expanded form.
/// The `raw` field stores the 16-bit value zero-extended to u32.
pub fn expand(half: u16) error{IllegalInstruction}!Expanded {
    const op = try decode(half);
    const raw: u32 = half;
    return switch (op) {
        .C_ADDI4SPN => {
            const nzu = ciw_nzuimm(half);
            if (nzu == 0) return error.IllegalInstruction;
            return .{
                .op = .ADDI,
                .rd = cReg(@truncate(half >> 2)),
                .rs1 = 2, // x2 = sp
                .imm = @intCast(nzu),
                .raw = raw,
            };
        },
        .C_LW => .{
            .op = .LW,
            .rd = cReg(@truncate(half >> 2)),
            .rs1 = cReg(@truncate(half >> 7)),
            .imm = @intCast(clsw_offset(half)),
            .raw = raw,
        },
        .C_SW => .{
            .op = .SW,
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = cReg(@truncate(half >> 2)),
            .imm = @intCast(clsw_offset(half)),
            .raw = raw,
        },
        .C_ADDI => {
            const rd_val: u5 = @truncate(half >> 7);
            return .{
                .op = .ADDI,
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = ci_imm(half),
                .raw = raw,
            };
        },
        .C_JAL => .{
            .op = .JAL,
            .rd = 1, // ra
            .imm = cj_offset(half),
            .raw = raw,
        },
        .C_LI => {
            const rd_val: u5 = @truncate(half >> 7);
            return .{
                .op = .ADDI,
                .rd = rd_val,
                .rs1 = 0,
                .imm = ci_imm(half),
                .raw = raw,
            };
        },
        .C_ADDI16SP => {
            const imm = ci_addi16sp_imm(half);
            if (imm == 0) return error.IllegalInstruction;
            return .{
                .op = .ADDI,
                .rd = 2,
                .rs1 = 2,
                .imm = imm,
                .raw = raw,
            };
        },
        .C_LUI => {
            const imm = ci_lui_imm(half);
            if (imm == 0) return error.IllegalInstruction;
            return .{
                .op = .LUI,
                .rd = @truncate(half >> 7),
                .imm = imm,
                .raw = raw,
            };
        },
        .C_SRLI => {
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            const rd_rs1 = cReg(@truncate(half >> 7));
            return .{
                .op = .SRLI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .raw = raw,
            };
        },
        .C_SRAI => {
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            const rd_rs1 = cReg(@truncate(half >> 7));
            return .{
                .op = .SRAI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .raw = raw,
            };
        },
        .C_ANDI => {
            const rd_rs1 = cReg(@truncate(half >> 7));
            return .{
                .op = .ANDI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = ci_imm(half),
                .raw = raw,
            };
        },
        .C_SUB, .C_XOR, .C_OR, .C_AND => {
            const rd_rs1 = cReg(@truncate(half >> 7));
            const rs2_val = cReg(@truncate(half >> 2));
            const base_op: rv32i.Opcode = switch (op) {
                .C_SUB => .SUB,
                .C_XOR => .XOR,
                .C_OR => .OR,
                .C_AND => .AND,
                else => unreachable,
            };
            return .{ .op = base_op, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .raw = raw };
        },
        .C_J => .{
            .op = .JAL,
            .rd = 0,
            .imm = cj_offset(half),
            .raw = raw,
        },
        .C_BEQZ => .{
            .op = .BEQ,
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = cb_offset(half),
            .raw = raw,
        },
        .C_BNEZ => .{
            .op = .BNE,
            .rs1 = cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = cb_offset(half),
            .raw = raw,
        },
        .C_SLLI => {
            const rd_val: u5 = @truncate(half >> 7);
            const shamt = ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            return .{
                .op = .SLLI,
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = @intCast(shamt & 0x1F),
                .raw = raw,
            };
        },
        .C_LWSP => {
            const rd_val: u5 = @truncate(half >> 7);
            if (rd_val == 0) return error.IllegalInstruction;
            return .{
                .op = .LW,
                .rd = rd_val,
                .rs1 = 2, // sp
                .imm = @intCast(ci_lwsp_offset(half)),
                .raw = raw,
            };
        },
        .C_JR => {
            const rd_rs1: u5 = @truncate(half >> 7);
            if (rd_rs1 == 0) return error.IllegalInstruction;
            return .{
                .op = .JALR,
                .rd = 0,
                .rs1 = rd_rs1,
                .imm = 0,
                .raw = raw,
            };
        },
        .C_MV => {
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            return .{
                .op = .ADD,
                .rd = rd_rs1,
                .rs1 = 0,
                .rs2 = rs2_val,
                .raw = raw,
            };
        },
        .C_EBREAK => .{
            .op = .EBREAK,
            .raw = raw,
        },
        .C_JALR => {
            const rd_rs1: u5 = @truncate(half >> 7);
            return .{
                .op = .JALR,
                .rd = 1, // ra
                .rs1 = rd_rs1,
                .imm = 0,
                .raw = raw,
            };
        },
        .C_ADD => {
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            return .{
                .op = .ADD,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .rs2 = rs2_val,
                .raw = raw,
            };
        },
        .C_SWSP => .{
            .op = .SW,
            .rs1 = 2, // sp
            .rs2 = @truncate(half >> 2),
            .imm = @intCast(css_swsp_offset(half)),
            .raw = raw,
        },
    };
}

/// Map 3-bit compressed register field to x8-x15.
fn cReg(r: u3) u5 {
    return @as(u5, r) + 8;
}

/// Extract bits [15:13] — the funct3 field for compressed instructions.
fn funct3(half: u16) u3 {
    return @truncate(half >> 13);
}

// ============================================================
// Immediate extraction helpers
// ============================================================

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
