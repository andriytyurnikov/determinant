const std = @import("std");
const main_mod = @import("../main.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "runDemo: deterministic output" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    var err_output: std.ArrayList(u8) = .empty;
    defer err_output.deinit(std.testing.allocator);
    try main_mod.runDemo(output.writer(std.testing.allocator), err_output.writer(std.testing.allocator), null);

    // Header
    try expectContains(output.items, "Demo");

    // Disassembly of 5 instructions
    try expectContains(output.items, "ADDI");
    try expectContains(output.items, "ADD");
    try expectContains(output.items, "SW");
    try expectContains(output.items, "ECALL");

    // Execution result
    try expectContains(output.items, "ecall after 5 cycles");

    // Register values
    try expectContains(output.items, "x1 = 100");
    try expectContains(output.items, "x2 = 10");
    try expectContains(output.items, "x3 = 110");

    // Memory store result
    try expectContains(output.items, "Memory[100] = 110");
}

test "runDemo: reproducible output" {
    var output1: std.ArrayList(u8) = .empty;
    defer output1.deinit(std.testing.allocator);
    var err_output1: std.ArrayList(u8) = .empty;
    defer err_output1.deinit(std.testing.allocator);
    try main_mod.runDemo(output1.writer(std.testing.allocator), err_output1.writer(std.testing.allocator), null);

    var output2: std.ArrayList(u8) = .empty;
    defer output2.deinit(std.testing.allocator);
    var err_output2: std.ArrayList(u8) = .empty;
    defer err_output2.deinit(std.testing.allocator);
    try main_mod.runDemo(output2.writer(std.testing.allocator), err_output2.writer(std.testing.allocator), null);

    try std.testing.expectEqualStrings(output1.items, output2.items);
}
