const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
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

test "step: BCLR bit 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b001, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3));
}

test "step: BINV bit 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b001, 0b0110100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: BSET bit 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: BEXT at bit 0" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFE); // bit 0 = 0
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: BINVI at bit 31 (immediate)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110100, 3, 1, 31));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: BCLR with rs2 >= 32 (masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 32); // masked to bit 0
    loadInst(&cpu, encodeR(0b001, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(3)); // bit 0 cleared
}

test "step: BEXT with rs2 >= 32 (masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001); // bit 0 set
    cpu.writeReg(2, 32); // masked to bit 0
    loadInst(&cpu, encodeR(0b101, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // extracts bit 0
}

test "step: BINV with rs2 >= 32 (masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 32); // masked to bit 0
    loadInst(&cpu, encodeR(0b001, 0b0110100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000001), cpu.readReg(3)); // bit 0 inverted
}

test "step: BSET with rs2 >= 32 (masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 33); // masked to bit 1
    loadInst(&cpu, encodeR(0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(3)); // bit 1 set
}
