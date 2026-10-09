const h = @import("../test_helpers.zig");

test "step: table (boundary)" {
    try h.expectSteps(&.{
        .{ .name = "BCLR bit 31", .inst = h.encodeOp(0b001, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 31 } }, .want = &.{.{ 3, 0x7FFFFFFF }} },
        .{ .name = "BINV bit 31", .inst = h.encodeOp(0b001, 0b0110100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 31 } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "BSET bit 31", .inst = h.encodeOp(0b001, 0b0010100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 31 } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "BEXT at bit 0", .inst = h.encodeOp(0b101, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFE }, .{ 2, 0 } }, .want = &.{.{ 3, 0 }} },
        .{ .name = "BINVI at bit 31 (immediate)", .inst = h.encodeOpImmShift(0b001, 0b0110100, 3, 1, 31), .regs = &.{.{ 1, 0x00000000 }}, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "BCLR with rs2 >= 32 (masking)", .inst = h.encodeOp(0b001, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 32 } }, .want = &.{.{ 3, 0xFFFFFFFE }} },
        .{ .name = "BEXT with rs2 >= 32 (masking)", .inst = h.encodeOp(0b101, 0b0100100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000001 }, .{ 2, 32 } }, .want = &.{.{ 3, 1 }} },
        .{ .name = "BINV with rs2 >= 32 (masking)", .inst = h.encodeOp(0b001, 0b0110100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 32 } }, .want = &.{.{ 3, 0x00000001 }} },
        .{ .name = "BSET with rs2 >= 32 (masking)", .inst = h.encodeOp(0b001, 0b0010100, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 33 } }, .want = &.{.{ 3, 0x00000002 }} },
        .{ .name = "BCLRI bit 31", .inst = h.encodeOpImmShift(0b001, 0b0100100, 3, 1, 31), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 0x7FFFFFFF }} },
        .{ .name = "BEXTI bit 0", .inst = h.encodeOpImmShift(0b101, 0b0100100, 3, 1, 0), .regs = &.{.{ 1, 0x00000001 }}, .want = &.{.{ 3, 1 }} },
        .{ .name = "BSETI bit 0", .inst = h.encodeOpImmShift(0b001, 0b0010100, 3, 1, 0), .regs = &.{.{ 1, 0x00000000 }}, .want = &.{.{ 3, 0x00000001 }} },
    });
}
