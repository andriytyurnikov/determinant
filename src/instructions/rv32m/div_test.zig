const h = @import("../test_helpers.zig");

// --- DIV execute tests ---

test "step: table (div)" {
    try h.expectSteps(&.{
        .{ .name = "DIV basic", .inst = h.encodeOp(0b100, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 20 }, .{ 2, 6 } }, .want = &.{.{ 3, 3 }} },
        .{ .name = "DIV signed negative", .inst = h.encodeOp(0b100, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, @as(u32, @bitCast(@as(i32, -20))) }, .{ 2, 6 } }, .want = &.{.{ 3, @as(u32, @bitCast(@as(i32, -3))) }} },
        .{ .name = "DIV by zero", .inst = h.encodeOp(0b100, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 0 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "DIV overflow INT_MIN / -1", .inst = h.encodeOp(0b100, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "DIV negative/negative", .inst = h.encodeOp(0b100, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, @as(u32, @bitCast(@as(i32, -20))) }, .{ 2, @as(u32, @bitCast(@as(i32, -6))) } }, .want = &.{.{ 3, 3 }} },
        .{ .name = "DIVU basic", .inst = h.encodeOp(0b101, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 20 }, .{ 2, 6 } }, .want = &.{.{ 3, 3 }} },
        .{ .name = "DIVU by zero", .inst = h.encodeOp(0b101, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 0 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "DIVU large unsigned", .inst = h.encodeOp(0b101, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 2 } }, .want = &.{.{ 3, 0x7FFFFFFF }} },
        .{ .name = "DIVU smaller divided by larger", .inst = h.encodeOp(0b101, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "REM basic", .inst = h.encodeOp(0b110, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 20 }, .{ 2, 6 } }, .want = &.{.{ 3, 2 }} },
        .{ .name = "REM signed negative", .inst = h.encodeOp(0b110, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, @as(u32, @bitCast(@as(i32, -20))) }, .{ 2, 6 } }, .want = &.{.{ 3, @as(u32, @bitCast(@as(i32, -2))) }} },
        .{ .name = "REM by zero", .inst = h.encodeOp(0b110, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 0 } }, .want = &.{.{ 3, 42 }} },
        .{ .name = "REM overflow INT_MIN / -1", .inst = h.encodeOp(0b110, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "REM positive/negative", .inst = h.encodeOp(0b110, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 20 }, .{ 2, @as(u32, @bitCast(@as(i32, -6))) } }, .want = &.{.{ 3, 2 }} },
        .{ .name = "REMU basic", .inst = h.encodeOp(0b111, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 20 }, .{ 2, 6 } }, .want = &.{.{ 3, 2 }} },
        .{ .name = "REMU by zero", .inst = h.encodeOp(0b111, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 42 }, .{ 2, 0 } }, .want = &.{.{ 3, 42 }} },
        .{ .name = "REMU large unsigned", .inst = h.encodeOp(0b111, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 2 } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "REMU smaller mod larger", .inst = h.encodeOp(0b111, 0b0000001, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0x80000000 }} },
    });
}
