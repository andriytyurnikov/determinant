const std = @import("std");
const bf = @import("bitfields.zig");

// ---- Register / function-field extractors ----

test "combined R-type word: distinct value in every field" {
    // opcode7=83  rd=21  funct3=6  rs1=12  rs2=25  funct7=42
    const raw: u32 = (42 << 25) | (25 << 20) | (12 << 15) | (6 << 12) | (21 << 7) | 83;

    try std.testing.expectEqual(@as(u7, 83), bf.opcode7(raw));
    try std.testing.expectEqual(@as(u5, 21), bf.rd(raw));
    try std.testing.expectEqual(@as(u3, 6), bf.funct3(raw));
    try std.testing.expectEqual(@as(u5, 12), bf.rs1(raw));
    try std.testing.expectEqual(@as(u5, 25), bf.rs2(raw));
    try std.testing.expectEqual(@as(u7, 42), bf.funct7(raw));
    try std.testing.expectEqual(@as(u5, 10), bf.funct5(raw)); // upper 5 of funct7
    try std.testing.expectEqual(@as(u12, 1369), bf.funct12(raw)); // funct7 ++ rs2
}

test "all-zeros word: every field extracts to zero" {
    const raw: u32 = 0x00000000;

    try std.testing.expectEqual(@as(u7, 0), bf.opcode7(raw));
    try std.testing.expectEqual(@as(u5, 0), bf.rd(raw));
    try std.testing.expectEqual(@as(u3, 0), bf.funct3(raw));
    try std.testing.expectEqual(@as(u5, 0), bf.rs1(raw));
    try std.testing.expectEqual(@as(u5, 0), bf.rs2(raw));
    try std.testing.expectEqual(@as(u7, 0), bf.funct7(raw));
    try std.testing.expectEqual(@as(u5, 0), bf.funct5(raw));
    try std.testing.expectEqual(@as(u12, 0), bf.funct12(raw));
}

test "all-ones word: every field extracts to its maximum" {
    const raw: u32 = 0xFFFFFFFF;

    try std.testing.expectEqual(@as(u7, 127), bf.opcode7(raw));
    try std.testing.expectEqual(@as(u5, 31), bf.rd(raw));
    try std.testing.expectEqual(@as(u3, 7), bf.funct3(raw));
    try std.testing.expectEqual(@as(u5, 31), bf.rs1(raw));
    try std.testing.expectEqual(@as(u5, 31), bf.rs2(raw));
    try std.testing.expectEqual(@as(u7, 127), bf.funct7(raw));
    try std.testing.expectEqual(@as(u5, 31), bf.funct5(raw));
    try std.testing.expectEqual(@as(u12, 4095), bf.funct12(raw));
}

// ---- immI: bits [31:20], sign-extended ----

test "immI: positive value" {
    // bits [31:20] = 0x345 = 837
    const raw: u32 = 0x345 << 20;
    try std.testing.expectEqual(@as(i32, 837), bf.immI(raw));
}

test "immI: negative value (sign bit set)" {
    // bits [31:20] = 0x800 → sign-extends to -2048
    const raw: u32 = 0x800 << 20;
    try std.testing.expectEqual(@as(i32, -2048), bf.immI(raw));
}

test "immI: max positive" {
    const raw: u32 = 0x7FF << 20;
    try std.testing.expectEqual(@as(i32, 2047), bf.immI(raw));
}

test "immI: zero" {
    try std.testing.expectEqual(@as(i32, 0), bf.immI(0));
}

test "immI: lower bits do not leak" {
    // bits [19:0] all ones — immI must ignore them
    const raw: u32 = (0x345 << 20) | 0xFFFFF;
    try std.testing.expectEqual(@as(i32, 837), bf.immI(raw));
}

// ---- immS: bits [31:25|11:7], sign-extended ----

test "immS: positive value" {
    // imm = 100 = 0b000001100100
    // imm[11:5] = 3, imm[4:0] = 4
    const raw: u32 = (3 << 25) | (4 << 7);
    try std.testing.expectEqual(@as(i32, 100), bf.immS(raw));
}

test "immS: negative value" {
    // imm = -100 → 12-bit = 0xF9C
    // imm[11:5] = 0b1111100 = 124, imm[4:0] = 0b11100 = 28
    const raw: u32 = (124 << 25) | (28 << 7);
    try std.testing.expectEqual(@as(i32, -100), bf.immS(raw));
}

test "immS: zero" {
    try std.testing.expectEqual(@as(i32, 0), bf.immS(0));
}

test "immS: other bits do not leak" {
    // Set rs1, rs2, funct3, opcode to all ones — immS must ignore them
    const raw: u32 = (3 << 25) | (4 << 7) | (0x1F << 20) | (0x1F << 15) | (0x7 << 12) | 0x7F;
    try std.testing.expectEqual(@as(i32, 100), bf.immS(raw));
}

// ---- immB: bits [31|7|30:25|11:8], sign-extended, bit[0]=0 ----

test "immB: positive value" {
    // imm[12]=0 (bit31), imm[11]=1 (bit7), imm[10:5]=42 (bits[30:25]), imm[4:1]=10 (bits[11:8])
    // Expected = (0<<12)|(1<<11)|(42<<5)|(10<<1) = 2048+1344+20 = 3412
    const raw: u32 = (0 << 31) | (42 << 25) | (10 << 8) | (1 << 7);
    try std.testing.expectEqual(@as(i32, 3412), bf.immB(raw));
}

test "immB: negative value" {
    // imm[12]=1 (bit31), imm[11]=1 (bit7), imm[10:5]=42 (bits[30:25]), imm[4:1]=10 (bits[11:8])
    // Expected = (1<<12)|(1<<11)|(42<<5)|(10<<1) = 7508 → sign-extend 13-bit → -684
    const raw: u32 = (1 << 31) | (42 << 25) | (10 << 8) | (1 << 7);
    try std.testing.expectEqual(@as(i32, -684), bf.immB(raw));
}

test "immB: zero" {
    try std.testing.expectEqual(@as(i32, 0), bf.immB(0));
}

test "immB: bit[0] is always zero" {
    // All scattered fields max → imm = 0b1_1111_1111_1110 = 8190
    // Sign-extend from 13 bits → -2 (even, confirming bit[0] = 0)
    const raw: u32 = (1 << 31) | (0x3F << 25) | (0xF << 8) | (1 << 7);
    try std.testing.expectEqual(@as(i32, -2), bf.immB(raw));
}

// ---- immU: bits [31:12] << 12 ----

test "immU: positive upper bits" {
    const raw: u32 = 0x12345678;
    try std.testing.expectEqual(@as(i32, 0x12345000), bf.immU(raw));
}

test "immU: negative upper bits" {
    const raw: u32 = 0x80001234;
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0x80001000))), bf.immU(raw));
}

test "immU: lower 12 bits masked to zero" {
    const raw: u32 = 0x00000FFF;
    try std.testing.expectEqual(@as(i32, 0), bf.immU(raw));
}

// ---- immJ: bits [31|19:12|20|30:21], sign-extended, bit[0]=0 ----

test "immJ: positive value" {
    // imm[20]=0, imm[10:1]=8 (bits[30:21]), imm[11]=0, imm[19:12]=0
    // Expected = 8<<1 = 16
    const raw: u32 = 8 << 21;
    try std.testing.expectEqual(@as(i32, 16), bf.immJ(raw));
}

test "immJ: negative value" {
    // imm = -2 → 21-bit = 0x1FFFFE
    // imm[20]=1, imm[19:12]=0xFF, imm[11]=1, imm[10:1]=0x3FF
    const raw: u32 = (1 << 31) | (0x3FF << 21) | (1 << 20) | (0xFF << 12);
    try std.testing.expectEqual(@as(i32, -2), bf.immJ(raw));
}

test "immJ: max positive" {
    // imm = 1048574 = 2^20 - 2
    // imm[20]=0, imm[19:12]=0xFF, imm[11]=1, imm[10:1]=0x3FF
    const raw: u32 = (0 << 31) | (0x3FF << 21) | (1 << 20) | (0xFF << 12);
    try std.testing.expectEqual(@as(i32, 1048574), bf.immJ(raw));
}

test "immJ: zero" {
    try std.testing.expectEqual(@as(i32, 0), bf.immJ(0));
}

test "immJ: bit[0] is always zero" {
    // Use a non-trivial pattern and verify LSB of result is 0
    const raw: u32 = (1 << 31) | (0x155 << 21) | (1 << 20) | (0xAA << 12);
    const result = bf.immJ(raw);
    try std.testing.expectEqual(@as(u1, 0), @as(u1, @truncate(@as(u32, @bitCast(result)))));
}
