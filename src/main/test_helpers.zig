const std = @import("std");

/// Fake argument iterator for testing mainInner.
/// Mimics the interface of std.process.ArgIterator (has next() -> ?[]const u8).
pub const SliceIterator = struct {
    items: []const []const u8,
    index: usize = 0,

    pub fn next(self: *SliceIterator) ?[]const u8 {
        if (self.index >= self.items.len) return null;
        const item = self.items[self.index];
        self.index += 1;
        return item;
    }
};
