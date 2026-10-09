const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

const io = std.testing.io;
const alloc = std.testing.allocator;

const Args = []const [:0]const u8;
const ExitStatus = main_mod.ExitStatus;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

const Output = struct {
    stdout: Io.Writer.Allocating,
    stderr: Io.Writer.Allocating,

    fn init() Output {
        return .{ .stdout = .init(alloc), .stderr = .init(alloc) };
    }

    fn deinit(self: *Output) void {
        self.stdout.deinit();
        self.stderr.deinit();
    }
};

/// Write `program` to a temporary file and run the CLI on it, followed by `extra` args.
fn runProgram(program: []const u8, extra: []const [:0]const u8, out: *Output) !u8 {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile(io, "prog.bin", .{});
    try f.writeStreamingAll(io, program);
    f.close(io);
    const path = try std.fmt.allocPrintSentinel(alloc, ".zig-cache/tmp/{s}/prog.bin", .{&tmp.sub_path}, 0);
    defer alloc.free(path);

    var args: std.ArrayList([:0]const u8) = .empty;
    defer args.deinit(alloc);
    try args.append(alloc, "determinant");
    try args.append(alloc, path);
    try args.appendSlice(alloc, extra);
    return main_mod.run(io, &out.stdout.writer, &out.stderr.writer, args.items);
}

test "run: program stopping at EBREAK exits 0" {
    var out: Output = .init();
    defer out.deinit();
    const ebreak = [_]u8{ 0x73, 0x00, 0x10, 0x00 };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), try runProgram(&ebreak, &.{}, &out));
    try expectContains(out.stdout.written(), "ebreak after 1 cycles");
}

test "run: demo stopping at ECALL exits 0" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var out: Output = .init();
    defer out.deinit();
    const args: Args = &.{"determinant"};
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), main_mod.run(io, &out.stdout.writer, &out.stderr.writer, args));
}

test "run: --help exits 0 and documents the exit statuses" {
    var out: Output = .init();
    defer out.deinit();
    const args: Args = &.{ "determinant", "--help" };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), main_mod.run(io, &out.stdout.writer, &out.stderr.writer, args));
    try expectContains(out.stdout.written(), "Exit status:");
}

test "run: usage error exits 1" {
    var out: Output = .init();
    defer out.deinit();
    const args: Args = &.{ "determinant", "--bogus" };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), main_mod.run(io, &out.stdout.writer, &out.stderr.writer, args));
    try expectContains(out.stderr.written(), "unknown option");
}

test "run: missing file exits 1" {
    var out: Output = .init();
    defer out.deinit();
    const args: Args = &.{ "determinant", "/nonexistent/determinant_test.bin" };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), main_mod.run(io, &out.stdout.writer, &out.stderr.writer, args));
    try expectContains(out.stderr.written(), "cannot open");
}

test "run: cycle limit exits 2" {
    var out: Output = .init();
    defer out.deinit();
    const loop = [_]u8{ 0x6F, 0x00, 0x00, 0x00 }; // JAL x0, 0 — loops forever
    try std.testing.expectEqual(@intFromEnum(ExitStatus.cycle_limit), try runProgram(&loop, &.{ "--max-cycles", "100" }, &out));
    try expectContains(out.stdout.written(), "Cycle limit reached after 100 cycles");
}

test "run: VM fault exits 3" {
    var out: Output = .init();
    defer out.deinit();
    const illegal = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.vm_fault), try runProgram(&illegal, &.{}, &out));
    try expectContains(out.stderr.written(), "IllegalInstruction");
}

test "run: stdout that cannot be written exits 1 with a message" {
    var failing: Io.Writer = .failing;
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();
    const args: Args = &.{ "determinant", "--help" };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), main_mod.run(io, &failing, &stderr_aw.writer, args));
    try expectContains(stderr_aw.written(), "cannot write output");
}

test "run: unwritable output beats the program's own status" {
    // The program stops at EBREAK (status 0), but its output is lost: exit 1.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile(io, "prog.bin", .{});
    try f.writeStreamingAll(io, &[_]u8{ 0x73, 0x00, 0x10, 0x00 });
    f.close(io);
    const path = try std.fmt.allocPrintSentinel(alloc, ".zig-cache/tmp/{s}/prog.bin", .{&tmp.sub_path}, 0);
    defer alloc.free(path);

    // A buffered writer whose sink fails: printing succeeds into the buffer, and only
    // the final flush fails, which must still turn into a non-zero status.
    var buf: [64 * 1024]u8 = undefined;
    const sink: Io.Writer = .failing;
    var buffered: Io.Writer = .{ .vtable = sink.vtable, .buffer = &buf };
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();
    const args: Args = &.{ "determinant", path };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.usage_or_io), main_mod.run(io, &buffered, &stderr_aw.writer, args));
    try expectContains(stderr_aw.written(), "cannot write output");
}

test "run: a fault reports the instruction and the faulting address" {
    var out: Output = .init();
    defer out.deinit();
    if (det.Cpu.mem_size < 8) return error.SkipZigTest;
    // LUI x1, 0x80000 (x1 = 0x80000000); LW x2, 4(x1) — far out of bounds
    const program = [_]u8{ 0xB7, 0x00, 0x00, 0x80, 0x03, 0xA1, 0x40, 0x00 };
    try std.testing.expectEqual(@intFromEnum(ExitStatus.vm_fault), try runProgram(&program, &.{}, &out));
    try expectContains(out.stderr.written(), "AddressOutOfBounds");
    try expectContains(out.stderr.written(), "PC = 0x00000004");
    try expectContains(out.stderr.written(), "instruction: 0x0040A103 LW x2, 4(x1)");
    try expectContains(out.stderr.written(), "address: 0x80000004");
}

test "stdStreamWriter: output appends at the file's offset instead of overwriting" {
    // Like `determinant --help >> log.txt`: the file already holds data and its offset
    // is at the end. A positional writer would overwrite "EXISTING" from offset 0.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile(io, "log.txt", .{ .read = true });
    defer f.close(io);
    try f.writeStreamingAll(io, "EXISTING\n");

    var buf: [256]u8 = undefined;
    var fw = main_mod.stdStreamWriter(f, io, &buf);
    const args: Args = &.{ "determinant", "--help" };
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();
    try std.testing.expectEqual(@intFromEnum(ExitStatus.ok), main_mod.run(io, &fw.interface, &stderr_aw.writer, args));

    var content: [64]u8 = undefined;
    const n = try f.readPositionalAll(io, &content, 0);
    try std.testing.expectStringStartsWith(content[0..n], "EXISTING\nUsage: determinant");
}
