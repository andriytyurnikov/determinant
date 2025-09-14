const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("instructions/test_helpers.zig");

// --- CSR pipeline invariant test ---

test "step: CSR cycle_count sees pre-step value" {
    var cpu = Cpu.init();
    // CSRRS x3, 0xC00, x0 — read cycle counter into x3
    h.loadInst(&cpu, h.encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    // cycle_count was 0 before step, so x3 should be 0 (not 1)
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

// --- Extension dispatch through CPU tests ---

test "step: MUL dispatch through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 7);
    cpu.writeReg(2, 6);
    // MUL x3, x1, x2: opcode=0b0110011, funct3=000, funct7=0b0000001
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: SH1ADD dispatch through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    // SH1ADD x3, x1, x2: opcode=0b0110011, funct3=010, funct7=0b0010000
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3));
}

test "step: CLZ dispatch through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0F000000);
    // CLZ x2, x1: opcode=0b0010011, funct3=001, imm12=0b0110000_00000
    const imm12: u12 = (@as(u12, 0b0110000) << 5) | 0;
    h.loadInst(&cpu, h.encodeI(0b0010011, 0b001, 2, 1, imm12));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2));
}

test "step: BSET dispatch through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 5);
    // BSET x3, x1, x2: opcode=0b0110011, funct3=001, funct7=0b0010100
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}
