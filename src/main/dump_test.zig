//! Memory dumps: the hexdump and raw formats, exactly.

const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const dump = main_mod.dump;
const h = @import("test_helpers.zig");

fn expectDump(memory: []const u8, base: u32, format: dump.Format, want: []const u8) !void {
    var aw: Io.Writer.Allocating = .init(h.alloc);
    defer aw.deinit();
    try dump.dumpMemory(&aw.writer, memory, base, format);
    try std.testing.expectEqualStrings(want, aw.written());
}

test "hexdump: one line, with its ASCII column and the end address" {
    try expectDump("Hello World!\x00\x01\x02\x03", 0, .hexdump,
        \\00000000  48 65 6C 6C 6F 20 57 6F  72 6C 64 21 00 01 02 03  |Hello World!....|
        \\00000010
        \\
    );
}

test "hexdump: addresses start at the base address" {
    try expectDump("ABC", 0x100, .hexdump,
        \\00000100  41 42 43                                          |ABC|
        \\00000103
        \\
    );
}

test "hexdump: repeated lines collapse to one '*', and the dump resumes after them" {
    const memory = @as([48]u8, @splat(0)) ++ @as([16]u8, @splat(0xFF));
    try expectDump(&memory, 0, .hexdump,
        \\00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
        \\*
        \\00000030  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  |................|
        \\00000040
        \\
    );
}

test "hexdump: a partial last line is never collapsed" {
    const memory = @as([16]u8, @splat(0)) ++ @as([4]u8, @splat(0));
    try expectDump(&memory, 0, .hexdump,
        \\00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
        \\00000010  00 00 00 00                                       |....|
        \\00000014
        \\
    );
}

test "hexdump: only 0x20..0x7E print as themselves" {
    try expectDump("\x1F\x20\x7E\x7F", 0, .hexdump,
        \\00000000  1F 20 7E 7F                                       |. ~.|
        \\00000004
        \\
    );
}

test "raw: two hex digits per byte, 32 bytes per line, nothing collapsed" {
    const memory = @as([32]u8, @splat(0xAB)) ++ [_]u8{ 0x00, 0x0A, 0xFF, 0x42 };
    const ab_line = std.fmt.bytesToHex(@as([32]u8, @splat(0xAB)), .upper);
    try expectDump(&memory, 0x100, .raw, ab_line ++ "\n000AFF42\n");
    const zero_line = std.fmt.bytesToHex(@as([32]u8, @splat(0)), .upper);
    try expectDump(&@as([64]u8, @splat(0)), 0, .raw, zero_line ++ "\n" ++ zero_line ++ "\n");
}
