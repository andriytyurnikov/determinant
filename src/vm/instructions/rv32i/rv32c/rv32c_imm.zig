//! Pure stateless immediate extraction helpers for RV32C compressed instructions.

/// Map 3-bit compressed register field to x8-x15.
pub fn cReg(r: u3) u5 {
    return @as(u5, r) + 8;
}

/// Extract bits [15:13] — the funct3 field for compressed instructions.
pub fn funct3(half: u16) u3 {
    return @truncate(half >> 13);
}

/// CIW-format nzuimm for C.ADDI4SPN.
/// Bits: [12:11] → [5:4], [10:7] → [9:6], [6] → [2], [5] → [3]
pub fn ciw_nzuimm(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x30) | // bits [12:11] → nzuimm[5:4]
        ((b >> 1) & 0x3C0) | // bits [10:7] → nzuimm[9:6]
        ((b >> 4) & 0x4) | // bit [6] → nzuimm[2]
        ((b >> 2) & 0x8); // bit [5] → nzuimm[3]
}

/// CL/CS-format word offset for C.LW/C.SW.
/// Bits: [12:10] → offset[5:3], [6] → offset[2], [5] → offset[6]
pub fn clsw_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x38) | // bits [12:10] → offset[5:3]
        ((b >> 4) & 0x4) | // bit [6] → offset[2]
        ((b << 1) & 0x40); // bit [5] → offset[6]
}

/// CI-format signed 6-bit immediate.
/// bit[12] → imm[5], bits[6:2] → imm[4:0], sign-extended.
pub fn ci_imm(half: u16) i32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    const raw: u6 = @truncate((hi << 5) | lo);
    return @as(i6, @bitCast(raw));
}

/// CI-format unsigned 6-bit shamt (for shifts).
/// bit[12] → shamt[5], bits[6:2] → shamt[4:0]
pub fn ci_shamt(half: u16) u32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    return (hi << 5) | lo;
}

/// C.ADDI16SP immediate.
/// bit[12] → imm[9], bits[6:2] → imm[4|6|8:7|5], sign-extended.
pub fn ci_addi16sp_imm(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 3) & 0x200) | // bit[12] → imm[9]
        ((b >> 2) & 0x10) | // bit[6] → imm[4]
        ((b << 1) & 0x40) | // bit[5] → imm[6]
        ((b << 4) & 0x180) | // bits[4:3] → imm[8:7]
        ((b << 3) & 0x20); // bit[2] → imm[5]
    const raw10: u10 = @truncate(raw);
    return @as(i10, @bitCast(raw10));
}

/// C.LUI immediate (upper 20 bits).
/// bit[12] → imm[17], bits[6:2] → imm[16:12], sign-extended to 32, shifted left 12.
pub fn ci_lui_imm(half: u16) i32 {
    const lo: u32 = (half >> 2) & 0x1F;
    const hi: u32 = (half >> 12) & 1;
    const raw: u6 = @truncate((hi << 5) | lo);
    const sign_ext: i32 = @as(i6, @bitCast(raw));
    // Shift left by 12 to produce the upper immediate
    return sign_ext << 12;
}

/// CJ-format offset for C.J/C.JAL.
/// Bits: [12] → [11], [11] → [4], [10:9] → [9:8], [8] → [10], [7] → [6], [6] → [7], [5:3] → [3:1], [2] → [5]
pub fn cj_offset(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 1) & 0x800) | // bit[12] → offset[11]
        ((b << 2) & 0x400) | // bit[8] → offset[10]
        ((b >> 1) & 0x300) | // bits[10:9] → offset[9:8]
        ((b << 1) & 0x80) | // bit[6] → offset[7]
        ((b >> 1) & 0x40) | // bit[7] → offset[6]
        ((b >> 7) & 0x10) | // bit[11] → offset[4]
        ((b >> 2) & 0xE) | // bits[5:3] → offset[3:1]
        ((b << 3) & 0x20); // bit[2] → offset[5]
    const raw12: u12 = @truncate(raw);
    return @as(i12, @bitCast(raw12));
}

/// CB-format offset for C.BEQZ/C.BNEZ.
/// Bits: [12] → [8], [11:10] → [4:3], [6] → [7], [5] → [6], [4:3] → [2:1], [2] → [5]
pub fn cb_offset(half: u16) i32 {
    const b: u32 = half;
    const raw: u32 = ((b >> 4) & 0x100) | // bit[12] → offset[8]
        ((b << 1) & 0xC0) | // bits[6:5] → offset[7:6]
        ((b << 3) & 0x20) | // bit[2] → offset[5]
        ((b >> 7) & 0x18) | // bits[11:10] → offset[4:3]
        ((b >> 2) & 0x6); // bits[4:3] → offset[2:1]
    const raw9: u9 = @truncate(raw);
    return @as(i9, @bitCast(raw9));
}

/// C.LWSP offset: bit[12] → offset[5], bits[6:4] → offset[4:2], bits[3:2] → offset[7:6]
pub fn ci_lwsp_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x20) | // bit[12] → offset[5]
        ((b >> 2) & 0x1C) | // bits[6:4] → offset[4:2]
        ((b << 4) & 0xC0); // bits[3:2] → offset[7:6]
}

/// C.SWSP offset: bits[12:9] → offset[5:2], bits[8:7] → offset[7:6]
pub fn css_swsp_offset(half: u16) u32 {
    const b: u32 = half;
    return ((b >> 7) & 0x3C) | // bits[12:9] → offset[5:2]
        ((b >> 1) & 0xC0); // bits[8:7] → offset[7:6]
}
