const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests: branches ===

test "step: BEQ taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BEQ not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: BNE taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BNE x1, x2, +8 = 0x00209463
    loadInst(&cpu, 0x00209463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BNE not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    // BNE x1, x2, +8 = 0x00209463
    loadInst(&cpu, 0x00209463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: BLT signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF); // -1
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8 = 0x0020C463
    loadInst(&cpu, 0x0020C463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGE signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF); // -1
    // BGE x1, x2, +8 = 0x0020D463
    loadInst(&cpu, 0x0020D463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLTU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF);
    // BLTU x1, x2, +8 = 0x0020E463
    loadInst(&cpu, 0x0020E463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLTU not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 2);
    cpu.writeReg(2, 1);
    // BLTU x1, x2, +8 = 0x0020E463
    loadInst(&cpu, 0x0020E463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: BGEU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // BGEU x1, x2, +8 = 0x0020F463
    loadInst(&cpu, 0x0020F463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGEU not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BGEU x1, x2, +8 = 0x0020F463
    loadInst(&cpu, 0x0020F463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}
