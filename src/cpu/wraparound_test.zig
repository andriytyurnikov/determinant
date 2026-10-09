//! Address arithmetic wraps modulo 2^32 (SEMANTICS.md, "Execution model"): rs1 + imm,
//! branch and jump targets and AUIPC all wrap; a wrapped address that lands inside
//! memory is valid.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const StepResult = cpu_mod.StepResult;
const h = @import("../instructions/test_helpers.zig");

test "wrap-around: LW 4(x1) with x1 = 0xFFFFFFFC loads address 0" {
    var cpu = Cpu.init();
    cpu.pc = 0x40;
    h.storeWordAt(&cpu, 0, 0x12345678);
    cpu.writeReg(1, 0xFFFF_FFFC);
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 2, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x12345678), cpu.readReg(2));
}

test "wrap-around: SW 16(x1) with x1 = 0xFFFFFFF8 stores to address 8" {
    var cpu = Cpu.init();
    cpu.pc = 0x40;
    cpu.writeReg(1, 0xFFFF_FFF8);
    cpu.writeReg(2, 0xABCD);
    h.loadInst(&cpu, h.encodeS(0b010, 1, 2, 16));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xABCD), h.readWordAt(&cpu, 8));
}

test "wrap-around: LW -4(x1) with x1 = 0 is out of bounds" {
    var cpu = Cpu.init();
    cpu.pc = 0x40;
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 2, 1, 0xFFC));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
}

test "wrap-around: JALR target wraps" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFF_FFF0);
    h.loadInst(&cpu, h.encodeI(0b1100111, 0b000, 0, 1, 0x14));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "wrap-around: a backward branch from 0 targets 0xFFFFFFFC, and the next fetch faults" {
    var cpu = Cpu.init();
    h.loadInst(&cpu, h.encodeB(0b000, 0, 0, -4)); // BEQ x0, x0, -4
    try std.testing.expectEqual(StepResult.@"continue", try cpu.step()); // the branch retires
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFC), cpu.pc);
    try std.testing.expectError(error.PCOutOfBounds, cpu.step());
}

test "wrap-around: AUIPC adds modulo 2^32" {
    var cpu = Cpu.init();
    cpu.pc = 0x10;
    h.loadInst(&cpu, h.encodeU(0b0010111, 1, 0xFFFFF)); // AUIPC x1, 0xFFFFF
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF_F010), cpu.readReg(1));
}
