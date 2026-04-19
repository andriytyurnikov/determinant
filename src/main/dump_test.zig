const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");

const alloc = std.testing.allocator;

fn dumpToString(memory: []const u8, format: main_mod.DumpFormat) ![]u8 {
    var aw: Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    try main_mod.dumpMemory(&aw.writer, memory, format);
    var list = aw.toArrayList();
    return list.toOwnedSlice(alloc);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "hexdump: single line" {
    const data = [_]u8{ 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x57, 0x6F, 0x72, 0x6C, 0x64, 0x21, 0x00, 0x01, 0x02, 0x03 };
    const result = try dumpToString(&data, .hexdump);
    defer alloc.free(result);

    try expectContains(result, "00000000");
    try expectContains(result, "48 65 6C 6C 6F 20 57 6F");
    try expectContains(result, "72 6C 64 21 00 01 02 03");
    try expectContains(result, "|Hello World!....|");
    try expectContains(result, "00000010\n");
}

test "hexdump: zero-run collapsing" {
    var data = [_]u8{0} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .hexdump);
    defer alloc.free(result);

    try expectContains(result, "00000000");
    try expectContains(result, "*\n");
    try expectContains(result, "00000040\n");

    if (std.mem.indexOf(u8, result, "00000010")) |_| {
        return error.TestExpectedEqual;
    }
}

test "hexdump: collapsing then resumption" {
    var data = [_]u8{0} ** 32 ++ [_]u8{0xFF} ** 16;
    _ = &data;
    const result = try dumpToString(&data, .hexdump);
    defer alloc.free(result);

    try expectContains(result, "00000000");
    try expectContains(result, "*\n");
    try expectContains(result, "00000020");
    try expectContains(result, "FF FF FF FF");
    try expectContains(result, "00000030\n");
}

test "hexdump: partial last line" {
    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const result = try dumpToString(&data, .hexdump);
    defer alloc.free(result);

    try expectContains(result, "41 42 43");
    try expectContains(result, "|ABC|");
    try expectContains(result, "00000003\n");
}

test "hexdump: ASCII printable range" {
    var data = [_]u8{0} ** 16;
    data[0] = 0x1F;
    data[1] = 0x20;
    data[2] = 0x7E;
    data[3] = 0x7F;
    const result = try dumpToString(&data, .hexdump);
    defer alloc.free(result);

    try expectContains(result, "|. ~.");
}

test "raw: hex encoding" {
    const data = [_]u8{ 0x00, 0x0A, 0xFF, 0x42 };
    const result = try dumpToString(&data, .raw);
    defer alloc.free(result);

    try expectContains(result, "000AFF42");
}

test "raw: line breaks at 32 bytes" {
    var data = [_]u8{0xAB} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .raw);
    defer alloc.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    const line1 = lines.next().?;
    try std.testing.expectEqual(@as(usize, 64), line1.len);
    const line2 = lines.next().?;
    try std.testing.expectEqual(@as(usize, 64), line2.len);
}

test "raw: no collapsing" {
    var data = [_]u8{0} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .raw);
    defer alloc.free(result);

    if (std.mem.indexOf(u8, result, "*")) |_| {
        return error.TestExpectedEqual;
    }

    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, result, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), line_count);
}
