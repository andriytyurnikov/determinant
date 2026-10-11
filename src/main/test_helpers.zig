//! Shared helpers for the CLI tests: a Fixture that writes files into a temporary
//! directory and runs the CLI with a fixed stdin and captured stdout and stderr,
//! programs as little-endian words, and output assertions.

const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

pub const io = std.testing.io;
pub const alloc = std.testing.allocator;
pub const ExitStatus = main_mod.ExitStatus;

pub fn status(s: ExitStatus) u8 {
    return @backingInt(s);
}

pub fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

pub fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) != null) {
        std.debug.print("\nExpected output NOT to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

/// A program given as instruction words, in little-endian bytes.
pub fn le(comptime words: []const u32) [4 * words.len]u8 {
    var bytes: [4 * words.len]u8 = undefined;
    for (words, 0..) |w, i| std.mem.writeInt(u32, bytes[4 * i ..][0..4], w, .little);
    return bytes;
}

pub const ebreak = le(&.{0x00100073});
/// ECALL with a7 = 0: not a host call, so the CLI stops.
pub const ecall = le(&.{0x00000073});
pub const illegal = le(&.{0xFFFFFFFF});
/// JAL x0, 0: loops forever.
pub const loop = le(&.{0x0000006F});

/// write(1, "hello\n", 6); exit(7). 42 bytes.
pub const hello = le(&.{
    0x00000597, // AUIPC a1, 0
    0x02458593, // ADDI a1, a1, 36 (the message)
    0x00100513, // ADDI a0, zero, 1
    0x00600613, // ADDI a2, zero, 6
    0x04000893, // ADDI a7, zero, 64 (write)
    0x00000073, // ECALL
    0x00700513, // ADDI a0, zero, 7
    0x05D00893, // ADDI a7, zero, 93 (exit)
    0x00000073, // ECALL
}) ++ "hello\n".*;

/// read(0, 0x200, 64); write(1, 0x200, n); exit(7). Needs 0x240 bytes of memory.
pub const echo = le(&.{
    0x03F00893, // ADDI a7, zero, 63 (read)
    0x00000513, // ADDI a0, zero, 0
    0x20000593, // ADDI a1, zero, 0x200
    0x04000613, // ADDI a2, zero, 64
    0x00000073, // ECALL
    0x00050613, // ADDI a2, a0, 0
    0x04000893, // ADDI a7, zero, 64 (write)
    0x00100513, // ADDI a0, zero, 1
    0x20000593, // ADDI a1, zero, 0x200
    0x00000073, // ECALL
    0x05D00893, // ADDI a7, zero, 93 (exit)
    0x00700513, // ADDI a0, zero, 7
    0x00000073, // ECALL
});

/// A minimal ELF32 RISC-V executable: `code` in one PT_LOAD segment at `vaddr`, which
/// is also the entry point, with these p_flags (5 = PF_R | PF_X).
pub fn tinyElf(comptime code: []const u8, vaddr: u32, flags: u32) [52 + 32 + code.len]u8 {
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
    std.mem.writeInt(u32, b[76..80], flags, .little); // p_flags
    @memcpy(b[84..], code);
    return b;
}

/// Files in a temporary directory, and a CLI with a fixed stdin and captured output.
pub const Fixture = struct {
    tmp: std.testing.TmpDir,
    out: Io.Writer.Allocating,
    err: Io.Writer.Allocating,
    stdin: Io.Reader = .fixed(""),
    paths: std.ArrayList([:0]u8) = .empty,

    pub fn init() Fixture {
        return .{ .tmp = std.testing.tmpDir(.{}), .out = .init(alloc), .err = .init(alloc) };
    }

    pub fn deinit(self: *Fixture) void {
        for (self.paths.items) |p| alloc.free(p);
        self.paths.deinit(alloc);
        self.out.deinit();
        self.err.deinit();
        self.tmp.cleanup();
    }

    /// Write a file and return its path, relative to the build root (the cwd).
    pub fn file(self: *Fixture, name: []const u8, bytes: []const u8) ![:0]const u8 {
        const f = try self.tmp.dir.createFile(io, name, .{});
        try f.writeStreamingAll(io, bytes);
        f.close(io);
        return self.path(name);
    }

    /// The cwd-relative path of `name` in the temporary directory.
    pub fn path(self: *Fixture, name: []const u8) ![:0]const u8 {
        const p = try alloc.printSentinel(".zig-cache/tmp/{s}/{s}", .{ &self.tmp.sub_path, name }, 0);
        try self.paths.append(alloc, p);
        return p;
    }

    pub fn cli(self: *Fixture) main_mod.Cli {
        return .{ .io = io, .gpa = alloc, .stdin = &self.stdin, .stdout = &self.out.writer, .stderr = &self.err.writer };
    }

    /// Run the CLI with these arguments (after the program name) and return its exit
    /// status. Output from earlier runs is discarded first.
    pub fn run(self: *Fixture, args: []const [:0]const u8) !u8 {
        self.out.clearRetainingCapacity();
        self.err.clearRetainingCapacity();
        var argv: std.ArrayList([:0]const u8) = .empty;
        defer argv.deinit(alloc);
        try argv.append(alloc, "determinant");
        try argv.appendSlice(alloc, args);
        return self.cli().run(argv.items);
    }

    pub fn stdout(self: *Fixture) []const u8 {
        return self.out.written();
    }

    pub fn stderr(self: *Fixture) []const u8 {
        return self.err.written();
    }
};

/// `template` with this build's values: {path} is `path`, {mem} the memory size, {sp}
/// the initial sp in 8 hex digits and {sp_dec} in signed decimal. The caller frees it.
pub fn expand(template: []const u8, path: []const u8) ![]u8 {
    var buf: [3][32]u8 = undefined;
    const vars = [_][2][]const u8{
        .{ "{path}", path },
        .{ "{mem}", try std.mem.print(&buf[0], "{f}", .{main_mod.units.MemSize{ .bytes = det.Cpu.mem_size }}) },
        .{ "{sp}", try std.mem.print(&buf[1], "{X:0>8}", .{main_mod.initial_sp}) },
        .{ "{sp_dec}", try std.mem.print(&buf[2], "{d}", .{@as(i32, @bitCast(main_mod.initial_sp))}) },
    };
    var text = try alloc.dupe(u8, template);
    for (vars) |v| {
        const next = try std.mem.replaceOwned(u8, alloc, text, v[0], v[1]);
        alloc.free(text);
        text = next;
    }
    return text;
}

/// Skip a test whose program needs more VM memory than the build has.
pub fn needMemory(bytes: u32) !void {
    if (det.Cpu.mem_size < bytes) return error.SkipZigTest;
}
