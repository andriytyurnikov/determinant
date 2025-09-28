const std = @import("std");
const main_mod = @import("../main.zig");
const det = @import("determinant");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("\nExpected output NOT to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "printResult: ecall" {
    var vm = det.Cpu.init();
    vm.cycle_count = 42;
    vm.pc = 0x00001000;

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ecall);

    try expectContains(output.items, "ecall after 42 cycles");
    try expectContains(output.items, "PC = 0x00001000");
}

test "printResult: ebreak" {
    var vm = det.Cpu.init();
    vm.cycle_count = 7;

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ebreak);

    try expectContains(output.items, "ebreak after 7 cycles");
}

test "printResult: continue (cycle limit)" {
    var vm = det.Cpu.init();
    vm.cycle_count = 1000;

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .@"continue");

    try expectContains(output.items, "Cycle limit reached after 1000 cycles");
}

test "printResult: non-zero registers displayed" {
    var vm = det.Cpu.init();
    vm.writeReg(1, 42);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ecall);

    try expectContains(output.items, "x1 = 42 (0x0000002A)");
}

test "printResult: negative register display" {
    var vm = det.Cpu.init();
    vm.writeReg(1, 0xFFFFFFFF);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ecall);

    try expectContains(output.items, "x1 = -1 (0xFFFFFFFF)");
}

test "printResult: zero registers omitted" {
    var vm = det.Cpu.init();
    // All registers are zero by default

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ecall);

    // Should have Registers header but no x<N> lines
    try expectContains(output.items, "Registers:");
    try expectNotContains(output.items, "x0 =");
    try expectNotContains(output.items, "x1 =");
}

test "printResult: PC format" {
    var vm = det.Cpu.init();
    vm.pc = 0x00000014;

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try main_mod.printResult(output.writer(std.testing.allocator), &vm, .ecall);

    try expectContains(output.items, "PC = 0x00000014");
}
