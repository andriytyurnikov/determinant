const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const h = @import("../test_helpers.zig");

// --- Decode tests ---

test "decode R-type M-extension MUL MULH MULHSU MULHU DIV DIVU REM REMU" {
    const cases = .{
        .{ @as(u3, 0b000), @as(u7, 0b0000001), Opcode{ .m = .MUL } },
        .{ @as(u3, 0b001), @as(u7, 0b0000001), Opcode{ .m = .MULH } },
        .{ @as(u3, 0b010), @as(u7, 0b0000001), Opcode{ .m = .MULHSU } },
        .{ @as(u3, 0b011), @as(u7, 0b0000001), Opcode{ .m = .MULHU } },
        .{ @as(u3, 0b100), @as(u7, 0b0000001), Opcode{ .m = .DIV } },
        .{ @as(u3, 0b101), @as(u7, 0b0000001), Opcode{ .m = .DIVU } },
        .{ @as(u3, 0b110), @as(u7, 0b0000001), Opcode{ .m = .REM } },
        .{ @as(u3, 0b111), @as(u7, 0b0000001), Opcode{ .m = .REMU } },
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

// --- MUL execute tests ---

test "step: table (mul)" {
    try h.expectSteps(&.{
        .{ .name = "MUL basic", .inst = h.encodeOp(0b000, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 7 }, .{ 2, 6 } }, .want = &.{.{ 3, 42 }} },
        .{ .name = "MUL wrapping", .inst = h.encodeOp(0b000, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 2 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "MUL by zero", .inst = h.encodeOp(0b000, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 12345 }, .{ 2, 0 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "MUL neg1 times neg1", .inst = h.encodeOp(0b000, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "MULH signed positive", .inst = h.encodeOp(0b001, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x10000 }, .{ 2, 0x10000 } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "MULH signed negative", .inst = h.encodeOp(0b001, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "MULH large negative", .inst = h.encodeOp(0b001, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "MULHSU signed*unsigned", .inst = h.encodeOp(0b010, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 2 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "MULHSU positive", .inst = h.encodeOp(0b010, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x10000 }, .{ 2, 0x10000 } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "MULHU unsigned", .inst = h.encodeOp(0b011, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0xFFFFFFFE }} },
        .{ .name = "MULHU with zero", .inst = h.encodeOp(0b011, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "MULH SIGNED_MIN * SIGNED_MIN", .inst = h.encodeOp(0b001, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x80000000 } }, .want = &.{.{ 3, 0x40000000 }} },
        .{ .name = "MULHSU SIGNED_MIN * unsigned max", .inst = h.encodeOp(0b010, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "MULHU max times one", .inst = h.encodeOp(0b011, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want = &.{.{ 3, 0 }} },
    });
}
