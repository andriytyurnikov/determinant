const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;

test "determinism: two VMs with same program produce identical state" {
    var cpu1 = Cpu.init();
    var cpu2 = Cpu.init();

    // Same program: compute (5 + 10) * 3 via shifts and adds, store result, ECALL
    // ADDI x1, x0, 5
    std.mem.writeInt(u32, cpu1.memory[0..][0..4], 0x00500093, .little);
    std.mem.writeInt(u32, cpu2.memory[0..][0..4], 0x00500093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu1.memory[4..][0..4], 0x00A00113, .little);
    std.mem.writeInt(u32, cpu2.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2 (x3 = 15)
    std.mem.writeInt(u32, cpu1.memory[8..][0..4], 0x002081B3, .little);
    std.mem.writeInt(u32, cpu2.memory[8..][0..4], 0x002081B3, .little);
    // SLLI x4, x3, 1 (x4 = 30)
    std.mem.writeInt(u32, cpu1.memory[12..][0..4], 0x00119213, .little);
    std.mem.writeInt(u32, cpu2.memory[12..][0..4], 0x00119213, .little);
    // ADD x5, x4, x3 (x5 = 45)
    std.mem.writeInt(u32, cpu1.memory[16..][0..4], 0x003202B3, .little);
    std.mem.writeInt(u32, cpu2.memory[16..][0..4], 0x003202B3, .little);
    // SW x5, 256(x0)
    std.mem.writeInt(u32, cpu1.memory[20..][0..4], 0x10502023, .little);
    std.mem.writeInt(u32, cpu2.memory[20..][0..4], 0x10502023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu1.memory[24..][0..4], 0x00000073, .little);
    std.mem.writeInt(u32, cpu2.memory[24..][0..4], 0x00000073, .little);

    const result1 = try cpu1.run(100);
    const result2 = try cpu2.run(100);

    // Identical results
    try std.testing.expectEqual(result1, result2);
    try std.testing.expectEqual(cpu1.pc, cpu2.pc);
    try std.testing.expectEqual(cpu1.cycle_count, cpu2.cycle_count);

    // Identical register state
    for (0..32) |i| {
        try std.testing.expectEqual(cpu1.readReg(@intCast(i)), cpu2.readReg(@intCast(i)));
    }

    // Identical memory at store target
    try std.testing.expectEqual(
        std.mem.readInt(u32, cpu1.memory[256..][0..4], .little),
        std.mem.readInt(u32, cpu2.memory[256..][0..4], .little),
    );

    // Verify expected values
    try std.testing.expectEqual(StepResult.Ecall, result1);
    try std.testing.expectEqual(@as(u32, 45), cpu1.readReg(5));
    try std.testing.expectEqual(@as(u32, 45), std.mem.readInt(u32, cpu1.memory[256..][0..4], .little));
}
