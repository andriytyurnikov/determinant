/// Edge cases: invalid encodings, operand isolation, minimal instruction.
const std = @import("std");
const h = @import("test_helpers.zig");
const Opcode = h.Opcode;

// --- Edge cases ---

test "decode zero instruction (0x00000000) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, h.decodeFull(0x00000000));
}

test "decode all-ones instruction (0xFFFFFFFF) is illegal" {
    try std.testing.expectError(error.IllegalInstruction, h.decodeFull(0xFFFFFFFF));
}

test "decode: minimal non-compressed 0x00000003 decodes as LB x0, 0(x0)" {
    // bits[1:0]=0b11 → 32-bit instruction, opcode=0b0000011 (LOAD), funct3=000 (LB)
    const inst = try h.decodeFull(0x00000003);
    try std.testing.expectEqual(Opcode{ .i = .LB }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

test "decode: EBREAK operand isolation" {
    const inst = try h.decodeFull(0x00100073);
    try std.testing.expectEqual(Opcode{ .i = .EBREAK }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(u5, 0), inst.rs2);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}
