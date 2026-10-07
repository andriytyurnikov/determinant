//! Program loading and host calls through the CLI: --input, exit statuses, ELF files,
//! --load-addr and the initial stack pointer.

const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

const io = std.testing.io;
const alloc = std.testing.allocator;
const ExitStatus = main_mod.ExitStatus;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

/// Files in a temporary directory, and the CLI's captured output.
const Fixture = struct {
    tmp: std.testing.TmpDir,
    out: Io.Writer.Allocating,
    err: Io.Writer.Allocating,
    paths: std.ArrayList([:0]u8) = .empty,

    fn init() Fixture {
        return .{ .tmp = std.testing.tmpDir(.{}), .out = .init(alloc), .err = .init(alloc) };
    }

    fn deinit(self: *Fixture) void {
        for (self.paths.items) |p| alloc.free(p);
        self.paths.deinit(alloc);
        self.out.deinit();
        self.err.deinit();
        self.tmp.cleanup();
    }

    /// Write a file and return its path, relative to the build root (the cwd).
    fn file(self: *Fixture, name: []const u8, bytes: []const u8) ![:0]const u8 {
        const f = try self.tmp.dir.createFile(io, name, .{});
        try f.writeStreamingAll(io, bytes);
        f.close(io);
        const p = try std.fmt.allocPrintSentinel(alloc, ".zig-cache/tmp/{s}/{s}", .{ &self.tmp.sub_path, name }, 0);
        try self.paths.append(alloc, p);
        return p;
    }

    fn run(self: *Fixture, args: []const [:0]const u8) u8 {
        return main_mod.run(io, &self.out.writer, &self.err.writer, args);
    }
};

/// read(0, 0x200, 64); write(1, 0x200, n); exit(7) — assembled with GNU as.
const echo_program = [_]u8{
    0x93, 0x08, 0xf0, 0x03, 0x13, 0x05, 0x00, 0x00, 0x93, 0x05, 0x00, 0x20, 0x13, 0x06, 0x00, 0x04,
    0x73, 0x00, 0x00, 0x00, 0x13, 0x06, 0x05, 0x00, 0x93, 0x08, 0x00, 0x04, 0x13, 0x05, 0x10, 0x00,
    0x93, 0x05, 0x00, 0x20, 0x73, 0x00, 0x00, 0x00, 0x93, 0x08, 0xd0, 0x05, 0x13, 0x05, 0x70, 0x00,
    0x73, 0x00, 0x00, 0x00,
};

test "host calls: the program reads --input, writes it out and exits with its status" {
    if (det.Cpu.mem_size < 0x240) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("echo.bin", &echo_program);
    const input = try fx.file("input.txt", "hello, host\n");
    try std.testing.expectEqual(@as(u8, 7), fx.run(&.{ "determinant", prog, "--input", input }));
    try expectContains(fx.out.written(), "executing (unlimited cycles)...\nhello, host\n");
    try expectContains(fx.out.written(), "Program exited with status 7 after 13 cycles");
}

test "host calls: without --input, read returns end of input" {
    if (det.Cpu.mem_size < 0x240) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("echo.bin", &echo_program);
    try std.testing.expectEqual(@as(u8, 7), fx.run(&.{ "determinant", prog }));
    try expectContains(fx.out.written(), "Program exited with status 7");
}

test "host calls: an ECALL that is not a host call stops the program (status 0)" {
    var fx: Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("stop.bin", &.{ 0x73, 0x00, 0x00, 0x00 }); // ECALL with a7 = 0
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), fx.run(&.{ "determinant", prog }));
    try expectContains(fx.out.written(), "ecall after 1 cycles");
}

test "--input: a missing file is a usage error" {
    var fx: Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("stop.bin", &.{ 0x73, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), fx.run(&.{ "determinant", prog, "--input", "/nonexistent/input" }));
    try expectContains(fx.err.written(), "cannot read input");
}

test "--load-addr: a flat binary is loaded and started at the address" {
    if (det.Cpu.mem_size < 0x110) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    // ADDI x1, x0, 42; EBREAK
    const prog = try fx.file("at100.bin", &.{ 0x93, 0x00, 0xA0, 0x02, 0x73, 0x00, 0x10, 0x00 });
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), fx.run(&.{ "determinant", prog, "--load-addr", "0x100" }));
    try expectContains(fx.out.written(), "Loaded 8 bytes at 0x00000100");
    try expectContains(fx.out.written(), "PC = 0x00000108");
    try expectContains(fx.out.written(), "x1 = 42");
}

test "--load-addr: odd, out of range or malformed values are usage errors" {
    var fx: Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("stop.bin", &.{ 0x73, 0x00, 0x00, 0x00 });
    const too_far = try std.fmt.allocPrintSentinel(alloc, "{d}", .{det.Cpu.mem_size}, 0);
    defer alloc.free(too_far);
    for ([_][:0]const u8{ "0x101", too_far, "nope" }) |addr| {
        try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), fx.run(&.{ "determinant", prog, "--load-addr", addr }));
    }
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), fx.run(&.{ "determinant", prog, "--load-addr" }));
}

test "initial sp: programs start with sp at the 16-byte-aligned top of memory" {
    if (det.Cpu.mem_size < 8) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    // ADDI x11, x2, 0 (a1 = sp); EBREAK
    const prog = try fx.file("sp.bin", &.{ 0x93, 0x05, 0x01, 0x00, 0x73, 0x00, 0x10, 0x00 });
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), fx.run(&.{ "determinant", prog }));
    const want = try std.fmt.allocPrint(alloc, "x11 = {d} (0x{X:0>8})", .{ @as(i32, @bitCast(main_mod.initial_sp)), main_mod.initial_sp });
    defer alloc.free(want);
    try expectContains(fx.out.written(), want);
    try std.testing.expectEqual(@as(u32, 0), main_mod.initial_sp % 16);
}

/// A minimal ELF32 RISC-V executable: `code` loaded at `vaddr`, entry at `vaddr`.
fn tinyElf(comptime code: []const u8, vaddr: u32) [52 + 32 + code.len]u8 {
    var b: [52 + 32 + code.len]u8 = @splat(0);
    b[0..4].* = "\x7fELF".*;
    b[4] = 1; // ELFCLASS32
    b[5] = 1; // little-endian
    b[6] = 1; // EV_CURRENT
    std.mem.writeInt(u16, b[16..18], 2, .little); // ET_EXEC
    std.mem.writeInt(u16, b[18..20], 243, .little); // EM_RISCV
    std.mem.writeInt(u32, b[20..24], 1, .little);
    std.mem.writeInt(u32, b[24..28], vaddr, .little); // e_entry
    std.mem.writeInt(u32, b[28..32], 52, .little); // e_phoff
    std.mem.writeInt(u16, b[42..44], 32, .little); // e_phentsize
    std.mem.writeInt(u16, b[44..46], 1, .little); // e_phnum
    std.mem.writeInt(u32, b[52..56], 1, .little); // PT_LOAD
    std.mem.writeInt(u32, b[56..60], 84, .little); // p_offset
    std.mem.writeInt(u32, b[60..64], vaddr, .little); // p_vaddr
    std.mem.writeInt(u32, b[68..72], code.len, .little); // p_filesz
    std.mem.writeInt(u32, b[72..76], code.len, .little); // p_memsz
    @memcpy(b[84..], code);
    return b;
}

test "ELF: the CLI detects an ELF file, loads its segments and starts at its entry" {
    if (det.Cpu.mem_size < 0x50) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    const elf = tinyElf(&.{ 0x93, 0x00, 0xA0, 0x02, 0x73, 0x00, 0x10, 0x00 }, 0x40); // ADDI x1, x0, 42; EBREAK
    const prog = try fx.file("tiny.elf", &elf);
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), fx.run(&.{ "determinant", prog }));
    try expectContains(fx.out.written(), "Loaded ELF executable, entry 0x00000040");
    try expectContains(fx.out.written(), "PC = 0x00000048");
    try expectContains(fx.out.written(), "x1 = 42");
}

test "ELF: a malformed ELF is a usage error" {
    var fx: Fixture = .init();
    defer fx.deinit();
    var elf = tinyElf(&.{ 0x73, 0x00, 0x10, 0x00 }, 0x40);
    elf[18] = 62; // EM_X86_64
    const prog = try fx.file("x86.elf", &elf);
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), fx.run(&.{ "determinant", prog }));
    try expectContains(fx.err.written(), "not a RISC-V ELF32");
}

test "ELF: a toolchain-built executable (crc32) loads and computes the native result" {
    // tests/programs/elf/crc32.elf is built by `zig build programs`; its stack needs
    // 256 KiB, so it runs on its own VM through the library loader.
    const Vm = det.CpuType(256 * 1024, .{});
    const image = try Io.Dir.cwd().readFileAlloc(io, "tests/programs/elf/crc32.elf", alloc, .limited(1 << 20));
    defer alloc.free(image);
    const expected = try Io.Dir.cwd().readFileAlloc(io, "tests/programs/expected/crc32.txt", alloc, .limited(4096));
    defer alloc.free(expected);
    const vm = try alloc.create(Vm);
    defer alloc.destroy(vm);
    vm.reset();
    vm.pc = try det.loader.loadElf(vm, image);
    try std.testing.expectEqual(det.StepResult.ebreak, try vm.run(10_000_000));
    var a0_text: [12]u8 = undefined;
    const a0 = try std.fmt.bufPrint(&a0_text, "a0={x:0>8}", .{vm.readReg(10)});
    try std.testing.expectStringStartsWith(expected, a0);
}

test "host calls: exit(3) is not mistaken for a VM fault (--dump-memory still runs)" {
    if (det.Cpu.mem_size < 16) return error.SkipZigTest;
    var fx: Fixture = .init();
    defer fx.deinit();
    // li a7, 93; li a0, 3; ecall
    const prog = try fx.file("exit3.bin", &.{ 0x93, 0x08, 0xd0, 0x05, 0x13, 0x05, 0x30, 0x00, 0x73, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(@as(u8, 3), fx.run(&.{ "determinant", prog, "--dump-memory" }));
    try expectContains(fx.out.written(), "Program exited with status 3");
    try expectContains(fx.out.written(), "00000000  93 08 D0 05"); // the memory dump ran
    try std.testing.expectEqualStrings("", fx.err.written()); // no fault report
}
