/// Round-trip tests verifying decode(encode(x)) == x for all instruction formats.
/// These tests convert implicit algorithmic coupling between encoder (test_helpers)
/// and decoder (decoder.zig) into explicit verified coupling.
const std = @import("std");
const decoder = @import("decoder.zig");
const instructions = @import("instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("instructions/test_helpers.zig");

// --- R-type round-trip ---

test "R-type round-trip: ADD" {
    try expectRoundTripR(0b0000000, 0b000, .{ .i = .ADD });
}

test "R-type round-trip: SUB" {
    try expectRoundTripR(0b0100000, 0b000, .{ .i = .SUB });
}

test "R-type round-trip: SLL" {
    try expectRoundTripR(0b0000000, 0b001, .{ .i = .SLL });
}

test "R-type round-trip: SLT" {
    try expectRoundTripR(0b0000000, 0b010, .{ .i = .SLT });
}

test "R-type round-trip: SLTU" {
    try expectRoundTripR(0b0000000, 0b011, .{ .i = .SLTU });
}

test "R-type round-trip: XOR" {
    try expectRoundTripR(0b0000000, 0b100, .{ .i = .XOR });
}

test "R-type round-trip: SRL" {
    try expectRoundTripR(0b0000000, 0b101, .{ .i = .SRL });
}

test "R-type round-trip: SRA" {
    try expectRoundTripR(0b0100000, 0b101, .{ .i = .SRA });
}

test "R-type round-trip: OR" {
    try expectRoundTripR(0b0000000, 0b110, .{ .i = .OR });
}

test "R-type round-trip: AND" {
    try expectRoundTripR(0b0000000, 0b111, .{ .i = .AND });
}

test "R-type round-trip: MUL (M-ext)" {
    try expectRoundTripR(0b0000001, 0b000, .{ .m = .MUL });
}

fn expectRoundTripR(f7: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_regs) |rs2_v| {
                const raw = h.encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
            }
        }
    }
}

// --- I-type round-trip ---

test "I-type round-trip: ADDI" {
    try expectRoundTripI(0b0010011, 0b000, .{ .i = .ADDI });
}

test "I-type round-trip: SLTI" {
    try expectRoundTripI(0b0010011, 0b010, .{ .i = .SLTI });
}

test "I-type round-trip: XORI" {
    try expectRoundTripI(0b0010011, 0b100, .{ .i = .XORI });
}

test "I-type round-trip: ORI" {
    try expectRoundTripI(0b0010011, 0b110, .{ .i = .ORI });
}

test "I-type round-trip: ANDI" {
    try expectRoundTripI(0b0010011, 0b111, .{ .i = .ANDI });
}

test "I-type round-trip: LB" {
    try expectRoundTripI(0b0000011, 0b000, .{ .i = .LB });
}

test "I-type round-trip: LW" {
    try expectRoundTripI(0b0000011, 0b010, .{ .i = .LW });
}

test "I-type round-trip: JALR" {
    try expectRoundTripI(0b1100111, 0b000, .{ .i = .JALR });
}

fn expectRoundTripI(opcode: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // Test various immediate values including sign-extension boundary cases
    const test_imms = [_]u12{ 0, 1, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeI(opcode, f3, rd_v, rs1_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                // Verify immediate: sign-extend u12 → i32
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- S-type round-trip ---

test "S-type round-trip: SB" {
    try expectRoundTripS(0b000, .{ .i = .SB });
}

test "S-type round-trip: SH" {
    try expectRoundTripS(0b001, .{ .i = .SH });
}

test "S-type round-trip: SW" {
    try expectRoundTripS(0b010, .{ .i = .SW });
}

fn expectRoundTripS(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u12{ 0, 1, 0x1F, 0x7E0, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeS(f3, rs1_v, rs2_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- B-type round-trip ---

test "B-type round-trip: BEQ" {
    try expectRoundTripB(0b000, .{ .i = .BEQ });
}

test "B-type round-trip: BNE" {
    try expectRoundTripB(0b001, .{ .i = .BNE });
}

test "B-type round-trip: BLT" {
    try expectRoundTripB(0b100, .{ .i = .BLT });
}

test "B-type round-trip: BGE" {
    try expectRoundTripB(0b101, .{ .i = .BGE });
}

test "B-type round-trip: BLTU" {
    try expectRoundTripB(0b110, .{ .i = .BLTU });
}

test "B-type round-trip: BGEU" {
    try expectRoundTripB(0b111, .{ .i = .BGEU });
}

fn expectRoundTripB(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // B-type immediates have bit 0 always 0, range -4096..4094 (13-bit signed, even)
    const test_imms = [_]i13{ 0, 2, 4, -2, -4, 0x7FE, -0x1000, 0xE };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm_val| {
                const raw = h.encodeB(f3, rs1_v, rs2_v, imm_val);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = imm_val;
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- U-type round-trip ---

test "U-type round-trip: LUI" {
    try expectRoundTripU(0b0110111, .{ .i = .LUI });
}

test "U-type round-trip: AUIPC" {
    try expectRoundTripU(0b0010111, .{ .i = .AUIPC });
}

fn expectRoundTripU(opcode: u7, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u20{ 0, 1, 0x7FFFF, 0x80000, 0xFFFFF };
    for (test_regs) |rd_v| {
        for (test_imms) |imm20| {
            const raw = h.encodeU(opcode, rd_v, imm20);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(expected_op, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            // U-type immediate is stored as the upper 20 bits (shifted left 12)
            const expected_imm: i32 = @bitCast(@as(u32, imm20) << 12);
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

// --- J-type round-trip ---

test "J-type round-trip: JAL" {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // J-type immediates have bit 0 always 0, range ±1 MiB (21-bit signed, even)
    const test_imms = [_]i21{ 0, 2, 4, -2, -4, 0x7FE, -0x100000, 0xFFFFE };
    for (test_regs) |rd_v| {
        for (test_imms) |imm_val| {
            const raw = h.encodeJ(rd_v, imm_val);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            const expected_imm: i32 = imm_val;
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

// --- Atomic round-trip ---

test "Atomic round-trip: all RV32A opcodes" {
    const cases = .{
        .{ @as(u5, 0b00010), Opcode{ .a = .LR_W } },
        .{ @as(u5, 0b00011), Opcode{ .a = .SC_W } },
        .{ @as(u5, 0b00001), Opcode{ .a = .AMOSWAP_W } },
        .{ @as(u5, 0b00000), Opcode{ .a = .AMOADD_W } },
        .{ @as(u5, 0b00100), Opcode{ .a = .AMOXOR_W } },
        .{ @as(u5, 0b01100), Opcode{ .a = .AMOAND_W } },
        .{ @as(u5, 0b01000), Opcode{ .a = .AMOOR_W } },
        .{ @as(u5, 0b10000), Opcode{ .a = .AMOMIN_W } },
        .{ @as(u5, 0b10100), Opcode{ .a = .AMOMAX_W } },
        .{ @as(u5, 0b11000), Opcode{ .a = .AMOMINU_W } },
        .{ @as(u5, 0b11100), Opcode{ .a = .AMOMAXU_W } },
    };
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    inline for (cases) |c| {
        for (test_regs) |rd_v| {
            for (test_regs) |rs1_v| {
                for (test_regs) |rs2_v| {
                    const raw = h.encodeAtomic(c[0], rd_v, rs1_v, rs2_v);
                    const inst = try decoder.decode(raw);
                    try std.testing.expectEqual(c[1], inst.op);
                    try std.testing.expectEqual(rd_v, inst.rd);
                    try std.testing.expectEqual(rs1_v, inst.rs1);
                    try std.testing.expectEqual(rs2_v, inst.rs2);
                }
            }
        }
    }
}

// --- CSR round-trip ---

test "CSR round-trip: CSRRW" {
    try expectRoundTripCsr(0b001, .{ .csr = .CSRRW });
}

test "CSR round-trip: CSRRS" {
    try expectRoundTripCsr(0b010, .{ .csr = .CSRRS });
}

test "CSR round-trip: CSRRC" {
    try expectRoundTripCsr(0b011, .{ .csr = .CSRRC });
}

test "CSR round-trip: CSRRWI" {
    try expectRoundTripCsr(0b101, .{ .csr = .CSRRWI });
}

test "CSR round-trip: CSRRSI" {
    try expectRoundTripCsr(0b110, .{ .csr = .CSRRSI });
}

test "CSR round-trip: CSRRCI" {
    try expectRoundTripCsr(0b111, .{ .csr = .CSRRCI });
}

// --- FENCE ---

test "FENCE round-trip" {
    // Standard FENCE iorw,iorw = 0x0FF0000F
    const inst = try decoder.decode(0x0FF0000F);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
}

test "FENCE with invalid funct3 is illegal" {
    // opcode=0b0001111, funct3=001 (FENCE.I, not implemented)
    const raw: u32 = (0b001 << 12) | 0b0001111;
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

// --- Edge cases ---

test "decode zero instruction (0x00000000) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(0x00000000));
}

test "decode all-ones instruction (0xFFFFFFFF) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(0xFFFFFFFF));
}

fn expectRoundTripCsr(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_addrs = [_]u12{ 0x000, 0xC00, 0xC80, 0x340, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_addrs) |csr_addr| {
                const raw = h.encodeCsr(f3, rd_v, rs1_v, csr_addr);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                // CSR address is in upper 12 bits, decoded as sign-extended I-type immediate
                const expected_imm: i32 = @as(i12, @bitCast(csr_addr));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}
