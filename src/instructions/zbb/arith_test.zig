const h = @import("../test_helpers.zig");

// --- ANDN/ORN/XNOR execute tests ---

test "step: table (arith)" {
    try h.expectSteps(&.{
        .{ .name = "ANDN basic", .inst = h.encodeOp(0b111, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xFF00FF00 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0xF000F000 }} },
        .{ .name = "ORN basic", .inst = h.encodeOp(0b110, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xFF00FF00 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0xFFF0FFF0 }} },
        .{ .name = "XNOR basic", .inst = h.encodeOp(0b100, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xFF00FF00 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0x0FF00FF0 }} },
        .{ .name = "ANDN identity (mask=0)", .inst = h.encodeOp(0b111, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 0 } }, .want = &.{.{ 3, 0xDEADBEEF }} },
        .{ .name = "ORN identity (mask=all-ones)", .inst = h.encodeOp(0b110, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0xDEADBEEF }} },
        .{ .name = "XNOR self", .inst = h.encodeOp(0b100, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 0xDEADBEEF } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "MAX signed", .inst = h.encodeOp(0b110, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, @as(u32, @bitCast(@as(i32, -5))) }, .{ 2, 3 } }, .want = &.{.{ 3, 3 }} },
        .{ .name = "MAXU unsigned", .inst = h.encodeOp(0b111, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 3 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "MIN signed", .inst = h.encodeOp(0b100, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, @as(u32, @bitCast(@as(i32, -5))) }, .{ 2, 3 } }, .want = &.{.{ 3, @as(u32, @bitCast(@as(i32, -5))) }} },
        .{ .name = "MINU unsigned", .inst = h.encodeOp(0b101, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 3 } }, .want = &.{.{ 3, 3 }} },
        .{ .name = "MIN SIGNED_MIN vs SIGNED_MAX", .inst = h.encodeOp(0b100, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x7FFFFFFF } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "MAX SIGNED_MIN vs SIGNED_MAX", .inst = h.encodeOp(0b110, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x7FFFFFFF } }, .want = &.{.{ 3, 0x7FFFFFFF }} },
        .{ .name = "MINU with zero operand", .inst = h.encodeOp(0b101, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "MAXU equal values", .inst = h.encodeOp(0b111, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want = &.{.{ 3, 42 }} },
        .{ .name = "MIN equal operands", .inst = h.encodeOp(0b100, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want = &.{.{ 3, 42 }} },
        .{ .name = "MAX equal operands", .inst = h.encodeOp(0b110, 0b0000101, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want = &.{.{ 3, 42 }} },
    });
}
