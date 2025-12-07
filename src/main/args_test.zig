const std = @import("std");
const main_mod = @import("../main.zig");
const SliceIterator = @import("test_helpers.zig").SliceIterator;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "mainInner: no args runs demo" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{"determinant"} };
    try main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter);

    try expectContains(stdout_buf.items, "Demo");
}

test "mainInner: --help" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "--help" } };
    try main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter);

    try expectContains(stdout_buf.items, "Usage:");
    try expectContains(stdout_buf.items, "--max-cycles");
}

test "mainInner: -h" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "-h" } };
    try main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter);

    try expectContains(stdout_buf.items, "Usage:");
}

test "mainInner: flag before path" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "--max-cycles", "10" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "unexpected option");
}

test "mainInner: unknown flag after path" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--unknown" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "unknown option");
}

test "mainInner: missing --max-cycles value" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "requires a value");
}

test "mainInner: invalid --max-cycles value" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles", "abc" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "invalid");
}

test "mainInner: negative --max-cycles value" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles", "-1" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "invalid");
}

test "mainInner: overflow --max-cycles value" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles", "99999999999999999999" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "invalid");
}

test "mainInner: --max-cycles empty string" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles", "" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "invalid");
}

test "mainInner: extra arguments produce warning" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "test.bin", "--max-cycles", "10", "extra" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "ignoring extra argument");
}

test "mainInner: valid --max-cycles proceeds to file loading" {
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(std.testing.allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(std.testing.allocator);

    var iter = SliceIterator{ .items = &.{ "determinant", "nonexistent.bin", "--max-cycles", "100" } };
    try std.testing.expectError(
        error.UserError,
        main_mod.mainInner(stdout_buf.writer(std.testing.allocator), stderr_buf.writer(std.testing.allocator), &iter),
    );

    try expectContains(stderr_buf.items, "cannot open");
}
