const h = @import("../test_helpers.zig");

// === Execute tests: branches ===

test "step: table (exec_branch)" {
    try h.expectSteps(&.{
        // BEQ x1, x2, +8 = 0x00208463
        .{ .name = "BEQ taken", .inst = 0x00208463, .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want_pc = 8 },
        // BEQ x1, x2, +8 = 0x00208463
        .{ .name = "BEQ not taken", .inst = 0x00208463, .regs = &.{ .{ 1, 1 }, .{ 2, 2 } }, .want_pc = 4 },
        // BNE x1, x2, +8 = 0x00209463
        .{ .name = "BNE taken", .inst = 0x00209463, .regs = &.{ .{ 1, 1 }, .{ 2, 2 } }, .want_pc = 8 },
        // BNE x1, x2, +8 = 0x00209463
        .{ .name = "BNE not taken", .inst = 0x00209463, .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want_pc = 4 },
        // BLT x1, x2, +8 = 0x0020C463
        .{ .name = "BLT signed", .inst = 0x0020C463, .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want_pc = 8 },
        // BGE x1, x2, +8 = 0x0020D463
        .{ .name = "BGE signed", .inst = 0x0020D463, .regs = &.{ .{ 1, 1 }, .{ 2, 0xFFFFFFFF } }, .want_pc = 8 },
        // BLTU x1, x2, +8 = 0x0020E463
        .{ .name = "BLTU unsigned", .inst = 0x0020E463, .regs = &.{ .{ 1, 1 }, .{ 2, 0xFFFFFFFF } }, .want_pc = 8 },
        // BLTU x1, x2, +8 = 0x0020E463
        .{ .name = "BLTU not taken", .inst = 0x0020E463, .regs = &.{ .{ 1, 2 }, .{ 2, 1 } }, .want_pc = 4 },
        // BGEU x1, x2, +8 = 0x0020F463
        .{ .name = "BGEU unsigned", .inst = 0x0020F463, .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want_pc = 8 },
        // BGEU x1, x2, +8 = 0x0020F463
        .{ .name = "BGEU not taken", .inst = 0x0020F463, .regs = &.{ .{ 1, 1 }, .{ 2, 2 } }, .want_pc = 4 },
        // BGEU x1, x2, +8
        .{ .name = "BGEU taken on equal operands", .inst = h.encodeB(0b111, 1, 2, 8), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x80000000 } }, .want_pc = 8 },
        // BLT x1, x2, +8
        .{ .name = "BLT not taken on equal operands", .inst = h.encodeB(0b100, 1, 2, 8), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0xFFFFFFFF } }, .want_pc = 4 },
    });
}
