const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = cpu_mod.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

test "init zeroes everything" {
    const cpu = Cpu.init();
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
    for (cpu.regs) |r| {
        try std.testing.expectEqual(@as(u32, 0), r);
    }
}

test "x0 hardwired to zero" {
    var cpu = Cpu.init();
    cpu.writeReg(0, 12345);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "register read/write" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(1));
    cpu.writeReg(31, 42);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(31));
}

test "fetch from memory" {
    var cpu = Cpu.init();
    // Write a little-endian u32 at address 0 (bits[1:0]=11 so it's treated as 32-bit)
    std.mem.writeInt(u32, cpu.memory[0..4], 0x1234567F, .little);
    const inst = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x1234567F), inst);
}

test "fetch misaligned PC" {
    var cpu = Cpu.init();
    cpu.pc = 1; // odd address is misaligned (2-byte alignment required)
    try std.testing.expectError(error.MisalignedPC, cpu.fetch());
}

test "fetch at 2-byte-aligned address" {
    var cpu = Cpu.init();
    // Write a 32-bit instruction at address 2 (2-byte aligned but not 4-byte)
    std.mem.writeInt(u32, cpu.memory[2..6], 0x00000013, .little);
    cpu.pc = 2;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x00000013), raw);
}

test "fetch compressed instruction returns zero-extended u16" {
    var cpu = Cpu.init();
    // C.NOP = 0x0001 (low 2 bits = 01, not 11 → compressed)
    std.mem.writeInt(u16, cpu.memory[0..2], 0x0001, .little);
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x0001), raw);
}

test "fetch PC out of bounds" {
    var cpu = Cpu.init();
    cpu.pc = MEMORY_SIZE;
    try std.testing.expectError(error.PCOutOfBounds, cpu.fetch());
}

test "loadProgram" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0x13, 0x00, 0x50, 0x00 }; // ADDI x0, x0, 5
    try cpu.loadProgram(&program, 0);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[0]);
    try std.testing.expectEqual(@as(u8, 0x00), cpu.memory[1]);
    try std.testing.expectEqual(@as(u8, 0x50), cpu.memory[2]);
    try std.testing.expectEqual(@as(u8, 0x00), cpu.memory[3]);
}

test "loadProgram at offset" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0xAA, 0xBB };
    try cpu.loadProgram(&program, 100);
    try std.testing.expectEqual(@as(u8, 0xAA), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0xBB), cpu.memory[101]);
}

test "loadProgram out of bounds" {
    var cpu = Cpu.init();
    const program = [_]u8{0xFF} ** 8;
    try std.testing.expectError(error.AddressOutOfBounds, cpu.loadProgram(&program, MEMORY_SIZE - 4));
}

// --- Memory helper tests ---

test "readByte / writeByte" {
    var cpu = Cpu.init();
    try cpu.writeByte(100, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), try cpu.readByte(100));
}

test "readHalfword / writeHalfword little-endian" {
    var cpu = Cpu.init();
    try cpu.writeHalfword(100, 0x1234);
    try std.testing.expectEqual(@as(u16, 0x1234), try cpu.readHalfword(100));
    // Verify little-endian byte order
    try std.testing.expectEqual(@as(u8, 0x34), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0x12), cpu.memory[101]);
}

test "readWord / writeWord little-endian" {
    var cpu = Cpu.init();
    try cpu.writeWord(100, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try cpu.readWord(100));
    try std.testing.expectEqual(@as(u8, 0xEF), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0xBE), cpu.memory[101]);
    try std.testing.expectEqual(@as(u8, 0xAD), cpu.memory[102]);
    try std.testing.expectEqual(@as(u8, 0xDE), cpu.memory[103]);
}

test "readHalfword misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.readHalfword(3));
}

test "writeHalfword misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.writeHalfword(5, 0));
}

test "readWord misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.readWord(2));
}

test "writeWord misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.writeWord(1, 0));
}

test "readByte out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.readByte(MEMORY_SIZE));
}

test "writeWord out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.writeWord(MEMORY_SIZE, 0));
}

// --- Pipeline infrastructure tests ---

test "step: cycle count increments" {
    var cpu = Cpu.init();
    // Two NOPs (ADDI x0, x0, 0 = 0x00000013)
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: multi-instruction ADDI + ADD" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 5 = 0x00500093
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00500093, .little);
    // ADDI x2, x0, 10 = 0x00A00113
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00A00113, .little);
    // ADD x3, x1, x2 = 0x002081B3
    std.mem.writeInt(u32, cpu.memory[8..12], 0x002081B3, .little);

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
    std.mem.writeInt(u32, cpu.memory[0..4], 0x06400093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00A00113, .little);
    // ADD x3, x1, x2
    std.mem.writeInt(u32, cpu.memory[8..12], 0x002081B3, .little);
    // SW x3, 0(x1) — store at address 100 (aligned)
    std.mem.writeInt(u32, cpu.memory[12..16], 0x0030A023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[16..20], 0x00000073, .little);

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
    try std.testing.expectEqual(@as(u32, 110), std.mem.readInt(u32, cpu.memory[100..104], .little));
}

// --- run() tests ---

test "run: stops on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run: stops on EBREAK" {
    var cpu = Cpu.init();
    // EBREAK
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00100073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.Ebreak, result);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "run: respects max_cycles" {
    var cpu = Cpu.init();
    // 4 NOPs then ECALL
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[8..12], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[12..16], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[16..20], 0x00000073, .little);

    // Limit to 2 cycles — should stop before ECALL
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "run: max_cycles exactly at ECALL" {
    var cpu = Cpu.init();
    // NOP then ECALL
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000073, .little);

    // max_cycles=2: should execute both instructions
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}
