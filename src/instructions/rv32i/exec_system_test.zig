const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests: system instructions ===

test "step: ECALL" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00000073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: EBREAK" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00100073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.ebreak, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: FENCE is no-op" {
    var cpu = Cpu.init();
    // FENCE iorw, iorw = 0x0FF0000F
    loadInst(&cpu, 0x0FF0000F);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "step: FENCE.I is no-op" {
    var cpu = Cpu.init();
    // FENCE.I = 0x0000100F (opcode=0x0F, funct3=001)
    loadInst(&cpu, 0x0000100F);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}
