//! Shared bit-field extraction functions for RISC-V instruction words.
//! Used by both branch_decoder.zig and lut_decoder.zig.

/// Canonical decode error — imported by both decoders so the error set is defined once.
pub const DecodeError = error{IllegalInstruction};

// --- Register / function fields ---

pub fn rd(raw: u32) u5 {
    return @truncate(raw >> 7);
}

pub fn funct3(raw: u32) u3 {
    return @truncate(raw >> 12);
}

pub fn rs1(raw: u32) u5 {
    return @truncate(raw >> 15);
}

pub fn rs2(raw: u32) u5 {
    return @truncate(raw >> 20);
}

pub fn funct7(raw: u32) u7 {
    return @truncate(raw >> 25);
}

pub fn funct5(raw: u32) u5 {
    return @truncate(raw >> 27);
}

pub fn funct12(raw: u32) u12 {
    return @truncate(raw >> 20);
}

pub fn opcode7(raw: u32) u7 {
    return @truncate(raw);
}

// --- Immediate extraction ---

pub fn immI(raw: u32) i32 {
    const bits: i32 = @bitCast(raw);
    return bits >> 20; // arithmetic right shift sign-extends
}

pub fn immS(raw: u32) i32 {
    const imm_11_5: u32 = (raw >> 25) & 0x7F;
    const imm_4_0: u32 = (raw >> 7) & 0x1F;
    const imm_raw: u32 = (imm_11_5 << 5) | imm_4_0;
    // Sign extend from bit 11
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 20)) >> 20;
    return shifted;
}

pub fn immB(raw: u32) i32 {
    // imm[12|10:5|4:1|11]
    const imm_12: u32 = (raw >> 31) & 1;
    const imm_11: u32 = (raw >> 7) & 1;
    const imm_10_5: u32 = (raw >> 25) & 0x3F;
    const imm_4_1: u32 = (raw >> 8) & 0xF;
    const imm_raw: u32 = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1);
    // Sign extend from bit 12
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 19)) >> 19;
    return shifted;
}

pub fn immU(raw: u32) i32 {
    return @bitCast(raw & 0xFFFFF000);
}

pub fn immJ(raw: u32) i32 {
    // imm[20|10:1|11|19:12]
    const imm_20: u32 = (raw >> 31) & 1;
    const imm_19_12: u32 = (raw >> 12) & 0xFF;
    const imm_11: u32 = (raw >> 20) & 1;
    const imm_10_1: u32 = (raw >> 21) & 0x3FF;
    const imm_raw: u32 = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1);
    // Sign extend from bit 20
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 11)) >> 11;
    return shifted;
}
