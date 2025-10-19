const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// ============================================================
// CPU step: ALU ops + stack ops
// ============================================================

test "CPU step: C.SUB" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 20);
    cpu.writeReg(9, 7);
    // C.SUB x8, x9 = 0x8C05
    h.storeHalfAt(&cpu, 0, 0x8C05);
    h.storeHalfAt(&cpu, 2, 0x0001); // NOP

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 13), cpu.readReg(8)); // 20 - 7
}

test "CPU step: C.OR" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0xF0);
    cpu.writeReg(9, 0x0F);
    // C.OR x8, x9 = 0x8C45
    h.storeHalfAt(&cpu, 0, 0x8C45);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(8));
}

test "CPU step: C.AND" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0xFF);
    cpu.writeReg(9, 0x0F);
    // C.AND x8, x9 = 0x8C65
    h.storeHalfAt(&cpu, 0, 0x8C65);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0F), cpu.readReg(8));
}

test "CPU step: C.XOR" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0xFF00FF00);
    cpu.writeReg(9, 0x0F0F0F0F);
    // C.XOR x8, x9 = 0x8C25
    h.storeHalfAt(&cpu, 0, 0x8C25);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF00FF00F), cpu.readReg(8));
}

test "CPU step: C.SLLI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x01);
    // C.SLLI x1, 4 = 0x0092
    h.storeHalfAt(&cpu, 0, 0x0092);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x10), cpu.readReg(1));
}

test "CPU step: C.SRLI" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0x80);
    // C.SRLI x8, 4 = 0x8011
    h.storeHalfAt(&cpu, 0, 0x8011);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x08), cpu.readReg(8));
}

test "CPU step: C.SRAI" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0x80000000);
    // C.SRAI x8, 1 = 0x8405
    h.storeHalfAt(&cpu, 0, 0x8405);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    // Arithmetic right shift preserves sign bit: 0x80000000 >> 1 = 0xC0000000
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(8));
}

test "CPU step: C.ANDI" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 0xFF);
    // C.ANDI x8, 3 = 0x880D
    h.storeHalfAt(&cpu, 0, 0x880D);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(8));
}

test "CPU step: C.ADDI4SPN" {
    var cpu = Cpu.init();
    cpu.writeReg(2, 1000); // sp = 1000
    // C.ADDI4SPN x8, x2, 8 = 0x0020
    h.storeHalfAt(&cpu, 0, 0x0020);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1008), cpu.readReg(8)); // sp + 8
}

test "CPU step: C.ADDI16SP" {
    var cpu = Cpu.init();
    cpu.writeReg(2, 1000); // sp = 1000
    // C.ADDI16SP x2, 16 = 0x6141
    h.storeHalfAt(&cpu, 0, 0x6141);
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1016), cpu.readReg(2)); // sp + 16
}
