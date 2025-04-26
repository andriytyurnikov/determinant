const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;

pub fn loadInst(cpu: *Cpu, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[cpu.pc..][0..4], word, .little);
}

pub fn storeWordAt(cpu: *Cpu, addr: u32, val: u32) void {
    const a: usize = addr;
    std.mem.writeInt(u32, cpu.memory[a..][0..4], val, .little);
}

pub fn readWordAt(cpu: *const Cpu, addr: u32) u32 {
    const a: usize = addr;
    return std.mem.readInt(u32, cpu.memory[a..][0..4], .little);
}

pub fn storeHalfAt(cpu: *Cpu, addr: u32, val: u16) void {
    const a: usize = addr;
    std.mem.writeInt(u16, cpu.memory[a..][0..2], val, .little);
}

// --- Instruction encoding helpers (for tests) ---

pub fn encodeR(op: u7, f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

pub fn encodeI(op: u7, f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, imm12) << 20);
}

pub fn encodeS(f3: u3, rs1_v: u5, rs2_v: u5, imm12: u12) u32 {
    const imm: u32 = @intCast(imm12);
    const imm_4_0: u32 = imm & 0x1F;
    const imm_11_5: u32 = (imm >> 5) & 0x7F;
    return 0b0100011 |
        (imm_4_0 << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (imm_11_5 << 25);
}

pub fn encodeB(f3: u3, rs1_v: u5, rs2_v: u5, imm_val: i13) u32 {
    const imm: u13 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_12: u32 = (bits >> 12) & 1;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_10_5: u32 = (bits >> 5) & 0x3F;
    const bits_4_1: u32 = (bits >> 1) & 0xF;
    return 0b1100011 |
        (bit_11 << 7) |
        (bits_4_1 << 8) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (bits_10_5 << 25) |
        (bit_12 << 31);
}

pub fn encodeU(op: u7, rd_v: u5, imm20: u20) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, imm20) << 12);
}

pub fn encodeJ(rd_v: u5, imm_val: i21) u32 {
    const imm: u21 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_20: u32 = (bits >> 20) & 1;
    const bits_10_1: u32 = (bits >> 1) & 0x3FF;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_19_12: u32 = (bits >> 12) & 0xFF;
    return 0b1101111 |
        (@as(u32, rd_v) << 7) |
        (bits_19_12 << 12) |
        (bit_11 << 20) |
        (bits_10_1 << 21) |
        (bit_20 << 31);
}

pub fn encodeAtomic(funct5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    const f7: u7 = @as(u7, funct5) << 2; // aq=0, rl=0
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

pub fn encodeCsr(f3: u3, rd_v: u5, rs1_v: u5, csr_addr: u12) u32 {
    return @as(u32, 0b1110011) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, csr_addr) << 20);
}
