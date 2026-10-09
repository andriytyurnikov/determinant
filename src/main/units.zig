//! Quantities in the CLI's messages: memory sizes ("64 KiB") and counts with their
//! noun ("1 cycle", "9 cycles").

const std = @import("std");
const Io = std.Io;

/// Exact memory size: "64 KiB", "1 MiB", "2 GiB" or "100 bytes".
pub const MemSize = struct {
    bytes: u32,

    pub fn format(self: MemSize, w: *Io.Writer) Io.Writer.Error!void {
        if (self.bytes != 0 and self.bytes % (1024 * 1024 * 1024) == 0) return w.print("{d} GiB", .{self.bytes / (1024 * 1024 * 1024)});
        if (self.bytes != 0 and self.bytes % (1024 * 1024) == 0) return w.print("{d} MiB", .{self.bytes / (1024 * 1024)});
        if (self.bytes != 0 and self.bytes % 1024 == 0) return w.print("{d} KiB", .{self.bytes / 1024});
        return w.print("{f}", .{count(self.bytes, "byte")});
    }
};

/// A number and its noun, plural unless the number is 1: "1 cycle", "0 cycles".
pub const Count = struct {
    n: u64,
    noun: []const u8,

    pub fn format(self: Count, w: *Io.Writer) Io.Writer.Error!void {
        return w.print("{d} {s}{s}", .{ self.n, self.noun, if (self.n == 1) "" else "s" });
    }
};

pub fn count(n: u64, noun: []const u8) Count {
    return .{ .n = n, .noun = noun };
}

pub fn cycles(n: u64) Count {
    return count(n, "cycle");
}
