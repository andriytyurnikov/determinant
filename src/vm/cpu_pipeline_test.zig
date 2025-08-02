const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = Cpu.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

// --- Pipeline infrastructure tests ---

test "step: cycle count increments" {
    var cpu = Cpu.init();
    // Two NOPs (ADDI x0, x0, 0 = 0x00000013)
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: multi-instruction ADDI + ADD" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 5 = 0x00500093
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00500093, .little);
    // ADDI x2, x0, 10 = 0x00A00113
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2 = 0x002081B3
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x002081B3, .little);

    _ = try cpu.step();
    _ = try cpu.step();
    _ = try cpu.step();

    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 15), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 12), cpu.pc);
    try std.testing.expectEqual(@as(u64, 3), cpu.cycle_count);
}

test "step: full demo program" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 100
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x06400093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x002081B3, .little);
    // SW x3, 0(x1) — store at address 100 (aligned)
    std.mem.writeInt(u32, cpu.memory[12..][0..4], 0x0030A023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[16..][0..4], 0x00000073, .little);

    var result: StepResult = .Continue;
    while (result == .Continue) {
        result = try cpu.step();
    }

    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 100), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 5), cpu.cycle_count);
    // Verify SW wrote to memory at address 100
    try std.testing.expectEqual(@as(u32, 110), std.mem.readInt(u32, cpu.memory[100..][0..4], .little));
}

// --- run() tests ---

test "run: stops on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run: stops on EBREAK" {
    var cpu = Cpu.init();
    // EBREAK
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00100073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.Ebreak, result);
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
    try std.testing.expectEqual(StepResult.Continue, result);
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
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

// --- Branch and error path tests ---

test "step: branch beyond memory causes PCOutOfBounds on next fetch" {
    const h = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // BEQ x0, x0, +4094 (large forward branch, always taken since x0==x0)
    // Target = 0 + 4094 = 4094, still in memory — but let's target beyond MEMORY_SIZE
    // Place instruction near end of memory, branch forward past it
    const pc: u32 = MEMORY_SIZE - 8;
    cpu.pc = pc;
    // BEQ x0, x0, +16 → target = (MEMORY_SIZE - 8) + 16 = MEMORY_SIZE + 8 → out of bounds
    h.loadInst(&cpu, h.encodeB(0b000, 0, 0, 16));
    _ = try cpu.step(); // branch is taken, sets next_pc beyond memory
    // PC is now MEMORY_SIZE + 8 (wrapped via +%)
    // Next fetch should fail
    try std.testing.expectError(error.PCOutOfBounds, cpu.step());
}

test "step: JAL beyond memory causes PCOutOfBounds on next fetch" {
    const h = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    const pc: u32 = MEMORY_SIZE - 4;
    cpu.pc = pc;
    // JAL x1, +8 → target = (MEMORY_SIZE - 4) + 8 = MEMORY_SIZE + 4 → out of bounds
    h.loadInst(&cpu, h.encodeJ(1, 8));
    _ = try cpu.step(); // JAL taken, link saved, next_pc beyond memory
    // Verify link register saved correctly
    try std.testing.expectEqual(pc + 4, cpu.readReg(1));
    // Next fetch should fail
    try std.testing.expectError(error.PCOutOfBounds, cpu.step());
}

test "step: cycle_count wrapping at u64 max" {
    var cpu = Cpu.init();
    cpu.cycle_count = std.math.maxInt(u64);
    // NOP
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 0), cpu.cycle_count);
}

test "step: backward branch (negative offset)" {
    const h2 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // NOP at address 0
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    // NOP at address 4
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    // BEQ x0, x0, -4 at address 8 → target = 4
    cpu.pc = 8;
    std.mem.writeInt(u32, cpu.memory[8..][0..4], h2.encodeB(0b000, 0, 0, -4), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

// --- Error path tests through step() ---

test "step: illegal instruction 0xFFFFFFFF" {
    var cpu = Cpu.init();
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0xFFFFFFFF, .little);
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: OOB load via LW causes AddressOutOfBounds" {
    const h3 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, MEMORY_SIZE); // address out of bounds
    // LW x2, 0(x1) = encodeI(0b0000011, 0b010, 2, 1, 0)
    h3.loadInst(&cpu, h3.encodeI(0b0000011, 0b010, 2, 1, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
}

test "step: misaligned LW causes MisalignedAccess" {
    const h4 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 3); // misaligned for word access
    // LW x2, 0(x1)
    h4.loadInst(&cpu, h4.encodeI(0b0000011, 0b010, 2, 1, 0));
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
}

// Determinism test in separate file
comptime {
    _ = @import("cpu_determinism_test.zig");
}
