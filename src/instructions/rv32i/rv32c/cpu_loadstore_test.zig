const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// === CPU step tests: compressed load/store ===

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
