const std = @import("std");
const expectEqual = std.testing.expectEqual;
const imm = @import("imm.zig");

// ============================================================
// cReg — 3-bit compressed register field to x8-x15
// ============================================================

test "cReg maps 0-7 to x8-x15" {
    for (0..8) |i| {
        try expectEqual(@as(u5, @truncate(i)) + 8, imm.cReg(@truncate(i)));
    }
}

// ============================================================
// funct3 — extract bits [15:13]
// ============================================================

test "funct3 extracts bits [15:13]" {
    try expectEqual(@as(u3, 5), imm.funct3(0xA000));
}

// ============================================================
// ciw_nzuimm — CIW-format nzuimm for C.ADDI4SPN
// ============================================================

test "ciw_nzuimm extracts scrambled bits" {
    // 0x12C0: bit[12]=1,bit[11]=0 → nzuimm[5:4]=10 (32)
    //         bits[10:7]=0101    → nzuimm[9:6]=0101 (320)
    //         bit[6]=1           → nzuimm[2]=1 (4)
    //         bit[5]=0           → nzuimm[3]=0
    try expectEqual(@as(u32, 356), imm.ciw_nzuimm(0x12C0));
}

// ============================================================
// clsw_offset — CL/CS-format word offset for C.LW/C.SW
// ============================================================

test "clsw_offset extracts scrambled bits" {
    // 0x1820: bits[12:10]=110 → offset[5:3]=110 (48)
    //         bit[6]=0        → offset[2]=0
    //         bit[5]=1        → offset[6]=1 (64)
    try expectEqual(@as(u32, 112), imm.clsw_offset(0x1820));
}

// ============================================================
// ci_imm — CI-format signed 6-bit immediate
// ============================================================

test "ci_imm positive" {
    // 0x0054: bit[12]=0, bits[6:2]=10101=21
    try expectEqual(@as(i32, 21), imm.ci_imm(0x0054));
}

test "ci_imm negative" {
    // 0x1028: bit[12]=1, bits[6:2]=01010=10 → raw=0b101010=42 → i6=-22
    try expectEqual(@as(i32, -22), imm.ci_imm(0x1028));
}

// ============================================================
// ci_shamt — CI-format unsigned 6-bit shamt
// ============================================================

test "ci_shamt extracts unsigned value" {
    // 0x006C: bit[12]=0, bits[6:2]=11011=27
    try expectEqual(@as(u32, 27), imm.ci_shamt(0x006C));
}

// ============================================================
// ci_addi16sp_imm — C.ADDI16SP immediate
// ============================================================

test "ci_addi16sp_imm positive" {
    // 0x0074: bit[12]=0 → imm[9]=0
    //         bit[6]=1  → imm[4]=1 (16)
    //         bit[5]=1  → imm[6]=1 (64)
    //         bits[4:3]=10 → imm[8:7]=10 (256)
    //         bit[2]=1  → imm[5]=1 (32)
    try expectEqual(@as(i32, 368), imm.ci_addi16sp_imm(0x0074));
}

test "ci_addi16sp_imm negative" {
    // 0x1074: bit[12]=1 → imm[9]=1 (512), rest same as 0x0074
    // raw = 512+16+64+256+32 = 880 → i10=-144
    try expectEqual(@as(i32, -144), imm.ci_addi16sp_imm(0x1074));
}

// ============================================================
// ci_lui_imm — C.LUI immediate (upper 20 bits)
// ============================================================

test "ci_lui_imm positive" {
    // 0x000C: bit[12]=0, bits[6:2]=00011=3 → 3 << 12 = 12288
    try expectEqual(@as(i32, 12288), imm.ci_lui_imm(0x000C));
}

test "ci_lui_imm negative" {
    // 0x107C: bit[12]=1, bits[6:2]=11111=31 → raw=0b111111 → i6=-1 → -1<<12 = -4096
    try expectEqual(@as(i32, -4096), imm.ci_lui_imm(0x107C));
}

// ============================================================
// cj_offset — CJ-format offset for C.J/C.JAL
// ============================================================

test "cj_offset extracts scrambled bits" {
    // 0x2904: bit[12]=0 → offset[11]=0
    //         bit[8]=1  → offset[10]=1 (1024)
    //         bits[10:9]=00 → offset[9:8]=00
    //         bit[6]=0  → offset[7]=0
    //         bit[7]=0  → offset[6]=0
    //         bit[11]=1 → offset[4]=1 (16)
    //         bits[5:3]=000 → offset[3:1]=000
    //         bit[2]=1  → offset[5]=1 (32)
    try expectEqual(@as(i32, 1072), imm.cj_offset(0x2904));
}

// ============================================================
// cb_offset — CB-format offset for C.BEQZ/C.BNEZ
// ============================================================

test "cb_offset extracts scrambled bits" {
    // 0x0C48: bit[12]=0 → offset[8]=0
    //         bits[6:5]=10 → offset[7:6]=10 (128)
    //         bit[2]=0  → offset[5]=0
    //         bits[11:10]=11 → offset[4:3]=11 (24)
    //         bits[4:3]=01 → offset[2:1]=01 (2)
    try expectEqual(@as(i32, 154), imm.cb_offset(0x0C48));
}

// ============================================================
// ci_lwsp_offset — C.LWSP offset
// ============================================================

test "ci_lwsp_offset extracts scrambled bits" {
    // 0x1050: bit[12]=1  → offset[5]=1 (32)
    //         bits[6:4]=101 → offset[4:2]=101 (20)
    //         bits[3:2]=00  → offset[7:6]=00
    try expectEqual(@as(u32, 52), imm.ci_lwsp_offset(0x1050));
}

// ============================================================
// css_swsp_offset — C.SWSP offset
// ============================================================

test "css_swsp_offset extracts scrambled bits" {
    // 0x1A80: bits[12:9]=1101 → offset[5:2]=1101 (52)
    //         bits[8:7]=01   → offset[7:6]=01 (64)
    try expectEqual(@as(u32, 116), imm.css_swsp_offset(0x1A80));
}
