const h = @import("../test_helpers.zig");

// --- SEXT_B execute tests ---

test "step: table (sext)" {
    try h.expectSteps(&.{
        .{ .name = "SEXT_B positive", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 4), .regs = &.{.{ 1, 0x0000007F }}, .want = &.{.{ 3, 0x0000007F }} },
        .{ .name = "SEXT_B negative", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 4), .regs = &.{.{ 1, 0x00000080 }}, .want = &.{.{ 3, 0xFFFFFF80 }} },
        .{ .name = "SEXT_B with upper bits set", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 4), .regs = &.{.{ 1, 0xDEAD0080 }}, .want = &.{.{ 3, 0xFFFFFF80 }} },
        .{ .name = "SEXT_B boundary 0xFF", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 4), .regs = &.{.{ 1, 0x000000FF }}, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "SEXT_B zero", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 4), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "SEXT_H positive", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 5), .regs = &.{.{ 1, 0x00007FFF }}, .want = &.{.{ 3, 0x00007FFF }} },
        .{ .name = "SEXT_H negative", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 5), .regs = &.{.{ 1, 0x00008000 }}, .want = &.{.{ 3, 0xFFFF8000 }} },
        .{ .name = "SEXT_H with upper bits set", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 5), .regs = &.{.{ 1, 0xDEAD8000 }}, .want = &.{.{ 3, 0xFFFF8000 }} },
        .{ .name = "SEXT_H boundary 0xFFFF", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 5), .regs = &.{.{ 1, 0x0000FFFF }}, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "SEXT_H zero", .inst = h.encodeOpImmShift(0b001, 0b0110000, 3, 1, 5), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "ZEXT_H basic", .inst = h.encodeOp(0b100, 0b0000100, 3, 1, 0), .regs = &.{.{ 1, 0xDEADBEEF }}, .want = &.{.{ 3, 0x0000BEEF }} },
        .{ .name = "ZEXT_H zero", .inst = h.encodeOp(0b100, 0b0000100, 3, 1, 0), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "ZEXT_H max halfword", .inst = h.encodeOp(0b100, 0b0000100, 3, 1, 0), .regs = &.{.{ 1, 0x0000FFFF }}, .want = &.{.{ 3, 0xFFFF }} },
    });
}
