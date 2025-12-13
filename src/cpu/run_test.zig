const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;

// --- run() tests ---

test "run: stops on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run: stops on EBREAK" {
    var cpu = Cpu.init();
    // EBREAK
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00100073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.ebreak, result);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "run: respects max_cycles" {
    var cpu = Cpu.init();
    // 4 NOPs then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[12..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[16..][0..4], 0x00000073, .little);

    // Limit to 2 cycles — should stop before ECALL
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "run: max_cycles exactly at ECALL" {
    var cpu = Cpu.init();
    // NOP then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    // max_cycles=2: should execute both instructions
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run(null) terminates on ECALL (unlimited)" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(null);
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run(0) returns immediately without executing" {
    var cpu = Cpu.init();
    // Place ECALL at addr 0 — if it executes, result would be ecall
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u64, 0), cpu.cycle_count); // unchanged
    try std.testing.expectEqual(@as(u32, 0), cpu.pc); // unchanged
}

// --- run() error propagation tests ---

test "run: propagates IllegalInstruction from decode" {
    var cpu = Cpu.init();
    // Memory is all zeros from init().
    // 0x0000 is compressed C_ADDI4SPN with nzuimm=0 → IllegalInstruction in expand()
    try std.testing.expectError(error.IllegalInstruction, cpu.run(null));
}

test "run: propagates PCOutOfBounds when execution falls off memory" {
    var cpu = Cpu.init();
    // Place a NOP at the very end of memory
    const last_word = Cpu.mem_size - 4;
    cpu.pc = last_word;
    std.mem.writeInt(u32, cpu.memory[last_word..][0..4], 0x00000013, .little);
    // After NOP, PC = mem_size → next fetch returns PCOutOfBounds
    try std.testing.expectError(error.PCOutOfBounds, cpu.run(null));
}

test "run: propagates MisalignedPC" {
    var cpu = Cpu.init();
    // Set PC to odd address directly (unreachable via normal execution since JALR clears bit[0])
    cpu.pc = 1;
    try std.testing.expectError(error.MisalignedPC, cpu.run(null));
}

test "run: propagates AddressOutOfBounds from load" {
    var cpu = Cpu.init();
    // LUI x1, 0xFFFFF → x1 = 0xFFFFF000
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0xFFFFF0B7, .little);
    // LW x2, 0(x1) → load from 0xFFFFF000, far beyond memory
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x0000A103, .little);
    try std.testing.expectError(error.AddressOutOfBounds, cpu.run(null));
}

test "run: propagates MisalignedAccess from load" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 1 → x1 = 1
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00100093, .little);
    // LW x2, 0(x1) → word load from addr 1, not 4-aligned
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x0000A103, .little);
    try std.testing.expectError(error.MisalignedAccess, cpu.run(null));
}

test "run: propagates IllegalInstruction from CSR execution" {
    var cpu = Cpu.init();
    // CSRRS x1, 0x123, x0 → read unsupported CSR 0x123
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x123020F3, .little);
    try std.testing.expectError(error.IllegalInstruction, cpu.run(null));
}

// --- run() cycle_count >= max_cycles edge cases ---

test "run: returns immediately when cycle_count equals max_cycles" {
    var cpu = Cpu.init();
    // Place ECALL at addr 0 — if it executes, result would be ecall
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000073, .little);
    cpu.cycle_count = 10;

    const result = try cpu.run(10);
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u64, 10), cpu.cycle_count); // unchanged
    try std.testing.expectEqual(@as(u32, 0), cpu.pc); // unchanged
}

test "run: returns immediately when cycle_count exceeds max_cycles" {
    var cpu = Cpu.init();
    // Place ECALL at addr 0 — if it executes, result would be ecall
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000073, .little);
    cpu.cycle_count = 15;

    const result = try cpu.run(10);
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u64, 15), cpu.cycle_count); // unchanged
    try std.testing.expectEqual(@as(u32, 0), cpu.pc); // unchanged
}

// --- run() with non-zero initial cycle_count ---

test "run: partial execution with non-zero initial cycle_count" {
    var cpu = Cpu.init();
    // 3 NOPs then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[12..][0..4], 0x00000073, .little);
    cpu.cycle_count = 5;

    // max_cycles=7 allows 2 steps (cycle 5→6, 6→7), then stops before 3rd NOP
    const result = try cpu.run(7);
    try std.testing.expectEqual(StepResult.@"continue", result);
    try std.testing.expectEqual(@as(u64, 7), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // executed 2 NOPs
}

test "run: unlimited with non-zero initial cycle_count" {
    var cpu = Cpu.init();
    // NOP then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);
    cpu.cycle_count = 100;

    const result = try cpu.run(null);
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u64, 102), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}
