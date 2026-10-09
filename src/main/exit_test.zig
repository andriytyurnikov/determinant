//! Exit statuses, and output that cannot be written.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const main_mod = @import("../main.zig");
const h = @import("test_helpers.zig");

test "exit status: one row per way a run ends" {
    const Case = struct { program: ?[]const u8, args: []const [:0]const u8 = &.{}, want: h.ExitStatus };
    const cases = [_]Case{
        .{ .program = &h.ebreak, .want = .ok },
        .{ .program = &h.ecall, .want = .ok },
        .{ .program = &h.loop, .args = &.{ "--max-cycles", "100" }, .want = .cycle_limit },
        .{ .program = &h.loop, .args = &.{ "--max-cycles", "0" }, .want = .cycle_limit },
        .{ .program = &h.illegal, .want = .vm_fault },
        .{ .program = &h.ebreak, .args = &.{"--bogus"}, .want = .usage_or_io },
        .{ .program = null, .args = &.{"/nonexistent/determinant_test.bin"}, .want = .usage_or_io },
        .{ .program = null, .args = &.{}, .want = .usage_or_io },
        .{ .program = null, .args = &.{"--help"}, .want = .ok },
        .{ .program = null, .args = &.{"--version"}, .want = .ok },
        .{ .program = &h.ebreak, .args = &.{"--disassemble"}, .want = .ok },
    };
    var fx: h.Fixture = .init();
    defer fx.deinit();
    for (cases) |c| {
        var argv: std.ArrayList([:0]const u8) = .empty;
        defer argv.deinit(h.alloc);
        if (c.program) |p| try argv.append(h.alloc, try fx.file("prog.bin", p));
        try argv.appendSlice(h.alloc, c.args);
        errdefer std.debug.print("\nargs: {any}\nstderr: {s}\n", .{ c.args, fx.stderr() });
        try std.testing.expectEqual(h.status(c.want), try fx.run(argv.items));
    }
}

test "VM memory that cannot be allocated: a message and exit status 1" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    var cli = fx.cli();
    cli.gpa = std.testing.failing_allocator;
    try std.testing.expectEqual(h.status(.usage_or_io), cli.run(&.{ "determinant", "--demo", "--memory", "3GiB" }));
    try std.testing.expectEqualStrings("Error: cannot allocate 3 GiB of VM memory\n", fx.stderr());
}

/// A buffered writer whose sink fails: printing succeeds into the buffer, and only
/// the flush fails.
fn failingBuffered(buf: []u8) Io.Writer {
    const sink: Io.Writer = .failing;
    return .{ .vtable = sink.vtable, .buffer = buf };
}

test "unwritable output: stdout for --help gives exit status 1 and a message" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    var failing: Io.Writer = .failing;
    var cli = fx.cli();
    cli.stdout = &failing;
    try std.testing.expectEqual(h.status(.usage_or_io), cli.run(&.{ "determinant", "--help" }));
    try std.testing.expectEqualStrings("Error: cannot write output\n", fx.stderr());
}

test "unwritable output: the program's output lost beats its own exit status" {
    // Before the report, stdout is flushed and fails there; with -q, and for a
    // listing, only the final flush finds out.
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("hello.bin", &h.hello);
    const runs = [_][]const [:0]const u8{ &.{ "determinant", prog }, &.{ "determinant", prog, "-q" }, &.{ "determinant", prog, "--disassemble" } };
    for (runs) |argv| {
        var buf: [64 * 1024]u8 = undefined;
        var stdout = failingBuffered(&buf);
        fx.err.clearRetainingCapacity();
        var cli = fx.cli();
        cli.stdout = &stdout;
        try std.testing.expectEqual(h.status(.usage_or_io), cli.run(argv));
        try h.expectContains(fx.stderr(), "Error: cannot write output\n");
    }
}

test "unwritable output: a report that cannot be written gives exit status 1" {
    // The program stops at EBREAK (status 0) and writes nothing, but its report is lost.
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("stop.bin", &h.ebreak);
    var buf: [64 * 1024]u8 = undefined;
    var stderr = failingBuffered(&buf);
    var cli = fx.cli();
    cli.stderr = &stderr;
    try std.testing.expectEqual(h.status(.usage_or_io), cli.run(&.{ "determinant", prog }));
}

test "stdStreamWriter: output appends at the file's offset instead of overwriting" {
    // Like `determinant --help >> log.txt`: the file already holds data and its offset
    // is at the end. A positional writer would overwrite "EXISTING" from offset 0.
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const f = try fx.tmp.dir.createFile(h.io, "log.txt", .{ .read = true });
    defer f.close(h.io);
    try f.writeStreamingAll(h.io, "EXISTING\n");

    var buf: [256]u8 = undefined;
    var fw = main_mod.stdStreamWriter(f, h.io, &buf);
    var cli = fx.cli();
    cli.stdout = &fw.interface;
    try std.testing.expectEqual(h.status(.ok), cli.run(&.{ "determinant", "--help" }));

    var content: [64]u8 = undefined;
    const n = try f.readPositionalAll(h.io, &content, 0);
    try std.testing.expectStringStartsWith(content[0..n], "EXISTING\nUsage: determinant");
}

test "the fault report comes after the program's output, even with unbuffered stderr" {
    // stdout buffered, stderr unbuffered, both into one file as with `> log 2>&1`.
    // Only the flush before the report keeps the report after what stdout printed.
    var fx: h.Fixture = .init();
    defer fx.deinit();
    // hello, with its exit replaced by an illegal instruction
    var program = h.hello;
    program[24..28].* = h.illegal;
    const prog = try fx.file("prog.bin", &program);

    const log = try fx.tmp.dir.createFile(h.io, "log.txt", .{ .read = true });
    defer log.close(h.io);
    var out_buf: [4096]u8 = undefined;
    var no_buf: [0]u8 = undefined;
    var out_fw = main_mod.stdStreamWriter(log, h.io, &out_buf);
    var err_fw = main_mod.stdStreamWriter(log, h.io, &no_buf);
    var cli = fx.cli();
    cli.stdout = &out_fw.interface;
    cli.stderr = &err_fw.interface;
    try std.testing.expectEqual(h.status(.vm_fault), cli.run(&.{ "determinant", prog }));

    var content: [4096]u8 = undefined;
    const text = content[0..try log.readPositionalAll(h.io, &content, 0)];
    const output = std.mem.find(u8, text, "hello\n") orelse return error.TestExpectedEqual;
    const fault = std.mem.find(u8, text, "Fault after") orelse return error.TestExpectedEqual;
    try std.testing.expect(output < fault);
}
