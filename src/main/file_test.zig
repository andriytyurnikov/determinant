const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");

const io = std.testing.io;
const alloc = std.testing.allocator;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

/// Build a path relative to cwd pointing into the TmpDir. tmpDir() roots its dirs
/// under `.zig-cache/tmp/<sub_path>/` and that's cwd-relative during `zig build test`.
fn makeTmpPath(tmp: std.testing.TmpDir, sub_path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/{s}", .{ &tmp.sub_path, sub_path });
}

test "runFile: empty file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = try tmp.dir.createFile(io, "empty.bin", .{});
    f.close(io);

    const path = try makeTmpPath(tmp, "empty.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, null, null),
    );

    try expectContains(stderr_aw.written(), "file is empty");
}

test "runFile: file too large" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = try tmp.dir.createFile(io, "big.bin", .{});
    defer f.close(io);

    const big_buf = try alloc.alloc(u8, 65537);
    defer alloc.free(big_buf);
    @memset(big_buf, 0x13); // NOP opcode byte
    try f.writeStreamingAll(io, big_buf);

    const path = try makeTmpPath(tmp, "big.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, null, null),
    );

    try expectContains(stderr_aw.written(), "file too large");
}

test "runFile: nonexistent file" {
    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, "/tmp/determinant_nonexistent_test_file.bin", null, null),
    );

    try expectContains(stderr_aw.written(), "cannot open");
}

test "runFile: successful execution" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // ADDI x1, x0, 42 + ECALL
    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile(io, "test.bin", .{});
    try f.writeStreamingAll(io, &program);
    f.close(io);

    const path = try makeTmpPath(tmp, "test.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, null, null);

    try expectContains(stdout_aw.written(), "Loaded 8 bytes");
    try expectContains(stdout_aw.written(), "ecall");
    try expectContains(stdout_aw.written(), "x1 = 42");
}

test "runFile: max cycles display" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile(io, "test.bin", .{});
    try f.writeStreamingAll(io, &program);
    f.close(io);

    const path = try makeTmpPath(tmp, "test.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, 1000, null);

    try expectContains(stdout_aw.written(), "max 1000 cycles");
}

test "runFile: unlimited cycles display" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile(io, "test.bin", .{});
    try f.writeStreamingAll(io, &program);
    f.close(io);

    const path = try makeTmpPath(tmp, "test.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, null, null);

    try expectContains(stdout_aw.written(), "unlimited cycles");
}

test "runFile: cycle limit reached" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 4 NOPs + ECALL; with max_cycles=2, only NOPs execute
    const program = [_]u8{
        0x13, 0x00, 0x00, 0x00, // NOP
        0x13, 0x00, 0x00, 0x00, // NOP
        0x13, 0x00, 0x00, 0x00, // NOP
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile(io, "test.bin", .{});
    try f.writeStreamingAll(io, &program);
    f.close(io);

    const path = try makeTmpPath(tmp, "test.bin");
    defer alloc.free(path);

    var stdout_aw: Io.Writer.Allocating = .init(alloc);
    defer stdout_aw.deinit();
    var stderr_aw: Io.Writer.Allocating = .init(alloc);
    defer stderr_aw.deinit();

    try main_mod.runFile(io, &stdout_aw.writer, &stderr_aw.writer, path, 2, null);

    try expectContains(stdout_aw.written(), "Cycle limit reached");
}
