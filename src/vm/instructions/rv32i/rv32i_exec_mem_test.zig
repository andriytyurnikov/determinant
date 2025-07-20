const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests: load/store/branch/jump/system ===

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

test "step: BEQ taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BEQ not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: BNE taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BNE x1, x2, +8 = 0x00209463
    loadInst(&cpu, 0x00209463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLT signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF); // -1
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8 = 0x0020C463
    loadInst(&cpu, 0x0020C463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGE signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF); // -1
    // BGE x1, x2, +8 = 0x0020D463
    loadInst(&cpu, 0x0020D463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLTU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF);
    // BLTU x1, x2, +8 = 0x0020E463
    loadInst(&cpu, 0x0020E463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGEU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // BGEU x1, x2, +8 = 0x0020F463
    loadInst(&cpu, 0x0020F463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: LUI" {
    var cpu = Cpu.init();
    // LUI x1, 0x12345 = 0x123450B7
    loadInst(&cpu, 0x123450B7);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x12345000), cpu.readReg(1));
}

test "step: AUIPC" {
    var cpu = Cpu.init();
    cpu.pc = 0x1000;
    // AUIPC x1, 0x2 = 0x00002097
    std.mem.writeInt(u32, cpu.memory[0x1000..][0..4], 0x00002097, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1000 + 0x2000), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 0x1004), cpu.pc);
}

test "step: JAL" {
    var cpu = Cpu.init();
    cpu.pc = 0x100;
    const jal_word: u32 = (0b0000000100 << 21) | (0b00001 << 7) | 0b1101111;
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], jal_word, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x104), cpu.readReg(1)); // return address
    try std.testing.expectEqual(@as(u32, 0x108), cpu.pc); // jumped to pc+8
}

test "step: JALR clears LSB" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x103); // odd address
    const jalr_word: u32 = (0b00001 << 15) | (0b00010 << 7) | 0b1100111;
    loadInst(&cpu, jalr_word);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // return address = pc + 4
    try std.testing.expectEqual(@as(u32, 0x102), cpu.pc); // (0x103 + 0) & ~1
}

test "step: JALR rd == rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x200);
    const jalr_word: u32 = (4 << 20) | (0b00001 << 15) | (0b00001 << 7) | 0b1100111;
    loadInst(&cpu, jalr_word);
    _ = try cpu.step();
    // rd should get return addr (pc+4 = 4), NOT the computed target
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(1));
    // pc = (0x200 + 4) & ~1 = 0x204
    try std.testing.expectEqual(@as(u32, 0x204), cpu.pc);
}

test "step: ECALL" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00000073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: EBREAK" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00100073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Ebreak, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: FENCE is no-op" {
    var cpu = Cpu.init();
    // FENCE iorw, iorw = 0x0FF0000F
    loadInst(&cpu, 0x0FF0000F);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}
