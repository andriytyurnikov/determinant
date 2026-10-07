const h = @import("../../test_helpers.zig");

// ============================================================
// CPU step: ALU ops + stack ops
// ============================================================

test "step: table (cpu_alu)" {
    try h.expectSteps(&.{
        // C.SUB x8, x9 = 0x8C05
        .{ .name = "C.SUB", .inst = (0x0001 << 16) | 0x8C05, .regs = &.{ .{ 8, 20 }, .{ 9, 7 } }, .want = &.{.{ 8, 13 }} },
        // C.OR x8, x9 = 0x8C45
        .{ .name = "C.OR", .inst = (0x0001 << 16) | 0x8C45, .regs = &.{ .{ 8, 0xF0 }, .{ 9, 0x0F } }, .want = &.{.{ 8, 0xFF }} },
        // C.AND x8, x9 = 0x8C65
        .{ .name = "C.AND", .inst = (0x0001 << 16) | 0x8C65, .regs = &.{ .{ 8, 0xFF }, .{ 9, 0x0F } }, .want = &.{.{ 8, 0x0F }} },
        // C.XOR x8, x9 = 0x8C25
        .{ .name = "C.XOR", .inst = (0x0001 << 16) | 0x8C25, .regs = &.{ .{ 8, 0xFF00FF00 }, .{ 9, 0x0F0F0F0F } }, .want = &.{.{ 8, 0xF00FF00F }} },
        // C.SLLI x1, 4 = 0x0092
        .{ .name = "C.SLLI", .inst = (0x0001 << 16) | 0x0092, .regs = &.{.{ 1, 0x01 }}, .want = &.{.{ 1, 0x10 }} },
        // C.SRLI x8, 4 = 0x8011
        .{ .name = "C.SRLI", .inst = (0x0001 << 16) | 0x8011, .regs = &.{.{ 8, 0x80 }}, .want = &.{.{ 8, 0x08 }} },
        // C.SRAI x8, 1 = 0x8405
        .{ .name = "C.SRAI", .inst = (0x0001 << 16) | 0x8405, .regs = &.{.{ 8, 0x80000000 }}, .want = &.{.{ 8, 0xC0000000 }} },
        // C.ANDI x8, 3 = 0x880D
        .{ .name = "C.ANDI", .inst = (0x0001 << 16) | 0x880D, .regs = &.{.{ 8, 0xFF }}, .want = &.{.{ 8, 3 }} },
        // C.ADDI4SPN x8, x2, 8 = 0x0020
        .{ .name = "C.ADDI4SPN", .inst = (0x0001 << 16) | 0x0020, .regs = &.{.{ 2, 1000 }}, .want = &.{.{ 8, 1008 }} },
        // C.ADDI16SP x2, 16 = 0x6141
        .{ .name = "C.ADDI16SP", .inst = (0x0001 << 16) | 0x6141, .regs = &.{.{ 2, 1000 }}, .want = &.{.{ 2, 1016 }} },
    });
}
