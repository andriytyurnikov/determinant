//! Register aliasing: rd equal to rs1 and/or rs2. Source registers are read before the
//! instruction executes (pipeline step 3), so the address and operands are the old
//! values and rd receives the result.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("../instructions/test_helpers.zig");

test "aliasing: LW x1, 0(x1) loads through the old x1" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 0xCAFE);
    cpu.writeReg(1, 0x100);
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 1, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xCAFE), cpu.readReg(1));
}

test "aliasing: AMOADD.W x1, x1, (x1) uses the old x1 as address and addend" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 5);
    cpu.writeReg(1, 0x100);
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 1, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1)); // old memory value
    try std.testing.expectEqual(@as(u32, 0x105), h.readWordAt(&cpu, 0x100)); // 5 + 0x100
}

test "aliasing: AMOSWAP.W x2, x2, (x1) swaps a register with memory" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 0x1111);
    cpu.writeReg(1, 0x100);
    cpu.writeReg(2, 0x2222);
    h.loadInst(&cpu, h.encodeAtomic(0b00001, 2, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1111), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0x2222), h.readWordAt(&cpu, 0x100));
}

test "aliasing: LR.W x1, (x1) reserves the old x1" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 0x200);
    cpu.writeReg(1, 0x100);
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 1, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x200), cpu.readReg(1));
    try std.testing.expectEqual(@as(?u32, 0x100), cpu.reservation);
}

test "aliasing: SC.W x1, x1, (x1) stores the old x1 and then writes the result code" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x100);
    cpu.reservation = 0x100;
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 1, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x100), h.readWordAt(&cpu, 0x100));
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(1)); // success
}

test "aliasing: CSRRW x1, mscratch, x1 swaps a register with the CSR" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xAAAA;
    cpu.writeReg(1, 0xBBBB);
    h.loadInst(&cpu, h.encodeCsr(0b001, 1, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 0xBBBB), cpu.csrs.mscratch);
}

test "aliasing: JALR x1, 8(x1) jumps through the old x1 and links" {
    var cpu = Cpu.init();
    cpu.pc = 0x20;
    cpu.writeReg(1, 0x100);
    h.loadInst(&cpu, h.encodeI(0b1100111, 0b000, 1, 1, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x108), cpu.pc);
    try std.testing.expectEqual(@as(u32, 0x24), cpu.readReg(1));
}
