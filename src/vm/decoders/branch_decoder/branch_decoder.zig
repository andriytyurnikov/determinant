const std = @import("std");
const instructions = @import("../../instructions.zig");
const bf = @import("../bitfields.zig");
const expand_mod = @import("../expand.zig");
const rv32i = instructions.rv32i;
const rv32m = instructions.rv32m;
const rv32a = instructions.rv32a;
const zicsr = instructions.zicsr;
const zba = instructions.zba;
const zbb = instructions.zbb;
const zbs = instructions.zbs;
const Opcode = instructions.Opcode;
const Instruction = instructions.Instruction;

pub const DecodeError = error{IllegalInstruction};

// Import bit-field extractors from shared module.
const rd = bf.rd;
const funct3 = bf.funct3;
const rs1 = bf.rs1;
const rs2 = bf.rs2;
const funct7 = bf.funct7;
const funct5 = bf.funct5;
const funct12 = bf.funct12;
const immI = bf.immI;
const immS = bf.immS;
const immB = bf.immB;
const immU = bf.immU;
const immJ = bf.immJ;

/// Decode a RISC-V instruction word into an Instruction.
/// Handles both 16-bit compressed (RV32C) and 32-bit instructions.
pub fn decode(raw: u32) DecodeError!Instruction {
    // Compressed instruction: low 2 bits != 11
    if (instructions.isCompressed(raw)) {
        return expand_mod.expandCompressed(raw);
    }
    const opcode_bits: u7 = @truncate(raw);
    return switch (opcode_bits) {
        0b0110011 => decodeR(raw),
        0b0010011 => decodeIAlu(raw),
        0b0000011 => decodeLoad(raw),
        0b0100011 => decodeStore(raw),
        0b1100011 => decodeBranch(raw),
        0b0110111 => decodeU(raw, .{ .i = .LUI }),
        0b0010111 => decodeU(raw, .{ .i = .AUIPC }),
        0b1101111 => decodeJ(raw),
        0b1100111 => decodeJalr(raw),
        0b0001111 => decodeFence(raw),
        0b0101111 => decodeAtomic(raw),
        0b1110011 => decodeSystem(raw),
        else => error.IllegalInstruction,
    };
}

// --- Sub-decoders ---

/// Decode an R-type instruction (opcode 0b0110011).
/// Extensions are checked in priority order: M-extension first (unique funct7=0b0000001
/// distinguishes it from RV32I which shares the same base opcode), then RV32I base,
/// then Zba, Zbb, Zbs. M-extension must precede RV32I because both use opcode 0b0110011
/// and a false match on funct3 alone would misidentify M instructions as RV32I.
fn decodeR(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);

    // M-extension: funct7 = 0b0000001, all 8 funct3 values valid
    if (f7 == 0b0000001) {
        return .{ .op = .{ .m = rv32m.decodeR(f3) }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    // RV32I base
    if (rv32i.decodeR(f3, f7)) |i_op| {
        return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    // Zba
    if (zba.decodeR(f3, f7)) |op| {
        return .{ .op = .{ .zba = op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    // Zbb
    if (zbb.decodeR(f3, f7, rs2(raw))) |op| {
        return .{ .op = .{ .zbb = op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    // Zbs
    if (zbs.decodeR(f3, f7)) |op| {
        return .{ .op = .{ .zbs = op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
    }

    return error.IllegalInstruction;
}

/// Decode an I-type ALU instruction (opcode 0b0010011).
/// RV32I base is checked first, then Zbb, then Zbs. For shift-like instructions
/// (funct3=001 or 101), funct7 disambiguates between extensions.
fn decodeIAlu(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);
    // For shift-like instructions (f3=001 or f3=101), immediate is the shamt
    const imm_val: i32 = if (f3 == 0b001 or f3 == 0b101)
        @as(i32, @intCast(rs2(raw)))
    else
        immI(raw);

    // RV32I base
    if (rv32i.decodeIAlu(f3, f7)) |i_op| {
        return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = imm_val, .raw = raw };
    }

    // Zbb I-type
    if (zbb.decodeIAlu(f3, f7, rs2(raw))) |op| {
        return .{ .op = .{ .zbb = op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = imm_val, .raw = raw };
    }

    // Zbs I-type
    if (zbs.decodeIAlu(f3, f7)) |op| {
        return .{ .op = .{ .zbs = op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = imm_val, .raw = raw };
    }

    return error.IllegalInstruction;
}

fn decodeLoad(raw: u32) DecodeError!Instruction {
    const i_op = rv32i.decodeLoad(funct3(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

fn decodeStore(raw: u32) DecodeError!Instruction {
    const i_op = rv32i.decodeStore(funct3(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .i = i_op }, .rs1 = rs1(raw), .rs2 = rs2(raw), .imm = immS(raw), .raw = raw };
}

fn decodeBranch(raw: u32) DecodeError!Instruction {
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

fn decodeFence(raw: u32) DecodeError!Instruction {
    if (funct3(raw) != 0b000) return error.IllegalInstruction;
    return .{ .op = .{ .i = .FENCE }, .raw = raw };
}

fn decodeAtomic(raw: u32) DecodeError!Instruction {
    if (funct3(raw) != 0b010) return error.IllegalInstruction;
    const a_op = rv32a.decodeR(funct5(raw)) orelse return error.IllegalInstruction;
    return .{ .op = .{ .a = a_op }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
}

fn decodeSystem(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    if (f3 == 0b000) {
        // ECALL / EBREAK: distinguished by funct12
        return switch (funct12(raw)) {
            0x000 => .{ .op = .{ .i = .ECALL }, .raw = raw },
            0x001 => .{ .op = .{ .i = .EBREAK }, .raw = raw },
            else => error.IllegalInstruction,
        };
    }
    const csr_op = zicsr.decodeSystem(f3) orelse return error.IllegalInstruction;
    return .{ .op = .{ .csr = csr_op }, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

test {
    _ = @import("branch_decoder_test.zig");
    _ = @import("../rv32c_cross_test.zig");
}
