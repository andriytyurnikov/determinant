const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const StepResult = cpu_mod.StepResult;

/// Load the test program into a CPU's memory.
fn loadTestProgram(memory: []u8) void {
    // compute (5 + 10) * 3 via shifts and adds, store result, ECALL
    const program = [_]struct { u32, u32 }{
        .{ 0, 0x00500093 }, // ADDI x1, x0, 5
        .{ 4, 0x00A00113 }, // ADDI x2, x0, 10
        .{ 8, 0x002081B3 }, // ADD x3, x1, x2 (x3 = 15)
        .{ 12, 0x00119213 }, // SLLI x4, x3, 1 (x4 = 30)
        .{ 16, 0x003202B3 }, // ADD x5, x4, x3 (x5 = 45)
        .{ 20, 0x10502023 }, // SW x5, 256(x0)
        .{ 24, 0x00000073 }, // ECALL
    };
    for (program) |entry| {
        std.mem.writeInt(u32, memory[entry[0]..][0..4], entry[1], .little);
    }
}

test "determinism: two VMs with same program produce identical state" {
    var cpu1 = Cpu.init();
    var cpu2 = Cpu.init();

    loadTestProgram(&cpu1.memory);
    loadTestProgram(&cpu2.memory);

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
    try std.testing.expectEqual(StepResult.ecall, result1);
    try std.testing.expectEqual(@as(u32, 45), cpu1.readReg(5));
    try std.testing.expectEqual(@as(u32, 45), std.mem.readInt(u32, cpu1.memory[256..][0..4], .little));
}
