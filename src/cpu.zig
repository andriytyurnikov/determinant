const std = @import("std");

pub const MEMORY_SIZE: u32 = 1024 * 1024; // 1 MB

pub const CpuError = error{
    MisalignedPC,
    PCOutOfBounds,
    AddressOutOfBounds,
};

pub const Cpu = struct {
    pc: u32,
    regs: [32]u32,
    memory: [MEMORY_SIZE]u8,

    pub fn init() Cpu {
        return .{
            .pc = 0,
            .regs = [_]u32{0} ** 32,
            .memory = [_]u8{0} ** MEMORY_SIZE,
        };
    }

    /// Read register. x0 always returns 0.
    pub fn readReg(self: *const Cpu, reg: u5) u32 {
        if (reg == 0) return 0;
        return self.regs[reg];
    }

    /// Write register. Writes to x0 are silently discarded.
    pub fn writeReg(self: *Cpu, reg: u5, value: u32) void {
        if (reg == 0) return;
        self.regs[reg] = value;
    }

    /// Fetch the 32-bit instruction at PC (little-endian).
    pub fn fetch(self: *const Cpu) !u32 {
        if (self.pc % 4 != 0) return error.MisalignedPC;
        if (self.pc > MEMORY_SIZE - 4) return error.PCOutOfBounds;
        const addr: usize = self.pc;
        return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
    }

    /// Load program bytes into memory at the given offset.
    pub fn loadProgram(self: *Cpu, program: []const u8, offset: u32) !void {
        const off: usize = offset;
        if (off + program.len > MEMORY_SIZE) return error.AddressOutOfBounds;
        @memcpy(self.memory[off..][0..program.len], program);
    }
};

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
    // Write a little-endian u32 at address 0
    std.mem.writeInt(u32, cpu.memory[0..4], 0x12345678, .little);
    const inst = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x12345678), inst);
}

test "fetch misaligned PC" {
    var cpu = Cpu.init();
    cpu.pc = 2;
    try std.testing.expectError(error.MisalignedPC, cpu.fetch());
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
