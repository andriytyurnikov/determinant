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

// --- ANDN/ORN/XNOR execute tests ---

test "step: ANDN basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b111, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF000F000), cpu.readReg(3));
}

test "step: ORN basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b110, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFF0FFF0), cpu.readReg(3));
}

test "step: XNOR basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b100, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0FF00FF0), cpu.readReg(3));
}

test "step: ANDN identity (mask=0)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b111, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3)); // x & ~0 = x
}

test "step: ORN identity (mask=all-ones)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b110, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3)); // x | ~0xFFFFFFFF = x | 0 = x
}

test "step: XNOR self" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0xDEADBEEF);
    loadInst(&cpu, encodeR(0b100, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // ~(x ^ x) = ~0
}

// --- MIN/MAX/MINU/MAXU execute tests ---

test "step: MAX signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -5))));
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: MAXU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b111, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: MIN signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -5))));
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -5))), cpu.readReg(3));
}

test "step: MINU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b101, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: MIN SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: MAX SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3));
}

test "step: MINU with zero operand" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: MAXU equal values" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b111, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: MIN equal operands" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: MAX equal operands" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}
