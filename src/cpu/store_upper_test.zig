const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

// --- CPU-level store and upper-immediate tests ---

test "step: SB stores byte" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 200); // base address
    cpu.writeReg(2, 0xDEADBEAB); // only low byte 0xAB stored
    // SB x2, 0(x1): funct3=000
    h.loadInst(&cpu, h.encodeS(0b000, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u8, 0xAB), cpu.memory[200]);
    // Adjacent bytes untouched
    try std.testing.expectEqual(@as(u8, 0), cpu.memory[201]);
}

test "step: SH stores halfword" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 200); // base address (aligned)
    cpu.writeReg(2, 0xDEAD1234); // only low halfword 0x1234 stored
    // SH x2, 0(x1): funct3=001
    h.loadInst(&cpu, h.encodeS(0b001, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u16, 0x1234), std.mem.readInt(u16, cpu.memory[200..][0..2], .little));
    // Adjacent bytes untouched
    try std.testing.expectEqual(@as(u8, 0), cpu.memory[202]);
}

test "step: LUI loads upper immediate" {
    var cpu = Cpu.init();
    // LUI x3, 0xABCDE → x3 = 0xABCDE000
    h.loadInst(&cpu, h.encodeU(0b0110111, 3, 0xABCDE));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xABCDE000), cpu.readReg(3));
}

test "step: AUIPC at non-zero PC" {
    var cpu = Cpu.init();
    cpu.pc = 0x100;
    // AUIPC x3, 0x00002 → x3 = PC + (0x00002 << 12) = 0x100 + 0x2000 = 0x2100
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], h.encodeU(0b0010111, 3, 0x00002), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x2100), cpu.readReg(3));
}
