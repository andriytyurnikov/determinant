const h = @import("../../test_helpers.zig");

// === CPU step tests: compressed branches ===

test "step: table (cpu_branch)" {
    try h.expectSteps(&.{
        // x8 = 0 by default
        .{ .name = "C.BEQZ taken", .inst = 0xC011, .mem = &.{.{ 4, 0x00000073 }}, .want_pc = 4 },
        // C.BEQZ x8, 4
        .{ .name = "C.BEQZ not-taken (x8 != 0)", .inst = (0x0001 << 16) | 0xC011, .regs = &.{.{ 8, 1 }}, .want_pc = 2 },
        // C.BNEZ x8, 4 = 0xE011
        .{ .name = "C.BNEZ taken (x8 != 0)", .inst = 0xE011, .regs = &.{.{ 8, 1 }}, .mem = &.{.{ 4, 0x00000073 }}, .want_pc = 4 },
        // x8 = 0 by default → branch not taken
        .{ .name = "C.BNEZ not-taken (x8 == 0)", .inst = (0x0001 << 16) | 0xE011, .want_pc = 2 },
    });
}
