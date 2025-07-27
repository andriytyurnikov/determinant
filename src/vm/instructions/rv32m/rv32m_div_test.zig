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

// --- DIV execute tests ---

test "step: DIV basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: DIV signed negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -20))));
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -3))), cpu.readReg(3));
}

test "step: DIV by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: DIV overflow INT_MIN / -1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: DIV negative/negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -20))));
    cpu.writeReg(2, @as(u32, @bitCast(@as(i32, -6))));
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

// --- DIVU execute tests ---

test "step: DIVU basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: DIVU by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: DIVU large unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 2);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3));
}

test "step: DIVU smaller divided by larger" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3)); // 0x80000000 / 0xFFFFFFFF = 0
}

// --- REM execute tests ---

test "step: REM basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(3));
}

test "step: REM signed negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -20))));
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -2))), cpu.readReg(3));
}

test "step: REM by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: REM overflow INT_MIN / -1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: REM positive/negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, @as(u32, @bitCast(@as(i32, -6))));
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(3));
}

// --- REMU execute tests ---

test "step: REMU basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(3));
}

test "step: REMU by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: REMU large unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 2);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

test "step: REMU smaller mod larger" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3)); // 0x80000000 % 0xFFFFFFFF = 0x80000000
}
