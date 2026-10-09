const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const h = @import("../test_helpers.zig");

// --- Decode tests ---

test "decode Zbs R-type BCLR BEXT BINV BSET" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0100100), Opcode{ .zbs = .BCLR } },
        .{ @as(u3, 0b101), @as(u7, 0b0100100), Opcode{ .zbs = .BEXT } },
        .{ @as(u3, 0b001), @as(u7, 0b0110100), Opcode{ .zbs = .BINV } },
        .{ @as(u3, 0b001), @as(u7, 0b0010100), Opcode{ .zbs = .BSET } },
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

test "decode Zbs I-type BCLRI BEXTI BINVI BSETI" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0100100), Opcode{ .zbs = .BCLRI } },
        .{ @as(u3, 0b101), @as(u7, 0b0100100), Opcode{ .zbs = .BEXTI } },
        .{ @as(u3, 0b001), @as(u7, 0b0110100), Opcode{ .zbs = .BINVI } },
        .{ @as(u3, 0b001), @as(u7, 0b0010100), Opcode{ .zbs = .BSETI } },
    };
    inline for (cases) |c| {
        const raw = h.encodeOpImmShift(c[0], c[1], 4, 5, 3); // shamt=3
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
    }
}

// --- Execute tests ---

test "step: table (decode_exec)" {
    try h.expectSteps(&.{
        .{ .name = "BCLR basic", .inst = h.encodeOp(0b001, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 5 } }, .want = &.{.{ 3, 0xFFFFFFDF }} },
        .{ .name = "BCLRI basic", .inst = h.encodeOpImmShift(0b001, 0b0100100, 3, 1, 0), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 0xFFFFFFFE }} },
        .{ .name = "BEXT basic", .inst = h.encodeOp(0b101, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000020 }, .{ 2, 5 } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "BEXT zero", .inst = h.encodeOp(0b101, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000020 }, .{ 2, 4 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "BEXTI basic", .inst = h.encodeOpImmShift(0b101, 0b0100100, 3, 1, 31), .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 3, 1 }} },
        .{ .name = "BINV basic", .inst = h.encodeOp(0b001, 0b0110100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 5 } }, .want = &.{.{ 3, 0x00000020 }} },
        .{ .name = "BINVI toggle", .inst = h.encodeOpImmShift(0b001, 0b0110100, 3, 1, 5), .regs = &.{.{ 1, 0x00000020 }}, .want = &.{.{ 3, 0x00000000 }} },
        .{ .name = "BSET basic", .inst = h.encodeOp(0b001, 0b0010100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 5 } }, .want = &.{.{ 3, 0x00000020 }} },
        .{ .name = "BSETI basic", .inst = h.encodeOpImmShift(0b001, 0b0010100, 3, 1, 31), .regs = &.{.{ 1, 0x00000000 }}, .want = &.{.{ 3, 0x80000000 }} },
    });
}
