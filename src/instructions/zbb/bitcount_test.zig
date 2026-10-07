const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const h = @import("../test_helpers.zig");

// --- Decode tests ---

test "decode Zbb R-type ANDN ORN XNOR MIN MINU MAX MAXU ROL ROR" {
    const cases = .{
        .{ @as(u3, 0b111), @as(u7, 0b0100000), Opcode{ .zbb = .ANDN } },
        .{ @as(u3, 0b110), @as(u7, 0b0100000), Opcode{ .zbb = .ORN } },
        .{ @as(u3, 0b100), @as(u7, 0b0100000), Opcode{ .zbb = .XNOR } },
        .{ @as(u3, 0b100), @as(u7, 0b0000101), Opcode{ .zbb = .MIN } },
        .{ @as(u3, 0b101), @as(u7, 0b0000101), Opcode{ .zbb = .MINU } },
        .{ @as(u3, 0b110), @as(u7, 0b0000101), Opcode{ .zbb = .MAX } },
        .{ @as(u3, 0b111), @as(u7, 0b0000101), Opcode{ .zbb = .MAXU } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), Opcode{ .zbb = .ROL } },
        .{ @as(u3, 0b101), @as(u7, 0b0110000), Opcode{ .zbb = .ROR } },
    };
    inline for (cases) |c| {
        const raw = h.encodeOp(c[0], c[1], 4, 5, 6);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
        try std.testing.expectEqual(@as(u5, 4), inst.rd);
        try std.testing.expectEqual(@as(u5, 5), inst.rs1);
        try std.testing.expectEqual(@as(u5, 6), inst.rs2);
    }
}

test "decode Zbb R-type ZEXT_H" {
    const raw = h.encodeOp(0b100, 0b0000100, 4, 5, 0); // rs2=0 required
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .zbb = .ZEXT_H }, inst.op);
}

test "decode Zbb I-type CLZ CTZ CPOP SEXT_B SEXT_H RORI ORC_B REV8" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 0), Opcode{ .zbb = .CLZ } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 1), Opcode{ .zbb = .CTZ } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 2), Opcode{ .zbb = .CPOP } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 4), Opcode{ .zbb = .SEXT_B } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 5), Opcode{ .zbb = .SEXT_H } },
        .{ @as(u3, 0b101), @as(u7, 0b0110000), @as(u5, 3), Opcode{ .zbb = .RORI } },
        .{ @as(u3, 0b101), @as(u7, 0b0010100), @as(u5, 7), Opcode{ .zbb = .ORC_B } },
        .{ @as(u3, 0b101), @as(u7, 0b0110100), @as(u5, 24), Opcode{ .zbb = .REV8 } },
    };
    inline for (cases) |c| {
        const raw = h.encodeOpImmShift(c[0], c[1], 4, 5, c[2]);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[3], inst.op);
    }
}

// --- CLZ/CTZ/CPOP execute tests ---

test "step: table (bitcount)" {
    try h.expectSteps(&.{
        .{ .name = "CLZ zero", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 0), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 32 }} },
        .{ .name = "CLZ one", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 0), .regs = &.{.{ 1, 1 }}, .want = &.{.{ 3, 31 }} },
        .{ .name = "CLZ high bit", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 0), .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "CLZ all-ones", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 0), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "CTZ zero", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 1), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 32 }} },
        .{ .name = "CTZ low bit", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 1), .regs = &.{.{ 1, 1 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "CTZ trailing zeros", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 1), .regs = &.{.{ 1, 0x80 }}, .want = &.{.{ 3, 7 }} },
        .{ .name = "CTZ all-ones", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 1), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "CPOP zero", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 2), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "CPOP all ones", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 2), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 32 }} },
        .{ .name = "CPOP mixed", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 2), .regs = &.{.{ 1, 0x0F0F0F0F }}, .want = &.{.{ 3, 16 }} },
        .{ .name = "CPOP single bit low", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 2), .regs = &.{.{ 1, 0x00000001 }}, .want = &.{.{ 3, 1 }} },
        .{ .name = "CPOP single bit high", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 2), .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 3, 1 }} },
    });
}
