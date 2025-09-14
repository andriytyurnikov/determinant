const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = Cpu.mem_size;
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

test "x0 write-protection: ADD to x0 leaves it zero" {
    const h = @import("../instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    cpu.writeReg(2, 200);
    // ADD x0, x1, x2 — result should be discarded
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b000, 0b0000000, 0, 1, 2));
    _ = try cpu.step();
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
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x1234567F, .little);
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
    std.mem.writeInt(u32, cpu.memory[2..][0..4], 0x00000013, .little);
    cpu.pc = 2;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x00000013), raw);
}

test "fetch compressed instruction returns zero-extended u16" {
    var cpu = Cpu.init();
    // C.NOP = 0x0001 (low 2 bits = 01, not 11 → compressed)
    std.mem.writeInt(u16, cpu.memory[0..][0..2], 0x0001, .little);
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
