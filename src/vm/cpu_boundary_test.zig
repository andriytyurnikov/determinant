const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = cpu_mod.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

// --- CSR cycle_count pipeline invariant test ---

test "step: CSR cycle_count sees pre-step value" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // CSRRS x3, 0xC00, x0 — read cycle counter into x3
    h5.loadInst(&cpu, h5.encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    // cycle_count was 0 before step, so x3 should be 0 (not 1)
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

// --- Extension dispatch through CPU tests ---

test "step: MUL dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 7);
    cpu.writeReg(2, 6);
    // MUL x3, x1, x2: opcode=0b0110011, funct3=000, funct7=0b0000001
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: SH1ADD dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    // SH1ADD x3, x1, x2: opcode=0b0110011, funct3=010, funct7=0b0010000
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3));
}

test "step: CLZ dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0F000000);
    // CLZ x2, x1: opcode=0b0010011, funct3=001, imm12=0b0110000_00000
    const imm12: u12 = (@as(u12, 0b0110000) << 5) | 0;
    h5.loadInst(&cpu, h5.encodeI(0b0010011, 0b001, 2, 1, imm12));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2));
}

test "step: BSET dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 5);
    // BSET x3, x1, x2: opcode=0b0110011, funct3=001, funct7=0b0010100
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}

// --- Boundary-value tests ---

test "step: ADD overflow wraps" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: SUB underflow wraps" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 1);
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: LB sign-extension bit 7" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LB x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(2));
}

test "step: LH sign-extension bit 15" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b001, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(2));
}

test "step: LBU zero-extension" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LBU x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b100, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000080), cpu.readReg(2));
}

test "step: BLT SIGNED_MIN vs positive" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8
    h5.loadInst(&cpu, h5.encodeB(0b100, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: BGE SIGNED_MAX vs SIGNED_MIN" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x7FFFFFFF); // SIGNED_MAX
    cpu.writeReg(2, 0x80000000); // SIGNED_MIN
    // BGE x1, x2, +8
    h5.loadInst(&cpu, h5.encodeB(0b101, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: JALR clears bit[0]" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x1001);
    // JALR x2, 0(x1) → target = 0x1001 & 0xFFFFFFFE = 0x1000
    h5.loadInst(&cpu, h5.encodeI(0b1100111, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1000), cpu.pc);
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // link = old_pc + 4
}

test "step: SLL shift masking rs2=32" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    cpu.writeReg(2, 32); // masked to 0
    // SLL x3, x1, x2
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b001, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(3)); // shift by 0
}
