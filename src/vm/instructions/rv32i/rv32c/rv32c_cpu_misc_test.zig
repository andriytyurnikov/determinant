const std = @import("std");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

// === CPU step tests: compressed miscellaneous (MV, EBREAK) ===

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
