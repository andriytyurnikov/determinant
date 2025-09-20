const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const encodeAtomic = h.encodeAtomic;
const loadInst = h.loadInst;
const storeWordAt = h.storeWordAt;
const readWordAt = h.readWordAt;

// --- AMO tests ---

test "step: AMOSWAP.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 42);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 99);
    loadInst(&cpu, encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 99), readWordAt(&cpu, addr)); // new value
}

test "step: AMOADD.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 10);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 32);
    loadInst(&cpu, encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 42), readWordAt(&cpu, addr));
}

test "step: AMOXOR.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b00100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xF00FF00F), readWordAt(&cpu, addr));
}

test "step: AMOAND.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b01100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0x0F000F00), readWordAt(&cpu, addr));
}

test "step: AMOOR.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b01000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xFF0FFF0F), readWordAt(&cpu, addr));
}

test "step: AMOMIN.W signed" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 3), readWordAt(&cpu, addr));
}

test "step: AMOMIN.W with negative" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    const neg5: u32 = @bitCast(@as(i32, -5));
    storeWordAt(&cpu, addr, 3);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, neg5);
    loadInst(&cpu, encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
    try std.testing.expectEqual(neg5, readWordAt(&cpu, addr)); // -5 < 3
}

test "step: AMOMAX.W signed" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 5), readWordAt(&cpu, addr));
}

test "step: AMOMAX.W with negative" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    const neg5: u32 = @bitCast(@as(i32, -5));
    storeWordAt(&cpu, addr, neg5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(neg5, cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 3), readWordAt(&cpu, addr)); // 3 > -5
}

test "step: AMOMINU.W unsigned" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFFFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeAtomic(0b11000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 5), readWordAt(&cpu, addr));
}

test "step: AMOMAXU.W unsigned" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeAtomic(0b11100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), readWordAt(&cpu, addr));
}

test "step: atomic misaligned address" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x101); // misaligned
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
}

// --- AMO boundary-value tests ---

test "step: AMOADD.W wrapping" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFFFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0), readWordAt(&cpu, addr));
}

test "step: AMOADD.W signed overflow boundary" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0x7FFFFFFF); // max positive i32
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0x80000000), readWordAt(&cpu, addr)); // wraps to min negative
}

test "step: AMOMIN.W SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0x80000000); // SIGNED_MIN
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeAtomic(0b10000, 3, 1, 2)); // AMOMIN.W
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0x80000000), readWordAt(&cpu, addr)); // min(SIGNED_MIN, SIGNED_MAX) = SIGNED_MIN
}

test "step: AMOMAX.W SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0x80000000); // SIGNED_MIN
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeAtomic(0b10100, 3, 1, 2)); // AMOMAX.W
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), readWordAt(&cpu, addr)); // max(SIGNED_MIN, SIGNED_MAX) = SIGNED_MAX
}

test "step: AMOMINU.W with zero" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFFFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeAtomic(0b11000, 3, 1, 2)); // AMOMINU.W
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0), readWordAt(&cpu, addr)); // minu(0xFFFFFFFF, 0) = 0
}

test "step: AMOMAXU.W at unsigned max boundary" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0x7FFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x80000000);
    loadInst(&cpu, encodeAtomic(0b11100, 3, 1, 2)); // AMOMAXU.W
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0x80000000), readWordAt(&cpu, addr)); // maxu(0x7FFFFFFF, 0x80000000) = 0x80000000
}

test "step: AMOSWAP.W same value (old == new)" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 42);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 42), readWordAt(&cpu, addr)); // same value written
}
