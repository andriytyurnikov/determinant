const std = @import("std");
const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeRBase = t.encodeRBase;
const encodeIAlu = t.encodeIAlu;
const encodeI = t.encodeI;
const encodeAtomic = t.encodeAtomic;
const encodeSystem = t.encodeSystem;
const encodeFence = t.encodeFence;

// --- Atomic ---

test "Atomic: all 11 instructions" {
    const cases = [_]struct { u5, Opcode }{
        .{ 0b00010, .{ .a = .LR_W } },
        .{ 0b00011, .{ .a = .SC_W } },
        .{ 0b00001, .{ .a = .AMOSWAP_W } },
        .{ 0b00000, .{ .a = .AMOADD_W } },
        .{ 0b00100, .{ .a = .AMOXOR_W } },
        .{ 0b01100, .{ .a = .AMOAND_W } },
        .{ 0b01000, .{ .a = .AMOOR_W } },
        .{ 0b10000, .{ .a = .AMOMIN_W } },
        .{ 0b10100, .{ .a = .AMOMAX_W } },
        .{ 0b11000, .{ .a = .AMOMINU_W } },
        .{ 0b11100, .{ .a = .AMOMAXU_W } },
    };
    for (cases) |c| {
        try expectOp(c[1], decode(encodeAtomic(c[0], 1, 2, 3)));
    }
}

test "Atomic: invalid funct5 → null" {
    try expectNull(decode(encodeAtomic(0b11111, 1, 2, 3)));
    try expectNull(decode(encodeAtomic(0b01010, 1, 2, 3)));
}

test "Atomic: funct3≠010 → null" {
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 0b000) << 12) |
        (@as(u32, 1) << 15) |
        (@as(u32, 2) << 20);
    try expectNull(decode(raw));
}

// --- System ---

test "System: ECALL and EBREAK" {
    try expectOp(.{ .i = .ECALL }, decode(encodeSystem(0b000, 0, 0, 0x000)));
    try expectOp(.{ .i = .EBREAK }, decode(encodeSystem(0b000, 0, 0, 0x001)));
}

test "System: invalid funct12 with funct3=0 → null" {
    try expectNull(decode(encodeSystem(0b000, 0, 0, 0x002)));
    try expectNull(decode(encodeSystem(0b000, 0, 0, 0xFFF)));
}

test "System: CSR all 6 instructions" {
    try expectOp(.{ .csr = .CSRRW }, decode(encodeSystem(0b001, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRS }, decode(encodeSystem(0b010, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRC }, decode(encodeSystem(0b011, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRWI }, decode(encodeSystem(0b101, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRSI }, decode(encodeSystem(0b110, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRCI }, decode(encodeSystem(0b111, 1, 2, 0x300)));
}

test "System: funct3=100 → null" {
    try expectNull(decode(encodeSystem(0b100, 1, 2, 0x300)));
}

// --- FENCE ---

test "FENCE: funct3=0 → FENCE" {
    try expectOp(.{ .i = .FENCE }, decode(encodeFence()));
}

test "FENCE.I: funct3=001 → FENCE_I" {
    try expectOp(.{ .i = .FENCE_I }, decode(encodeI(0b0001111, 0b001, 0, 0, 0)));
}

test "FENCE: funct3≥2 → null" {
    try expectNull(decode(encodeI(0b0001111, 0b010, 0, 0, 0)));
    try expectNull(decode(encodeI(0b0001111, 0b111, 0, 0, 0)));
}

// --- Misc ---

test "unknown opcode[6:0] → null" {
    try expectNull(decode(0b1111111));
    try expectNull(decode(0b0000000));
    try expectNull(decode(0b1010101));
}

test "tables are comptime-evaluable" {
    comptime {
        std.debug.assert(decode(encodeRBase(0b000, 0b0000000, 1, 2, 3)) != null);
        std.debug.assert(decode(encodeIAlu(0b000, 100)) != null);
        std.debug.assert(decode(encodeIAlu(0b101, 0b0100000_00011)) != null);
        std.debug.assert(decode(0b1111111) == null);
    }
}
