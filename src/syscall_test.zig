const std = @import("std");
const cpu = @import("cpu.zig");
const syscall = @import("syscall.zig");

fn testWriter() struct { buf: [4096]u8, fbs: std.io.FixedBufferStream([]u8) } {
    var state: struct { buf: [4096]u8, fbs: std.io.FixedBufferStream([]u8) } = undefined;
    state.buf = [_]u8{0} ** 4096;
    state.fbs = std.io.fixedBufferStream(&state.buf);
    return state;
}

// Helper: encode ADDI rd, rs1, imm as u32 (I-type, opcode 0x13)
fn encodeAddi(rd: u5, rs1: u5, imm: i12) u32 {
    const imm_u: u12 = @bitCast(imm);
    return @as(u32, imm_u) << 20 | @as(u32, rs1) << 15 | @as(u32, 0b000) << 12 | @as(u32, rd) << 7 | 0x13;
}

// Helper: encode ECALL as u32
fn encodeEcall() u32 {
    return 0x00000073;
}

// Helper: load a program (as u32 words) into VM memory at offset 0
fn loadProgram(vm: *cpu.Cpu, words: []const u32) !void {
    const bytes = std.mem.sliceAsBytes(words);
    try vm.loadProgram(bytes, 0);
}

test "write to fd=1 outputs bytes and returns count" {
    var vm = cpu.Cpu.init();

    // Place "Hi" at address 0x1000
    vm.memory[0x1000] = 'H';
    vm.memory[0x1001] = 'i';

    // Set up syscall: write(fd=1, buf=0x1000, len=2)
    // a7 (x17) = 64 (write), a0 (x10) = 1, a1 (x11) = 0x1000, a2 (x12) = 2
    vm.writeReg(17, 64); // a7 = write
    vm.writeReg(10, 1); // a0 = fd 1
    vm.writeReg(11, 0x1000); // a1 = buf ptr
    vm.writeReg(12, 2); // a2 = len

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const result = try syscall.handleSyscall(&vm, writer);

    try std.testing.expectEqual(syscall.SyscallResult.continue_, result);
    try std.testing.expectEqual(@as(u32, 2), vm.readReg(10)); // a0 = bytes written
    try std.testing.expectEqualStrings("Hi", fbs.getWritten());
}

test "write to bad fd returns -EBADF" {
    var vm = cpu.Cpu.init();

    // a7 = 64 (write), a0 = 2 (stderr, not supported), a1 = 0, a2 = 0
    vm.writeReg(17, 64);
    vm.writeReg(10, 2); // bad fd
    vm.writeReg(11, 0);
    vm.writeReg(12, 0);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const result = try syscall.handleSyscall(&vm, writer);

    try std.testing.expectEqual(syscall.SyscallResult.continue_, result);
    // -9 as u32 two's complement
    const expected: u32 = @bitCast(@as(i32, -9));
    try std.testing.expectEqual(expected, vm.readReg(10));
}

test "write with OOB buffer returns -EFAULT" {
    var vm = cpu.Cpu.init();

    // a7 = 64 (write), a0 = 1, a1 = MEMORY_SIZE - 1, a2 = 2 (would overflow)
    vm.writeReg(17, 64);
    vm.writeReg(10, 1);
    vm.writeReg(11, cpu.MEMORY_SIZE - 1);
    vm.writeReg(12, 2);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const result = try syscall.handleSyscall(&vm, writer);

    try std.testing.expectEqual(syscall.SyscallResult.continue_, result);
    const expected: u32 = @bitCast(@as(i32, -14));
    try std.testing.expectEqual(expected, vm.readReg(10));
}

test "exit returns exit code" {
    var vm = cpu.Cpu.init();

    // a7 = 93 (exit), a0 = 42
    vm.writeReg(17, 93);
    vm.writeReg(10, 42);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const result = try syscall.handleSyscall(&vm, writer);

    try std.testing.expectEqual(syscall.SyscallResult{ .exit = 42 }, result);
}

test "unknown syscall returns -ENOSYS" {
    var vm = cpu.Cpu.init();

    // a7 = 999 (unknown)
    vm.writeReg(17, 999);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const result = try syscall.handleSyscall(&vm, writer);

    try std.testing.expectEqual(syscall.SyscallResult.continue_, result);
    const expected: u32 = @bitCast(@as(i32, -38));
    try std.testing.expectEqual(expected, vm.readReg(10));
}

test "runWithSyscalls: write then exit" {
    var vm = cpu.Cpu.init();

    // Place "OK" at address 0x800
    vm.memory[0x800] = 'O';
    vm.memory[0x801] = 'K';

    // Program:
    //   ADDI x17, x0, 64    — a7 = write
    //   ADDI x10, x0, 1     — a0 = fd 1
    //   ADDI x11, x0, 0x800 is too large for 12-bit imm, use LUI+ADDI approach
    // Actually 0x800 = 2048 which fits in 12-bit signed (-2048..2047) but just barely doesn't.
    // Use a two-step: LUI x11, 1 (sets x11 = 0x1000) then ADDI x11, x11, -2048
    // Wait, 0x800 = 2048. imm12 range is -2048 to 2047. So 2048 doesn't fit.
    // Simpler: use address 0x400 = 1024. That fits in 12-bit signed.

    // Move data to 0x400
    vm.memory[0x400] = 'O';
    vm.memory[0x401] = 'K';

    // Program at address 0x000:
    //   ADDI x17, x0, 64       — a7 = 64 (write syscall)
    //   ADDI x10, x0, 1        — a0 = 1 (stdout)
    //   ADDI x11, x0, 1024     — a1 = 0x400 (buf ptr)  -- 1024 fits in i12? No! max is 2047 so yes.
    //   ADDI x12, x0, 2        — a2 = 2 (len)
    //   ECALL                   — write(1, 0x400, 2)
    //   ADDI x17, x0, 93       — a7 = 93 (exit syscall)
    //   ADDI x10, x0, 7        — a0 = 7 (exit code)
    //   ECALL                   — exit(7)

    const program = [_]u32{
        encodeAddi(17, 0, 64), // ADDI x17, x0, 64
        encodeAddi(10, 0, 1), // ADDI x10, x0, 1
        encodeAddi(11, 0, 1024), // ADDI x11, x0, 1024
        encodeAddi(12, 0, 2), // ADDI x12, x0, 2
        encodeEcall(), // ECALL
        encodeAddi(17, 0, 93), // ADDI x17, x0, 93
        encodeAddi(10, 0, 7), // ADDI x10, x0, 7
        encodeEcall(), // ECALL
    };

    // Load program at 0x0 — won't overlap 0x400
    try loadProgram(&vm, &program);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const exit_code = try syscall.runWithSyscalls(&vm, 0, writer);

    try std.testing.expectEqual(@as(?u32, 7), exit_code);
    try std.testing.expectEqualStrings("OK", fbs.getWritten());
}
