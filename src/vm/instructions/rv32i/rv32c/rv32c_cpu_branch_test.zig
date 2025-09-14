const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// === CPU step tests: compressed branches ===

test "CPU step: C.BEQZ taken" {
    var cpu = Cpu.init();
    // x8 = 0 by default
    h.storeHalfAt(&cpu, 0, 0xC011);
    // ECALL at offset 4
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
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
