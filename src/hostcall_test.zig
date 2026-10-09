const std = @import("std");
const hostcall = @import("hostcall.zig");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("instructions/test_helpers.zig");

const alloc = std.testing.allocator;

const Harness = struct {
    out: std.Io.Writer.Allocating,
    err: std.Io.Writer.Allocating,
    env: hostcall.Env,

    fn init(self: *Harness, input: []const u8) void {
        self.out = .init(alloc);
        self.err = .init(alloc);
        self.env = .{ .input = input, .stdout = &self.out.writer, .stderr = &self.err.writer };
    }

    fn deinit(self: *Harness) void {
        self.out.deinit();
        self.err.deinit();
    }
};

/// Set up the registers of a call and handle it.
fn call(cpu: *Cpu, hs: *Harness, number: u32, a0: u32, a1: u32, a2: u32) !hostcall.Outcome {
    cpu.writeReg(17, number);
    cpu.writeReg(10, a0);
    cpu.writeReg(11, a1);
    cpu.writeReg(12, a2);
    return hostcall.handle(cpu, &hs.env);
}

test "write: fd 1 and 2 go to the host's stdout and stderr; a0 = length" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("");
    defer hs.deinit();
    try cpu.loadProgram("hello world", 0x100);
    try std.testing.expectEqual(hostcall.Outcome.resumed, try call(&cpu, &hs, 64, 1, 0x100, 5));
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(10));
    try std.testing.expectEqual(hostcall.Outcome.resumed, try call(&cpu, &hs, 64, 2, 0x106, 5));
    try std.testing.expectEqualStrings("hello", hs.out.written());
    try std.testing.expectEqualStrings("world", hs.err.written());
}

test "write: a bad fd or an out-of-bounds buffer writes nothing" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("");
    defer hs.deinit();
    _ = try call(&cpu, &hs, 64, 3, 0, 4);
    try std.testing.expectEqual(hostcall.ebadf, cpu.readReg(10));
    _ = try call(&cpu, &hs, 64, 1, Cpu.mem_size - 2, 4);
    try std.testing.expectEqual(hostcall.efault, cpu.readReg(10));
    _ = try call(&cpu, &hs, 64, 1, 0xFFFF_FFFF, 2); // the range would wrap
    try std.testing.expectEqual(hostcall.efault, cpu.readReg(10));
    try std.testing.expectEqualStrings("", hs.out.written());
}

test "read: copies the input in order, then 0 at its end" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("abcdef");
    defer hs.deinit();
    _ = try call(&cpu, &hs, 63, 0, 0x200, 4);
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(10));
    _ = try call(&cpu, &hs, 63, 0, 0x204, 4);
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(10)); // only "ef" left
    _ = try call(&cpu, &hs, 63, 0, 0x206, 4);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(10)); // end of input
    try std.testing.expectEqualStrings("abcdef", cpu.memory[0x200..0x206]);
    try std.testing.expectEqual(@as(u8, 0), cpu.memory[0x206]);
}

test "read: a bad fd or an out-of-bounds buffer reads nothing" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("abc");
    defer hs.deinit();
    _ = try call(&cpu, &hs, 63, 1, 0x200, 3);
    try std.testing.expectEqual(hostcall.ebadf, cpu.readReg(10));
    _ = try call(&cpu, &hs, 63, 0, Cpu.mem_size - 1, 3);
    try std.testing.expectEqual(hostcall.efault, cpu.readReg(10));
    try std.testing.expectEqual(@as(usize, 0), hs.env.input_pos); // nothing consumed
}

test "read: overwriting the reserved word drops the LR reservation" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("abcd");
    defer hs.deinit();
    cpu.reservation = 0x200;
    _ = try call(&cpu, &hs, 63, 0, 0x202, 2);
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "exit and exit_group report the status; unknown calls change nothing" {
    var cpu = Cpu.init();
    var hs: Harness = undefined;
    hs.init("");
    defer hs.deinit();
    try std.testing.expectEqual(hostcall.Outcome{ .exit = 42 }, try call(&cpu, &hs, 93, 42, 0, 0));
    try std.testing.expectEqual(hostcall.Outcome{ .exit = 0xFFFF_FFFF }, try call(&cpu, &hs, 94, 0xFFFF_FFFF, 0, 0));
    cpu.writeReg(17, 0); // not a host call
    cpu.writeReg(10, 1);
    const before = cpu.stateDigest();
    try std.testing.expectEqual(hostcall.Outcome{ .unknown = 0 }, try hostcall.handle(&cpu, &hs.env));
    try std.testing.expectEqualSlices(u8, &before, &cpu.stateDigest());
}

test "a guest program echoes its input and exits with a status" {
    // read(0, 0x200, 64); write(1, 0x200, n); exit(7) — assembled with GNU as
    const program = [_]u8{
        0x93, 0x08, 0xf0, 0x03, 0x13, 0x05, 0x00, 0x00, 0x93, 0x05, 0x00, 0x20, 0x13, 0x06, 0x00, 0x04,
        0x73, 0x00, 0x00, 0x00, 0x13, 0x06, 0x05, 0x00, 0x93, 0x08, 0x00, 0x04, 0x13, 0x05, 0x10, 0x00,
        0x93, 0x05, 0x00, 0x20, 0x73, 0x00, 0x00, 0x00, 0x93, 0x08, 0xd0, 0x05, 0x13, 0x05, 0x70, 0x00,
        0x73, 0x00, 0x00, 0x00,
    };
    var cpu = Cpu.init();
    try cpu.loadProgram(&program, 0);
    var hs: Harness = undefined;
    hs.init("deterministic\n");
    defer hs.deinit();
    const status = while (true) {
        try std.testing.expectEqual(cpu_mod.StepResult.ecall, try cpu.run(1000));
        switch (try hostcall.handle(&cpu, &hs.env)) {
            .resumed => {},
            .exit => |s| break s,
            .unknown => return error.TestUnexpectedResult,
        }
    };
    try std.testing.expectEqual(@as(u32, 7), status);
    try std.testing.expectEqualStrings("deterministic\n", hs.out.written());
    try std.testing.expectEqual(@as(u64, 13), cpu.cycle_count); // calls cost no extra cycles
}
