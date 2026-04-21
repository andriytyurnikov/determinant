const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

const alloc = std.testing.allocator;

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

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ecall);

    try expectContains(aw.written(), "ecall after 42 cycles");
    try expectContains(aw.written(), "PC = 0x00001000");
}

test "printResult: ebreak" {
    var vm = det.Cpu.init();
    vm.cycle_count = 7;

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ebreak);

    try expectContains(aw.written(), "ebreak after 7 cycles");
}

test "printResult: continue (cycle limit)" {
    var vm = det.Cpu.init();
    vm.cycle_count = 1000;

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .@"continue");

    try expectContains(aw.written(), "Cycle limit reached after 1000 cycles");
}

test "printResult: non-zero registers displayed" {
    var vm = det.Cpu.init();
    vm.writeReg(1, 42);

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ecall);

    try expectContains(aw.written(), "x1 = 42 (0x0000002A)");
}

test "printResult: negative register display" {
    var vm = det.Cpu.init();
    vm.writeReg(1, 0xFFFFFFFF);

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ecall);

    try expectContains(aw.written(), "x1 = -1 (0xFFFFFFFF)");
}

test "printResult: zero registers omitted" {
    var vm = det.Cpu.init();

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ecall);

    try expectContains(aw.written(), "Registers:");
    try expectNotContains(aw.written(), "x0 =");
    try expectNotContains(aw.written(), "x1 =");
}

test "printResult: PC format" {
    var vm = det.Cpu.init();
    vm.pc = 0x00000014;

    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printResult(&aw.writer, &vm, .ecall);

    try expectContains(aw.written(), "PC = 0x00000014");
}
