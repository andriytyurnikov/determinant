const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");

const alloc = std.testing.allocator;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "runDemo: deterministic output" {
    var out_aw: Io.Writer.Allocating = .init(alloc);
    defer out_aw.deinit();
    var err_aw: Io.Writer.Allocating = .init(alloc);
    defer err_aw.deinit();
    try main_mod.runDemo(&out_aw.writer, &err_aw.writer, null);

    const output = out_aw.written();

    try expectContains(output, "Demo");
    try expectContains(output, "ADDI");
    try expectContains(output, "ADD");
    try expectContains(output, "SW");
    try expectContains(output, "ECALL");
    try expectContains(output, "ecall after 5 cycles");
    try expectContains(output, "x1 = 100");
    try expectContains(output, "x2 = 10");
    try expectContains(output, "x3 = 110");
    try expectContains(output, "Memory[100] = 110");
}

test "runDemo: reproducible output" {
    var out1: Io.Writer.Allocating = .init(alloc);
    defer out1.deinit();
    var err1: Io.Writer.Allocating = .init(alloc);
    defer err1.deinit();
    try main_mod.runDemo(&out1.writer, &err1.writer, null);

    var out2: Io.Writer.Allocating = .init(alloc);
    defer out2.deinit();
    var err2: Io.Writer.Allocating = .init(alloc);
    defer err2.deinit();
    try main_mod.runDemo(&out2.writer, &err2.writer, null);

    try std.testing.expectEqualStrings(out1.written(), out2.written());
}
