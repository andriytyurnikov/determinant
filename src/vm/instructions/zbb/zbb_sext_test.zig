const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

fn encodeR(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return h.encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
}

fn encodeIShamt(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, shamt: u5) u32 {
    const imm12: u12 = (@as(u12, f7) << 5) | @as(u12, shamt);
    return h.encodeI(0b0010011, f3, rd_v, rs1_v, imm12);
}

// --- SEXT_B execute tests ---

test "step: SEXT_B positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0000007F);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000007F), cpu.readReg(3));
}

test "step: SEXT_B negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000080);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(3));
}

test "step: SEXT_B with upper bits set" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEAD0080);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(3));
}

test "step: SEXT_B boundary 0xFF" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x000000FF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // 0xFF as i8 = -1
}

test "step: SEXT_B zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

// --- SEXT_H execute tests ---

test "step: SEXT_H positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00007FFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00007FFF), cpu.readReg(3));
}

test "step: SEXT_H negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00008000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(3));
}

test "step: SEXT_H with upper bits set" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEAD8000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(3));
}

test "step: SEXT_H zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

// --- ZEXT_H execute tests ---

test "step: ZEXT_H basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000BEEF), cpu.readReg(3));
}

test "step: ZEXT_H zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: ZEXT_H max halfword" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0000FFFF);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF), cpu.readReg(3));
}
