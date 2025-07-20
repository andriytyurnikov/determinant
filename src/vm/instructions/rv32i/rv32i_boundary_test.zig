const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const encodeR = h.encodeR;
const encodeI = h.encodeI;
const encodeB = h.encodeB;
const loadInst = h.loadInst;

// === Boundary value tests (wrapping arithmetic, shift masking, sign extension) ===

test "step: ADDI wrapping 0xFFFFFFFF + 1 = 0" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    // ADDI x2, x1, 1
    loadInst(&cpu, encodeI(0b0010011, 0b000, 2, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(2));
}

test "step: ADDI wrapping 0x7FFFFFFF + 1 = 0x80000000" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x7FFFFFFF);
    // ADDI x2, x1, 1
    loadInst(&cpu, encodeI(0b0010011, 0b000, 2, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(2));
}

test "step: ADD wrapping 0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFE" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    // ADD x3, x1, x2
    loadInst(&cpu, encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(3));
}

test "step: SLL shift masking rs2 >= 32" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 32); // masked to 0
    // SLL x3, x1, x2
    loadInst(&cpu, encodeR(0b0110011, 0b001, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3)); // shift by 0
}

test "step: SRL shift masking rs2 = 33" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 33); // masked to 1
    // SRL x3, x1, x2
    loadInst(&cpu, encodeR(0b0110011, 0b101, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x40000000), cpu.readReg(3)); // shift right by 1
}

test "step: SRA shift masking rs2 = 33" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 33); // masked to 1
    // SRA x3, x1, x2
    loadInst(&cpu, encodeR(0b0110011, 0b101, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3)); // arithmetic shift right by 1
}

test "step: SLTIU with sign-extended immediate (unsigned comparison)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFE);
    // SLTIU x2, x1, -1 (imm=0xFFF → sign-extended to 0xFFFFFFFF, interpreted as unsigned)
    loadInst(&cpu, encodeI(0b0010011, 0b011, 2, 1, 0xFFF));
    _ = try cpu.step();
    // 0xFFFFFFFE < 0xFFFFFFFF unsigned → 1
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: SLTIU small value vs large unsigned immediate" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    // SLTIU x2, x1, -1 (imm=0xFFF → 0xFFFFFFFF unsigned)
    loadInst(&cpu, encodeI(0b0010011, 0b011, 2, 1, 0xFFF));
    _ = try cpu.step();
    // 5 < 0xFFFFFFFF unsigned → 1
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: BLT SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    // BLT x1, x2, +8
    loadInst(&cpu, encodeB(0b100, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // taken
}

test "step: BGE SIGNED_MIN vs SIGNED_MAX not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    // BGE x1, x2, +8
    loadInst(&cpu, encodeB(0b101, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc); // not taken
}

test "step: BGE equal values" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0x80000000);
    // BGE x1, x2, +8
    loadInst(&cpu, encodeB(0b101, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // taken (equal)
}

test "step: LB sign-extension boundary 0x7F positive" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x7F; // max positive i8
    cpu.writeReg(1, 200);
    // LB x2, 0(x1)
    loadInst(&cpu, encodeI(0b0000011, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000007F), cpu.readReg(2)); // positive, no sign extension
}

test "step: LH sign-extension boundary 0x7FFF positive" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x7FFF, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1)
    loadInst(&cpu, encodeI(0b0000011, 0b001, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00007FFF), cpu.readReg(2)); // positive, no sign extension
}

test "step: BEQ self-loop (offset=0)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    // BEQ x1, x2, +0 → branch taken, PC unchanged (stays at 0)
    loadInst(&cpu, encodeB(0b000, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "step: JALR wrapping target address" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    // JALR x2, 4(x1) → target = (0xFFFFFFFF +% 4) & 0xFFFFFFFE = 3 & 0xFFFFFFFE = 2
    loadInst(&cpu, encodeI(0b1100111, 0b000, 2, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // link = old_pc + 4
}

test "step: LW with negative offset" {
    var cpu = Cpu.init();
    // Store a known value at address 96
    std.mem.writeInt(u32, cpu.memory[96..][0..4], 0xDEADBEEF, .little);
    cpu.writeReg(1, 100);
    // LW x2, -4(x1) → load from address 96
    // -4 as u12 = 0xFFC
    loadInst(&cpu, encodeI(0b0000011, 0b010, 2, 1, 0xFFC));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(2));
}
