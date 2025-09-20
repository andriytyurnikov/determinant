const std = @import("std");
const instructions = @import("../../instructions.zig");
pub const Opcode = instructions.Opcode;
pub const lut = @import("../lut.zig");
pub const decode = lut.decodeOpcode;

// --- Instruction encoding helpers ---

pub fn encodeR(comptime opcode_bits: u7, f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

pub fn encodeRBase(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
}

pub fn encodeIAlu(f3: u3, imm12: u12) u32 {
    return @as(u32, 0b0010011) |
        (@as(u32, f3) << 12) |
        (@as(u32, imm12) << 20);
}

pub fn encodeI(comptime opcode_bits: u7, f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, imm12) << 20);
}

pub fn encodeLoad(f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b0000011, f3, rd_v, rs1_v, imm12);
}

pub fn encodeStore(f3: u3, rs1_v: u5, rs2_v: u5, imm: u12) u32 {
    const imm_4_0: u5 = @truncate(imm);
    const imm_11_5: u7 = @truncate(imm >> 5);
    return @as(u32, 0b0100011) |
        (@as(u32, imm_4_0) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, imm_11_5) << 25);
}

pub fn encodeBranch(f3: u3, rs1_v: u5, rs2_v: u5) u32 {
    // Encode a minimal branch (imm=0 is fine for opcode identification)
    return @as(u32, 0b1100011) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20);
}

pub fn encodeBranchFull(f3: u3, rs1_v: u5, rs2_v: u5, imm: i13) u32 {
    const uimm: u13 = @bitCast(imm);
    const imm_12: u32 = (@as(u32, uimm) >> 12) & 1;
    const imm_11: u32 = (@as(u32, uimm) >> 11) & 1;
    const imm_10_5: u32 = (@as(u32, uimm) >> 5) & 0x3F;
    const imm_4_1: u32 = (@as(u32, uimm) >> 1) & 0xF;
    return @as(u32, 0b1100011) |
        (imm_11 << 7) |
        (imm_4_1 << 8) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (imm_10_5 << 25) |
        (imm_12 << 31);
}

pub fn encodeU(comptime opcode_bits: u7, rd_v: u5, imm20: u20) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, imm20) << 12);
}

pub fn encodeJ(rd_v: u5) u32 {
    // JAL with imm=0 (fine for opcode identification)
    return @as(u32, 0b1101111) |
        (@as(u32, rd_v) << 7);
}

pub fn encodeJFull(rd_v: u5, imm: i21) u32 {
    const uimm: u21 = @bitCast(imm);
    const imm_20: u32 = (@as(u32, uimm) >> 20) & 1;
    const imm_19_12: u32 = (@as(u32, uimm) >> 12) & 0xFF;
    const imm_11: u32 = (@as(u32, uimm) >> 11) & 1;
    const imm_10_1: u32 = (@as(u32, uimm) >> 1) & 0x3FF;
    return @as(u32, 0b1101111) |
        (@as(u32, rd_v) << 7) |
        (imm_19_12 << 12) |
        (imm_11 << 20) |
        (imm_10_1 << 21) |
        (imm_20 << 31);
}

pub fn encodeJalr(rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b1100111, 0b000, rd_v, rs1_v, imm12);
}

pub fn encodeFence() u32 {
    return @as(u32, 0b0001111);
}

pub fn encodeAtomic(f5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    // funct3=010 (word), aq=0, rl=0
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f5) << 27);
}

pub fn encodeAtomicFull(f5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5, aq: u1, rl: u1) u32 {
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, rl) << 25) |
        (@as(u32, aq) << 26) |
        (@as(u32, f5) << 27);
}

pub fn encodeSystem(f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b1110011, f3, rd_v, rs1_v, imm12);
}

// --- Assertion helpers ---

pub fn expectOp(expected: Opcode, actual: ?Opcode) !void {
    try std.testing.expect(actual != null);
    try std.testing.expectEqual(expected, actual.?);
}

pub fn expectNull(actual: ?Opcode) !void {
    try std.testing.expect(actual == null);
}
