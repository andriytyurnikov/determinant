const std = @import("std");
const main_mod = @import("../main.zig");

fn dumpToString(memory: []const u8, format: main_mod.DumpFormat) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(std.testing.allocator);
    try main_mod.dumpMemory(output.writer(std.testing.allocator), memory, format);
    return output.toOwnedSlice(std.testing.allocator);
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
    defer std.testing.allocator.free(result);

    // Address
    try expectContains(result, "00000000");
    // Hex bytes
    try expectContains(result, "48 65 6C 6C 6F 20 57 6F");
    try expectContains(result, "72 6C 64 21 00 01 02 03");
    // ASCII — printable chars shown, non-printable as dots
    try expectContains(result, "|Hello World!....|");
    // Final address (total size)
    try expectContains(result, "00000010\n");
}

test "hexdump: zero-run collapsing" {
    // 64 bytes of zeros — should collapse to first line + * + final address
    var data = [_]u8{0} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .hexdump);
    defer std.testing.allocator.free(result);

    // First line of zeros
    try expectContains(result, "00000000");
    // Collapse marker
    try expectContains(result, "*\n");
    // Final address
    try expectContains(result, "00000040\n");

    // Should NOT have intermediate addresses
    if (std.mem.indexOf(u8, result, "00000010")) |_| {
        return error.TestExpectedEqual;
    }
}

test "hexdump: collapsing then resumption" {
    // 48 bytes: 16 zeros, 16 zeros (collapsed), 16 non-zeros
    var data = [_]u8{0} ** 32 ++ [_]u8{0xFF} ** 16;
    _ = &data;
    const result = try dumpToString(&data, .hexdump);
    defer std.testing.allocator.free(result);

    // First zero line
    try expectContains(result, "00000000");
    // Collapse marker
    try expectContains(result, "*\n");
    // Resumed line with FF bytes
    try expectContains(result, "00000020");
    try expectContains(result, "FF FF FF FF");
    // Final address
    try expectContains(result, "00000030\n");
}

test "hexdump: partial last line" {
    const data = [_]u8{ 0x41, 0x42, 0x43 };
    const result = try dumpToString(&data, .hexdump);
    defer std.testing.allocator.free(result);

    // Should show 3 bytes then padding
    try expectContains(result, "41 42 43");
    try expectContains(result, "|ABC|");
    // Final address
    try expectContains(result, "00000003\n");
}

test "hexdump: ASCII printable range" {
    // Test boundary characters: 0x1F (non-printable), 0x20 (space), 0x7E (~), 0x7F (non-printable)
    var data = [_]u8{0} ** 16;
    data[0] = 0x1F;
    data[1] = 0x20;
    data[2] = 0x7E;
    data[3] = 0x7F;
    const result = try dumpToString(&data, .hexdump);
    defer std.testing.allocator.free(result);

    // 0x1F → dot, 0x20 → space, 0x7E → ~, 0x7F → dot
    try expectContains(result, "|. ~.");
}

test "raw: hex encoding" {
    const data = [_]u8{ 0x00, 0x0A, 0xFF, 0x42 };
    const result = try dumpToString(&data, .raw);
    defer std.testing.allocator.free(result);

    try expectContains(result, "000AFF42");
}

test "raw: line breaks at 32 bytes" {
    var data = [_]u8{0xAB} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .raw);
    defer std.testing.allocator.free(result);

    // Each line should be 64 hex chars (32 bytes) + newline
    var lines = std.mem.splitScalar(u8, result, '\n');
    const line1 = lines.next().?;
    try std.testing.expectEqual(@as(usize, 64), line1.len);
    const line2 = lines.next().?;
    try std.testing.expectEqual(@as(usize, 64), line2.len);
}

test "raw: no collapsing" {
    // 64 bytes of zeros — raw format should NOT collapse
    var data = [_]u8{0} ** 64;
    _ = &data;
    const result = try dumpToString(&data, .raw);
    defer std.testing.allocator.free(result);

    // Should have 2 full lines (no * collapsing)
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
