const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

// --- Boundary-value tests ---

test "step: ADD overflow wraps" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: SUB underflow wraps" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 1);
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b000, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: LB sign-extension bit 7" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LB x2, 0(x1)
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(2));
}

test "step: LH sign-extension bit 15" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1)
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b001, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(2));
}

test "step: LBU zero-extension" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LBU x2, 0(x1)
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b100, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000080), cpu.readReg(2));
}

test "step: BLT SIGNED_MIN vs positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8
    h.loadInst(&cpu, h.encodeB(0b100, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: BGE SIGNED_MAX vs SIGNED_MIN" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x7FFFFFFF); // SIGNED_MAX
    cpu.writeReg(2, 0x80000000); // SIGNED_MIN
    // BGE x1, x2, +8
    h.loadInst(&cpu, h.encodeB(0b101, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: JALR clears bit[0]" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x1001);
    // JALR x2, 0(x1) → target = 0x1001 & 0xFFFFFFFE = 0x1000
    h.loadInst(&cpu, h.encodeI(0b1100111, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1000), cpu.pc);
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // link = old_pc + 4
}

test "step: SLL shift masking rs2=32" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    cpu.writeReg(2, 32); // masked to 0
    // SLL x3, x1, x2
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b001, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(3)); // shift by 0
}
