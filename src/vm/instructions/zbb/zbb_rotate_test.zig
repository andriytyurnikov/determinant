const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder/branch_decoder.zig");
const decode = decoder.decode;
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

// --- ROL/ROR/RORI execute tests ---

test "step: ROL basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000003), cpu.readReg(3));
}

test "step: ROL by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: ROL by 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: ROL with high rs2 (shift amount masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 0x21); // 33 & 0x1F = 1
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000003), cpu.readReg(3));
}

test "step: ROR basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: ROR by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: ROR by 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(3)); // rotate right 31 = rotate left 1
}

test "step: ROR with high rs2 (shift amount masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 0x21); // 33 & 0x1F = 1
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: RORI basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: RORI by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: RORI shamt=31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 31));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(3)); // rotate right 31 = rotate left 1
}

// --- ORC_B execute tests ---

test "step: ORC_B mixed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00010200);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00FFFF00), cpu.readReg(3));
}

test "step: ORC_B all zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: ORC_B all nonzero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x01010101);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: ORC_B single byte in each position" {
    var cpu = Cpu.init();
    // Byte 0 only
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x000000FF), cpu.readReg(3));

    // Byte 1 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00000100);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000FF00), cpu.readReg(3));

    // Byte 2 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00010000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), cpu.readReg(3));

    // Byte 3 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x01000000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF000000), cpu.readReg(3));
}

// --- REV8 execute tests ---

test "step: REV8 basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x01020304);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x04030201), cpu.readReg(3));
}

test "step: REV8 palindrome" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xAAAAAAAA);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAAAAAA), cpu.readReg(3));
}

test "step: REV8 zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: REV8 all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}
