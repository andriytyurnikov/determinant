const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// ============================================================
// CPU step tests for compressed instructions:
// jumps, branches, load-store, MV, EBREAK
// ============================================================

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

test "CPU step: C.LW and C.SW" {
    var cpu = Cpu.init();
    // ADDI x2, x0, 256 = 0x10000113
    h.storeWordAt(&cpu, 0, 0x10000113);
    // ADDI x8, x0, 42 = 0x02A00413
    h.storeWordAt(&cpu, 4, 0x02A00413);
    // C.SWSP x8, 0(x2) = 0xC022
    h.storeHalfAt(&cpu, 8, 0xC022);
    // C.LWSP x9, 0(x2) = 0x4482
    h.storeHalfAt(&cpu, 10, 0x4482);
    // ECALL
    h.storeWordAt(&cpu, 12, 0x00000073);

    _ = try cpu.step(); // ADDI x2, x0, 256
    _ = try cpu.step(); // ADDI x8, x0, 42
    _ = try cpu.step(); // C.SWSP x8, 0(x2) → mem[256]=42
    _ = try cpu.step(); // C.LWSP x9, 0(x2) → x9=42

    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(9));
    try std.testing.expectEqual(@as(u32, 42), try cpu.readWord(256));
}

test "CPU step: C.BEQZ taken" {
    var cpu = Cpu.init();
    // x8 = 0 by default
    h.storeHalfAt(&cpu, 0, 0xC011);
    // ECALL at offset 4
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
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

test "CPU step: C.BEQZ not-taken (x8 != 0)" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 1); // nonzero → branch not taken
    // C.BEQZ x8, 4
    h.storeHalfAt(&cpu, 0, 0xC011);
    // NOP at offset 2
    h.storeHalfAt(&cpu, 2, 0x0001);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.pc); // PC advanced by 2 (not taken)
}

test "CPU step: C.BNEZ taken (x8 != 0)" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 1); // nonzero → branch taken
    // C.BNEZ x8, 4 = 0xE011
    h.storeHalfAt(&cpu, 0, 0xE011);
    // ECALL at target (offset 4)
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc); // branch taken
}

test "CPU step: C.BNEZ not-taken (x8 == 0)" {
    var cpu = Cpu.init();
    // x8 = 0 by default → branch not taken
    h.storeHalfAt(&cpu, 0, 0xE011);
    h.storeHalfAt(&cpu, 2, 0x0001); // NOP at offset 2

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.pc); // not taken, PC += 2
}

test "CPU step: C.MV" {
    var cpu = Cpu.init();
    cpu.writeReg(2, 42);
    // C.MV x1, x2 = 0x808A
    h.storeHalfAt(&cpu, 0, 0x808A);
    h.storeHalfAt(&cpu, 2, 0x0001); // NOP

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
}

test "CPU step: C.EBREAK" {
    var cpu = Cpu.init();
    // C.EBREAK = 0x9002
    h.storeHalfAt(&cpu, 0, 0x9002);

    const result = try cpu.step();
    try std.testing.expectEqual(cpu_mod.StepResult.ebreak, result);
}

test "CPU step: C.LW and C.SW with compact registers" {
    var cpu = Cpu.init();
    cpu.writeReg(8, 256); // base address in compact register
    cpu.writeReg(9, 0xBEEF); // value to store

    // C.SW x9, 0(x8) = 0xC004
    h.storeHalfAt(&cpu, 0, 0xC004);
    // C.LW x10, 0(x8) = 0x4008
    h.storeHalfAt(&cpu, 2, 0x4008);
    h.storeWordAt(&cpu, 4, 0x00000073); // ECALL

    _ = try cpu.step(); // C.SW
    _ = try cpu.step(); // C.LW
    try std.testing.expectEqual(@as(u32, 0xBEEF), cpu.readReg(10));
    try std.testing.expectEqual(@as(u32, 0xBEEF), try cpu.readWord(256));
}
