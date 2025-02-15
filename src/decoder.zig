const std = @import("std");
const instruction = @import("instruction.zig");
const rv32i = instruction.rv32i;
const rv32m = instruction.rv32m;
const rv32a = instruction.rv32a;
const rv32c = @import("instruction/rv32c.zig");
const Opcode = instruction.Opcode;
const Instruction = instruction.Instruction;

pub const DecodeError = error{IllegalInstruction};

/// Decode a RISC-V instruction word into an Instruction.
/// Handles both 16-bit compressed (RV32C) and 32-bit instructions.
pub fn decode(raw: u32) DecodeError!Instruction {
    // Compressed instruction: low 2 bits != 11
    if ((raw & 0b11) != 0b11) {
        return rv32c.expand(@truncate(raw));
    }
    const opcode_bits: u7 = @truncate(raw);
    return switch (opcode_bits) {
        0b0110011 => decodeR(raw),
        0b0010011 => decodeIAlu(raw),
        0b0000011 => decodeLoad(raw),
        0b0100011 => decodeS(raw),
        0b1100011 => decodeB(raw),
        0b0110111 => decodeU(raw, .{ .i = .LUI }),
        0b0010111 => decodeU(raw, .{ .i = .AUIPC }),
        0b1101111 => decodeJ(raw),
        0b1100111 => decodeJalr(raw),
        0b0101111 => decodeAtomic(raw),
        0b1110011 => decodeSystem(raw),
        else => error.IllegalInstruction,
    };
}

// --- Bit field extraction ---

fn rd(raw: u32) u5 {
    return @truncate(raw >> 7);
}

fn funct3(raw: u32) u3 {
    return @truncate(raw >> 12);
}

fn rs1(raw: u32) u5 {
    return @truncate(raw >> 15);
}

fn rs2(raw: u32) u5 {
    return @truncate(raw >> 20);
}

fn funct7(raw: u32) u7 {
    return @truncate(raw >> 25);
}

// --- Immediate extraction ---

fn immI(raw: u32) i32 {
    const bits: i32 = @bitCast(raw);
    return bits >> 20; // arithmetic right shift sign-extends
}

fn immS(raw: u32) i32 {
    const imm_11_5: u32 = (raw >> 25) & 0x7F;
    const imm_4_0: u32 = (raw >> 7) & 0x1F;
    const imm_raw: u32 = (imm_11_5 << 5) | imm_4_0;
    // Sign extend from bit 11
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 20)) >> 20;
    return shifted;
}

fn immB(raw: u32) i32 {
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

fn immU(raw: u32) i32 {
    return @bitCast(raw & 0xFFFFF000);
}

fn immJ(raw: u32) i32 {
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

// --- Sub-decoders ---

fn decodeR(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);

    // M-extension: funct7 = 0b0000001
    if (f7 == 0b0000001) {
        return .{ .op = .{ .m = rv32m.decodeR(f3) }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    const i_op = rv32i.decodeR(f3, f7) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
}

fn decodeIAlu(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);
    const i_op = rv32i.decodeIAlu(f3, f7) orelse return error.IllegalInstruction;
    // For shift instructions, immediate is the shamt (rs2 field = bits [24:20])
    const imm_val: i32 = if (f3 == 0b001 or f3 == 0b101)
        @as(i32, @intCast(rs2(raw)))
    else
        immI(raw);
    return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = imm_val, .raw = raw };
}

fn decodeLoad(raw: u32) DecodeError!Instruction {
    const i_op = rv32i.decodeLoad(funct3(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

fn decodeS(raw: u32) DecodeError!Instruction {
    const i_op = rv32i.decodeStore(funct3(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rs1 = rs1(raw), .rs2 = rs2(raw), .imm = immS(raw), .raw = raw };
}

fn decodeB(raw: u32) DecodeError!Instruction {
    const i_op = rv32i.decodeBranch(funct3(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rs1 = rs1(raw), .rs2 = rs2(raw), .imm = immB(raw), .raw = raw };
}

fn decodeU(raw: u32, op: Opcode) DecodeError!Instruction {
    return .{ .op = op, .rd = rd(raw), .imm = immU(raw), .raw = raw };
}

fn decodeJ(raw: u32) DecodeError!Instruction {
    return .{ .op = .{ .i = .JAL }, .rd = rd(raw), .imm = immJ(raw), .raw = raw };
}

fn decodeJalr(raw: u32) DecodeError!Instruction {
    if (funct3(raw) != 0b000) return error.IllegalInstruction;
    return .{ .op = .{ .i = .JALR }, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

fn decodeAtomic(raw: u32) DecodeError!Instruction {
    if (funct3(raw) != 0b010) return error.IllegalInstruction;
    const a_op = rv32a.decodeR(funct7(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .a = a_op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
}

fn decodeSystem(raw: u32) DecodeError!Instruction {
    return switch (raw) {
        0x00000073 => .{ .op = .{ .i = .ECALL }, .raw = raw },
        0x00100073 => .{ .op = .{ .i = .EBREAK }, .raw = raw },
        else => error.IllegalInstruction,
    };
}
