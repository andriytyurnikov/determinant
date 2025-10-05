const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = Cpu.mem_size;
const StepResult = cpu_mod.StepResult;

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

// --- Boundary memory tests ---

test "fetch: compressed instruction at MEMORY_SIZE - 2" {
    var cpu = Cpu.init();
    // Place a compressed NOP (C.NOP = 0x0001) at the very last 2 bytes
    const addr: usize = MEMORY_SIZE - 2;
    std.mem.writeInt(u16, cpu.memory[addr..][0..2], 0x0001, .little);
    cpu.pc = MEMORY_SIZE - 2;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x0001), raw);
}

test "fetch: 32-bit instruction at MEMORY_SIZE - 2 fails" {
    var cpu = Cpu.init();
    // Place bytes that look like a 32-bit instruction (bits[1:0] = 0b11) at MEMORY_SIZE-2
    // Only 2 bytes available, so 32-bit fetch must fail
    const addr: usize = MEMORY_SIZE - 2;
    std.mem.writeInt(u16, cpu.memory[addr..][0..2], 0x0013, .little); // ADDI low half, bits[1:0]=11
    cpu.pc = MEMORY_SIZE - 2;
    try std.testing.expectError(error.PCOutOfBounds, cpu.fetch());
}

test "fetch: 32-bit instruction at MEMORY_SIZE - 4 succeeds" {
    var cpu = Cpu.init();
    // NOP at the last 4-byte-aligned position
    const addr: usize = MEMORY_SIZE - 4;
    std.mem.writeInt(u32, cpu.memory[addr..][0..4], 0x00000013, .little);
    cpu.pc = MEMORY_SIZE - 4;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x00000013), raw);
}

test "loadProgram: exact fit (offset + len = MEMORY_SIZE)" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0x13, 0x00, 0x00, 0x00 };
    try cpu.loadProgram(&program, MEMORY_SIZE - 4);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[MEMORY_SIZE - 4]);
}

test "loadProgram: single byte at last address" {
    var cpu = Cpu.init();
    const program = [_]u8{0xFF};
    try cpu.loadProgram(&program, MEMORY_SIZE - 1);
    try std.testing.expectEqual(@as(u8, 0xFF), cpu.memory[MEMORY_SIZE - 1]);
}

test "loadProgram: one byte past end fails" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0xFF, 0xFF };
    try std.testing.expectError(error.AddressOutOfBounds, cpu.loadProgram(&program, MEMORY_SIZE - 1));
}

test "loadProgram: full memory" {
    var cpu = Cpu.init();
    var program: [MEMORY_SIZE]u8 = undefined;
    @memset(&program, 0x13);
    try cpu.loadProgram(&program, 0);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[0]);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[MEMORY_SIZE - 1]);
}

test "readByte: last valid address" {
    var cpu = Cpu.init();
    cpu.memory[MEMORY_SIZE - 1] = 0xAB;
    try std.testing.expectEqual(@as(u8, 0xAB), try cpu.readByte(MEMORY_SIZE - 1));
}

test "readWord: last valid aligned address" {
    var cpu = Cpu.init();
    const addr: u32 = MEMORY_SIZE - 4;
    try cpu.writeWord(addr, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try cpu.readWord(addr));
}

test "readHalfword: last valid aligned address" {
    var cpu = Cpu.init();
    const addr: u32 = MEMORY_SIZE - 2;
    try cpu.writeHalfword(addr, 0xBEEF);
    try std.testing.expectEqual(@as(u16, 0xBEEF), try cpu.readHalfword(addr));
}

test "readWord: one past last valid address fails" {
    var cpu = Cpu.init();
    // MEMORY_SIZE - 3 is not 4-byte aligned, so MisalignedAccess
    try std.testing.expectError(error.MisalignedAccess, cpu.readWord(MEMORY_SIZE - 3));
    // MEMORY_SIZE is out of bounds
    try std.testing.expectError(error.AddressOutOfBounds, cpu.readWord(MEMORY_SIZE));
}

test "writeByte out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.writeByte(MEMORY_SIZE, 0));
}

test "readHalfword out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.readHalfword(MEMORY_SIZE));
}

test "writeHalfword out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.writeHalfword(MEMORY_SIZE, 0));
}
