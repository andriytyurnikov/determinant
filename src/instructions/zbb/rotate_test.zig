const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// --- ROL/ROR/RORI execute tests ---

test "step: table (rotate)" {
    try h.expectSteps(&.{
        .{ .name = "ROL basic", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000001 }, .{ 2, 1 } }, .want = &.{.{ 3, 0x00000003 }} },
        .{ .name = "ROL by zero", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 0 } }, .want = &.{.{ 3, 0xDEADBEEF }} },
        .{ .name = "ROL by 31", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x00000001 }, .{ 2, 31 } }, .want = &.{.{ 3, 0x80000000 }} },
        .{ .name = "ROL with high rs2 (shift amount masking)", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000001 }, .{ 2, 0x21 } }, .want = &.{.{ 3, 0x00000003 }} },
        .{ .name = "ROL all-zeros unchanged", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 13 } }, .want = &.{.{ 3, 0x00000000 }} },
        .{ .name = "ROL all-ones unchanged", .inst = h.encodeOp(0b001, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 13 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "ROR basic", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000001 }, .{ 2, 1 } }, .want = &.{.{ 3, 0xC0000000 }} },
        .{ .name = "ROR by zero", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 0 } }, .want = &.{.{ 3, 0xDEADBEEF }} },
        .{ .name = "ROR by 31", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x00000001 }, .{ 2, 31 } }, .want = &.{.{ 3, 0x00000002 }} },
        .{ .name = "ROR with high rs2 (shift amount masking)", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000001 }, .{ 2, 0x21 } }, .want = &.{.{ 3, 0xC0000000 }} },
        .{ .name = "ROR all-zeros unchanged", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0x00000000 }, .{ 2, 7 } }, .want = &.{.{ 3, 0x00000000 }} },
        .{ .name = "ROR all-ones unchanged", .inst = h.encodeOp(0b101, 0b0110000, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 7 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "RORI basic", .inst = h.encodeOpImmShift(0b101, 0b0110000, 3, 1, 1), .regs = &.{.{ 1, 0x80000001 }}, .want = &.{.{ 3, 0xC0000000 }} },
        .{ .name = "RORI by zero", .inst = h.encodeOpImmShift(0b101, 0b0110000, 3, 1, 0), .regs = &.{.{ 1, 0xDEADBEEF }}, .want = &.{.{ 3, 0xDEADBEEF }} },
        .{ .name = "RORI shamt=31", .inst = h.encodeOpImmShift(0b101, 0b0110000, 3, 1, 31), .regs = &.{.{ 1, 0x00000001 }}, .want = &.{.{ 3, 0x00000002 }} },
        .{ .name = "ORC_B mixed", .inst = h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7), .regs = &.{.{ 1, 0x00010200 }}, .want = &.{.{ 3, 0x00FFFF00 }} },
        .{ .name = "ORC_B all zero", .inst = h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "ORC_B all nonzero", .inst = h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7), .regs = &.{.{ 1, 0x01010101 }}, .want = &.{.{ 3, 0xFFFFFFFF }} },
        .{ .name = "REV8 basic", .inst = h.encodeOpImmShift(0b101, 0b0110100, 3, 1, 24), .regs = &.{.{ 1, 0x01020304 }}, .want = &.{.{ 3, 0x04030201 }} },
        .{ .name = "REV8 palindrome", .inst = h.encodeOpImmShift(0b101, 0b0110100, 3, 1, 24), .regs = &.{.{ 1, 0xAAAAAAAA }}, .want = &.{.{ 3, 0xAAAAAAAA }} },
        .{ .name = "REV8 zero", .inst = h.encodeOpImmShift(0b101, 0b0110100, 3, 1, 24), .regs = &.{.{ 1, 0x00000000 }}, .want = &.{.{ 3, 0 }} },
        .{ .name = "REV8 all-ones", .inst = h.encodeOpImmShift(0b101, 0b0110100, 3, 1, 24), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 3, 0xFFFFFFFF }} },
    });
}

// --- ORC_B execute tests ---

test "step: ORC_B single byte in each position" {
    var cpu = Cpu.init();
    // Byte 0 only
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(0x000000FF, cpu.readReg(3));

    // Byte 1 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00000100);
    loadInst(&cpu, h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(0x0000FF00, cpu.readReg(3));

    // Byte 2 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00010000);
    loadInst(&cpu, h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(0x00FF0000, cpu.readReg(3));

    // Byte 3 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x01000000);
    loadInst(&cpu, h.encodeOpImmShift(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(0xFF000000, cpu.readReg(3));
}

// --- REV8 execute tests ---

test "step: ORC.B sets a byte when only its high nibble is non-zero" {
    const orc_b = h.encodeI(0b0010011, 0b101, 3, 1, (@as(u12, 0b0010100) << 5) | 7); // ORC.B x3, x1
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00800000);
    loadInst(&cpu, orc_b);
    _ = try cpu.step();
    try std.testing.expectEqual(0x00FF0000, cpu.readReg(3));
    cpu.pc = 0;
    cpu.writeReg(1, 0x0000F000);
    loadInst(&cpu, orc_b);
    _ = try cpu.step();
    try std.testing.expectEqual(0x0000FF00, cpu.readReg(3));
}
