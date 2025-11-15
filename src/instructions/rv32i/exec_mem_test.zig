const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests: load/store ===

test "step: LW / SW" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100); // base address
    cpu.writeReg(2, 0xCAFEBABE);
    // SW x2, 0(x1) = 0x0020A023
    loadInst(&cpu, 0x0020A023);
    _ = try cpu.step();
    // LW x3, 0(x1) = 0x0000A183
    loadInst(&cpu, 0x0000A183);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), cpu.readReg(3));
}

test "step: LB sign-extends" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80; // -128 as i8
    cpu.writeReg(1, 200);
    // LB x2, 0(x1) = 0x00008103
    loadInst(&cpu, 0x00008103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(2));
}

test "step: LBU zero-extends" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LBU x2, 0(x1) = 0x0000C103
    loadInst(&cpu, 0x0000C103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80), cpu.readReg(2));
}

test "step: LH sign-extends" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1) = 0x00009103
    loadInst(&cpu, 0x00009103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(2));
}

test "step: LHU zero-extends" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LHU x2, 0(x1) = 0x0000D103
    loadInst(&cpu, 0x0000D103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x8000), cpu.readReg(2));
}

test "step: SB stores low byte" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 300);
    cpu.writeReg(2, 0xDEADBE42);
    // SB x2, 0(x1) = 0x00208023
    loadInst(&cpu, 0x00208023);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u8, 0x42), cpu.memory[300]);
}

test "step: SH stores low halfword" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 300);
    cpu.writeReg(2, 0xDEAD1234);
    // SH x2, 0(x1) = 0x00209023
    loadInst(&cpu, 0x00209023);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u16, 0x1234), std.mem.readInt(u16, cpu.memory[300..][0..2], .little));
}

test "step: SW with positive offset" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100); // base address
    cpu.writeReg(2, 0xCAFEBABE); // value to store
    // SW x2, 8(x1) → store at address 108
    loadInst(&cpu, h.encodeS(0b010, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), h.readWordAt(&cpu, 108));
}
