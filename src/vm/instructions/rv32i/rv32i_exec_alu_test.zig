const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests (I-extension ALU step tests) ===

test "step: ADDI" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    loadInst(&cpu, 0x02A00093);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "step: ADDI negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    // ADDI x2, x1, -1 = 0xFFF08113
    loadInst(&cpu, 0xFFF08113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 99), cpu.readReg(2));
}

test "step: ADD" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 10);
    // ADD x3, x1, x2 = 0x002081B3
    loadInst(&cpu, 0x002081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 15), cpu.readReg(3));
}

test "step: SUB" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 7);
    // SUB x3, x1, x2 = 0x402081B3
    loadInst(&cpu, 0x402081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 13), cpu.readReg(3));
}

test "step: SUB wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 1);
    // SUB x3, x1, x2
    loadInst(&cpu, 0x402081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: SLL" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 4);
    // SLL x3, x1, x2 = 0x002091B3
    loadInst(&cpu, 0x002091B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 16), cpu.readReg(3));
}

test "step: SLT signed" {
    var cpu = Cpu.init();
    // -1 (0xFFFFFFFF) < 1 signed
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // SLT x3, x1, x2 = 0x0020A1B3
    loadInst(&cpu, 0x0020A1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

test "step: SLTU unsigned" {
    var cpu = Cpu.init();
    // 0xFFFFFFFF > 1 unsigned
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // SLTU x3, x1, x2 = 0x0020B1B3
    loadInst(&cpu, 0x0020B1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: XOR" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    // XOR x3, x1, x2 = 0x0020C1B3
    loadInst(&cpu, 0x0020C1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF00FF00F), cpu.readReg(3));
}

test "step: SRL" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 4);
    // SRL x3, x1, x2 = 0x0020D1B3
    loadInst(&cpu, 0x0020D1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x08000000), cpu.readReg(3));
}

test "step: SRA" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // -2147483648
    cpu.writeReg(2, 4);
    // SRA x3, x1, x2 = 0x4020D1B3
    loadInst(&cpu, 0x4020D1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF8000000), cpu.readReg(3));
}

test "step: OR" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xF0F0F0F0);
    cpu.writeReg(2, 0x0F0F0F0F);
    // OR x3, x1, x2 = 0x0020E1B3
    loadInst(&cpu, 0x0020E1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: AND" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    // AND x3, x1, x2 = 0x0020F1B3
    loadInst(&cpu, 0x0020F1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0F000F00), cpu.readReg(3));
}

test "step: SLTI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    // SLTI x2, x1, 10 = 0x00A0A113
    loadInst(&cpu, 0x00A0A113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: SLTIU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    // SLTIU x2, x1, 10 = 0x00A0B113
    loadInst(&cpu, 0x00A0B113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: XORI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    // XORI x2, x1, 0x0F = 0x00F0C113
    loadInst(&cpu, 0x00F0C113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.readReg(2));
}

test "step: ORI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xF0);
    // ORI x2, x1, 0x0F = 0x00F0E113
    loadInst(&cpu, 0x00F0E113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(2));
}

test "step: ANDI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    // ANDI x2, x1, 0x0F = 0x00F0F113
    loadInst(&cpu, 0x00F0F113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0F), cpu.readReg(2));
}

test "step: SLLI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    // SLLI x2, x1, 31 = 0x01F09113
    loadInst(&cpu, 0x01F09113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(2));
}

test "step: SRLI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    // SRLI x2, x1, 31 = 0x01F0D113
    loadInst(&cpu, 0x01F0D113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: SRAI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    // SRAI x2, x1, 31 = 0x41F0D113
    loadInst(&cpu, 0x41F0D113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(2));
}

test "step: shift by 0" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    // SLLI x2, x1, 0 = 0x00009113
    loadInst(&cpu, 0x00009113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(2));
}

test "step: x0 writes ignored" {
    var cpu = Cpu.init();
    // ADDI x0, x0, 42 — should not change x0
    loadInst(&cpu, 0x02A00013);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}
