/// Edge cases, invalid encodings, load variants, ZEXT_H, operand isolation tests.
const std = @import("std");
const decoder = @import("../branch.zig");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("../../instructions/test_helpers.zig");

// --- Edge cases ---

test "decode zero instruction (0x00000000) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(0x00000000));
}

test "decode all-ones instruction (0xFFFFFFFF) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(0xFFFFFFFF));
}

test "ECALL and EBREAK exact decode" {
    const ecall = try decoder.decode(0x00000073);
    try std.testing.expectEqual(Opcode{ .i = .ECALL }, ecall.op);
    const ebreak = try decoder.decode(0x00100073);
    try std.testing.expectEqual(Opcode{ .i = .EBREAK }, ebreak.op);
}

test "invalid R-type funct7 fallthrough is illegal" {
    const raw = h.encodeR(0b0110011, 0b000, 0b1111111, 4, 5, 6);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "I-type shift shamt extraction for SLLI" {
    const imm12: u12 = (@as(u12, 0b0000000) << 5) | 17;
    const raw = h.encodeI(0b0010011, 0b001, 3, 5, imm12);
    const inst = try decoder.decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .SLLI }, inst.op);
    try std.testing.expectEqual(@as(u5, 3), inst.rd);
    try std.testing.expectEqual(@as(u5, 5), inst.rs1);
    try std.testing.expectEqual(@as(i32, 17), inst.imm);
}

// --- Negative tests: invalid field combinations ---

test "decode: load invalid funct3=011 is illegal" {
    const raw = h.encodeI(0b0000011, 0b011, 1, 2, 0);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: store invalid funct3=011 is illegal" {
    const raw = h.encodeS(0b011, 1, 2, 0);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: branch invalid funct3=010 is illegal" {
    const raw = h.encodeB(0b010, 1, 2, 0);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: JALR invalid funct3=001 is illegal" {
    const raw = h.encodeI(0b1100111, 0b001, 1, 2, 0);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: atomic invalid funct3=000 is illegal" {
    // Encode atomic opcode with funct3=000 instead of 010
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 1) << 7) |
        (@as(u32, 0b000) << 12) |
        (@as(u32, 2) << 15) |
        (@as(u32, 3) << 20) |
        (@as(u32, @as(u7, 0b00010) << 2) << 25);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: atomic invalid funct5=0b11111 is illegal" {
    const raw = h.encodeAtomic(0b11111, 1, 2, 3);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

test "decode: system invalid funct3=0b100 is illegal" {
    const raw = h.encodeCsr(0b100, 1, 2, 0x340);
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}

// --- Load variant round-trips ---

test "I-type round-trip: LH" {
    try expectRoundTripI(0b0000011, 0b001, .{ .i = .LH });
}

test "I-type round-trip: LBU" {
    try expectRoundTripI(0b0000011, 0b100, .{ .i = .LBU });
}

test "I-type round-trip: LHU" {
    try expectRoundTripI(0b0000011, 0b101, .{ .i = .LHU });
}

fn expectRoundTripI(opcode: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u12{ 0, 1, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeI(opcode, f3, rd_v, rs1_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- ZEXT_H constraint tests ---

test "R-type round-trip: ZEXT_H (Zbb) with rs2=0" {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            const raw = h.encodeR(0b0110011, 0b100, 0b0000100, rd_v, rs1_v, 0);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(Opcode{ .zbb = .ZEXT_H }, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            try std.testing.expectEqual(rs1_v, inst.rs1);
        }
    }
}

test "decode: ZEXT_H encoding with rs2!=0 is illegal" {
    const test_rs2 = [_]u5{ 1, 15, 31 };
    for (test_rs2) |rs2_v| {
        const raw = h.encodeR(0b0110011, 0b100, 0b0000100, 4, 5, rs2_v);
        try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
    }
}

// --- Operand isolation tests ---

test "decode: ECALL operand isolation" {
    const inst = try decoder.decode(0x00000073);
    try std.testing.expectEqual(Opcode{ .i = .ECALL }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(u5, 0), inst.rs2);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

test "decode: EBREAK operand isolation" {
    const inst = try decoder.decode(0x00100073);
    try std.testing.expectEqual(Opcode{ .i = .EBREAK }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(u5, 0), inst.rs2);
}

test "decode: FENCE operand isolation" {
    const inst = try decoder.decode(0x0FF0000F);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
}

test "decode: minimal non-compressed 0x00000003 decodes as LB x0, 0(x0)" {
    // bits[1:0]=0b11 → 32-bit instruction, opcode=0b0000011 (LOAD), funct3=000 (LB)
    const inst = try decoder.decode(0x00000003);
    try std.testing.expectEqual(Opcode{ .i = .LB }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}
