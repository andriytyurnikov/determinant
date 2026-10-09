//! Memory dumps (--dump-memory, --dump-range): a hexdump -C style listing that
//! collapses repeated lines, or raw hex digits, 32 bytes per line.

const std = @import("std");
const Io = std.Io;

pub const Format = enum { hexdump, raw };

/// Dump `memory`, whose first byte is at address `base`.
pub fn dumpMemory(w: *Io.Writer, memory: []const u8, base: u32, format: Format) Io.Writer.Error!void {
    switch (format) {
        .hexdump => try dumpHexdump(w, memory, base),
        .raw => try dumpRaw(w, memory),
    }
}

fn dumpHexdump(w: *Io.Writer, memory: []const u8, base: u32) Io.Writer.Error!void {
    var prev_line: ?*const [16]u8 = null;
    var collapsing = false;
    var offset: usize = 0;

    while (offset < memory.len) : (offset += 16) {
        const line_len = @min(16, memory.len - offset);
        const line = memory[offset..][0..line_len];

        // A full line equal to the one before is shown as one "*" for the whole run.
        if (line_len == 16) {
            if (prev_line) |prev| {
                if (std.mem.eql(u8, line, prev)) {
                    if (!collapsing) {
                        try w.writeAll("*\n");
                        collapsing = true;
                    }
                    continue;
                }
            }
        }
        collapsing = false;

        try w.print("{X:0>8}  ", .{base + offset});
        for (0..16) |j| {
            if (j == 8) try w.writeAll(" ");
            if (j < line_len) {
                try w.print("{X:0>2} ", .{line[j]});
            } else {
                try w.writeAll("   ");
            }
        }
        try w.writeAll(" |");
        for (line) |c| try w.writeByte(if (c >= 0x20 and c <= 0x7E) c else '.');
        try w.writeAll("|\n");

        prev_line = if (line_len == 16) memory[offset..][0..16] else null;
    }

    // The address just past the end, as hexdump prints it.
    try w.print("{X:0>8}\n", .{base + memory.len});
}

fn dumpRaw(w: *Io.Writer, memory: []const u8) Io.Writer.Error!void {
    var offset: usize = 0;
    while (offset < memory.len) : (offset += 32) {
        for (memory[offset..][0..@min(32, memory.len - offset)]) |byte| try w.print("{X:0>2}", .{byte});
        try w.writeAll("\n");
    }
}
