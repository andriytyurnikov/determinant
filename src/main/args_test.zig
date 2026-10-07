const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

const io = std.testing.io;
const alloc = std.testing.allocator;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

const Args = []const [:0]const u8;

fn runArgs(args: Args, stdout: *Io.Writer, stderr: *Io.Writer) !main_mod.ExitStatus {
    return main_mod.mainInner(io, stdout, stderr, args);
}

test "mainInner: no args runs demo" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{"determinant"};
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Demo");
}

test "mainInner: --help" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "--help" };
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Usage:");
    try expectContains(stdout_aw.written(), "--max-cycles");
}

test "mainInner: -h" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "-h" };
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Usage:");
}

test "mainInner: --max-cycles without file limits the demo" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    // The demo needs 5 cycles; stop it after 2.
    const args: Args = &.{ "determinant", "--max-cycles", "2" };
    try std.testing.expectEqual(main_mod.ExitStatus.cycle_limit, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Demo");
    try expectContains(stdout_aw.written(), "Cycle limit reached after 2 cycles");
}

test "mainInner: unknown flag after path" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--unknown" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "unknown option");
}

test "mainInner: missing --max-cycles value" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "requires a value");
}

test "mainInner: invalid --max-cycles value" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles", "abc" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "invalid");
}

test "mainInner: negative --max-cycles value" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles", "-1" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "invalid");
}

test "mainInner: overflow --max-cycles value" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles", "99999999999999999999" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "invalid");
}

test "mainInner: --max-cycles empty string" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles", "" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "invalid");
}

test "mainInner: extra arguments produce warning" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "test.bin", "--max-cycles", "10", "extra" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "ignoring extra argument");
}

test "mainInner: --dump-memory runs demo with hexdump" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "--dump-memory" };
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Demo");
    try expectContains(stdout_aw.written(), "|");
}

test "mainInner: --dump-memory raw runs demo with raw format" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    // A raw dump prints two hex digits per byte; skip it for very large memories.
    if (det.Cpu.mem_size > 1024 * 1024) return error.SkipZigTest;
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "--dump-memory", "raw" };
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "Demo");
    try expectContains(stdout_aw.written(), "00000000");
}

test "mainInner: --help shows --dump-memory" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "--help" };
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stdout_aw.written(), "--dump-memory");
}

test "mainInner: valid --max-cycles proceeds to file loading" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    const args: Args = &.{ "determinant", "nonexistent.bin", "--max-cycles", "100" };
    try std.testing.expectError(error.UserError, runArgs(args, &stdout_aw.writer, &stderr_aw.writer));

    try expectContains(stderr_aw.written(), "cannot open");
}
