const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

// === Execute tests: upper immediates and jumps ===

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

test "step: JAL backward" {
    var cpu = Cpu.init();
    cpu.pc = 0x100;
    // JAL x1, -8 = 0xFF9FF0EF
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], 0xFF9FF0EF, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x104), cpu.readReg(1)); // link address
    try std.testing.expectEqual(@as(u32, 0x0F8), cpu.pc); // 0x100 - 8
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
