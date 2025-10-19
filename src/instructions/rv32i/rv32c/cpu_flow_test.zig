const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// === CPU step tests: compressed flow control (LI, ADDI, jumps, mixed sequences) ===

test "CPU step: C.LUI loads upper immediate" {
    var cpu = Cpu.init();
    // C.LUI x1, 1 = 0x6085
    h.storeHalfAt(&cpu, 0, 0x6085);
    h.storeHalfAt(&cpu, 2, 0x0001); // NOP

    _ = try cpu.step();
    // nzimm=1 placed in bits[16:12], result = 1 << 12 = 0x1000
    try std.testing.expectEqual(@as(u32, 0x1000), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
}

test "CPU step: C.LI sets register, PC advances by 2" {
    var cpu = Cpu.init();
    // C.LI x1, 5 = 0x4095
    h.storeHalfAt(&cpu, 0, 0x4095);
    // NOP at offset 2 to avoid illegal instruction
    h.storeWordAt(&cpu, 2, 0x00000013);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
}

test "CPU step: C.ADDI modifies register" {
    var cpu = Cpu.init();
    // C.LI x1, 10 = 0x40A9
    h.storeHalfAt(&cpu, 0, 0x40A9);
    // C.ADDI x1, 3 = 0x008D
    h.storeHalfAt(&cpu, 2, 0x008D);
    // ECALL at offset 4
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 13), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "CPU step: C.JAL links PC+2" {
    var cpu = Cpu.init();
    // C.JAL offset=4
    h.storeHalfAt(&cpu, 0, 0x2011);
    // ECALL at target (offset 4)
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    // JAL links ra with PC+2 (compressed instruction)
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(1)); // ra = old_pc + 2
    try std.testing.expectEqual(@as(u32, 4), cpu.pc); // jumped to pc+4
}

test "CPU step: C.JALR links PC+2" {
    var cpu = Cpu.init();
    // C.LI x1, 8 = 0x40A1
    h.storeHalfAt(&cpu, 0, 0x40A1);
    // C.JALR x1 at offset 2 = 0x9082
    h.storeHalfAt(&cpu, 2, 0x9082);
    // ECALL at offset 8 (the jump target)
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step(); // C.LI x1, 8 → pc=2
    _ = try cpu.step(); // C.JALR x1 → pc=8, ra=4

    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(1)); // ra = old_pc(2) + 2
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "CPU step: C.JR jumps without linking" {
    var cpu = Cpu.init();
    // C.LI x1, 8 = 0x40A1
    h.storeHalfAt(&cpu, 0, 0x40A1);
    // C.JR x1 at offset 2 = 0x8082
    h.storeHalfAt(&cpu, 2, 0x8082);
    // ECALL at offset 8 (the jump target)
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step(); // C.LI x1, 8 → pc=2
    _ = try cpu.step(); // C.JR x1 → pc=8

    // No link: rd=x0, so x1 retains its value (unlike C.JALR which writes ra)
    try std.testing.expectEqual(@as(u32, 8), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "CPU step: C.J unconditional jump" {
    var cpu = Cpu.init();
    // C.J offset=8 = 0xA021
    h.storeHalfAt(&cpu, 0, 0xA021);
    // ECALL at target (offset 8)
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0)); // x0 unchanged (C.J links to x0)
}

test "CPU step: mixed 16-bit and 32-bit sequence" {
    var cpu = Cpu.init();
    // C.LI x1, 7 at offset 0 (2 bytes)
    h.storeHalfAt(&cpu, 0, 0x409D);
    // ADDI x2, x0, 3 = 0x00300113 at offset 2 (4 bytes)
    h.storeWordAt(&cpu, 2, 0x00300113);
    // C.ADD x1, x2 at offset 6 (2 bytes)
    h.storeHalfAt(&cpu, 6, 0x908A);
    // ECALL at offset 8
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step(); // C.LI x1, 7 → pc=2
    try std.testing.expectEqual(@as(u32, 7), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);

    _ = try cpu.step(); // ADDI x2, x0, 3 → pc=6
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 6), cpu.pc);

    _ = try cpu.step(); // C.ADD x1, x2 → x1=10, pc=8
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);

    const result = try cpu.step(); // ECALL → pc=12
    try std.testing.expectEqual(cpu_mod.StepResult.ecall, result);
}
