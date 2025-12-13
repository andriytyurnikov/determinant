const std = @import("std");
const main_mod = @import("../main.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

fn makeTmpPath(tmp_dir: std.testing.TmpDir, sub_path: []const u8) ![]const u8 {
    return tmp_dir.dir.realpathAlloc(std.testing.allocator, sub_path);
}

test "runFile: empty file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create empty file
    const f = try tmp.dir.createFile("empty.bin", .{});
    f.close();

    const path = try makeTmpPath(tmp, "empty.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, null),
    );

    try expectContains(stderr_buf.items, "file is empty");
}

test "runFile: file too large" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create file larger than VM memory (65536)
    const f = try tmp.dir.createFile("big.bin", .{});
    defer f.close();

    const big_buf = try std.testing.allocator.alloc(u8, 65537);
    defer std.testing.allocator.free(big_buf);
    @memset(big_buf, 0x13); // NOP opcode byte
    try f.writeAll(big_buf);

    const path = try makeTmpPath(tmp, "big.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, null),
    );

    try expectContains(stderr_buf.items, "file too large");
}

test "runFile: nonexistent file" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UserError,
        main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), "/tmp/determinant_nonexistent_test_file.bin", null),
    );

    try expectContains(stderr_buf.items, "cannot open");
}

test "runFile: successful execution" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // ADDI x1, x0, 42 + ECALL
    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile("test.bin", .{});
    try f.writeAll(&program);
    f.close();

    const path = try makeTmpPath(tmp, "test.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, null);

    try expectContains(stdout_buf.items, "Loaded 8 bytes");
    try expectContains(stdout_buf.items, "ecall");
    try expectContains(stdout_buf.items, "x1 = 42");
}

test "runFile: max cycles display" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile("test.bin", .{});
    try f.writeAll(&program);
    f.close();

    const path = try makeTmpPath(tmp, "test.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, 1000);

    try expectContains(stdout_buf.items, "max 1000 cycles");
}

test "runFile: unlimited cycles display" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const program = [_]u8{
        0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    const f = try tmp.dir.createFile("test.bin", .{});
    try f.writeAll(&program);
    f.close();

    const path = try makeTmpPath(tmp, "test.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, null);

    try expectContains(stdout_buf.items, "unlimited cycles");
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

    const f = try tmp.dir.createFile("test.bin", .{});
    try f.writeAll(&program);
    f.close();

    const path = try makeTmpPath(tmp, "test.bin");
    defer std.testing.allocator.free(path);

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    try main_mod.runFile(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), path, 2);

    try expectContains(stdout_buf.items, "Cycle limit reached");
}
