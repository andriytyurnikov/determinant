const std = @import("std");

/// RV32I instruction formats.
pub const Format = enum {
    R,
    I,
    S,
    B,
    U,
    J,
};

/// RV32I opcodes.
pub const Opcode = enum {
    // R-type ALU
    ADD,
    SUB,
    SLL,
    SLT,
    SLTU,
    XOR,
    SRL,
    SRA,
    OR,
    AND,

    // R-type M-extension (multiply/divide)
    MUL,
    MULH,
    MULHSU,
    MULHU,
    DIV,
    DIVU,
    REM,
    REMU,

    // I-type ALU
    ADDI,
    SLTI,
    SLTIU,
    XORI,
    ORI,
    ANDI,
    SLLI,
    SRLI,
    SRAI,

    // Loads (I-type)
    LB,
    LH,
    LW,
    LBU,
    LHU,

    // Stores (S-type)
    SB,
    SH,
    SW,

    // Branches (B-type)
    BEQ,
    BNE,
    BLT,
    BGE,
    BLTU,
    BGEU,

    // Upper immediates (U-type)
    LUI,
    AUIPC,

    // Jumps
    JAL, // J-type
    JALR, // I-type

    // System
    ECALL,
    EBREAK,

    pub fn format(self: Opcode) Format {
        return switch (self) {
            .ADD, .SUB, .SLL, .SLT, .SLTU, .XOR, .SRL, .SRA, .OR, .AND,
            .MUL, .MULH, .MULHSU, .MULHU, .DIV, .DIVU, .REM, .REMU,
            => .R,
            .ADDI, .SLTI, .SLTIU, .XORI, .ORI, .ANDI, .SLLI, .SRLI, .SRAI => .I,
            .LB, .LH, .LW, .LBU, .LHU => .I,
            .JALR => .I,
            .ECALL, .EBREAK => .I,
            .SB, .SH, .SW => .S,
            .BEQ, .BNE, .BLT, .BGE, .BLTU, .BGEU => .B,
            .LUI, .AUIPC => .U,
            .JAL => .J,
        };
    }
};

/// Decoded RV32I instruction.
pub const Instruction = struct {
    op: Opcode,
    rd: u5 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm: i32 = 0,
    raw: u32,
};

test "opcode format mapping" {
    try std.testing.expectEqual(Format.R, Opcode.ADD.format());
    try std.testing.expectEqual(Format.I, Opcode.ADDI.format());
    try std.testing.expectEqual(Format.I, Opcode.LW.format());
    try std.testing.expectEqual(Format.S, Opcode.SW.format());
    try std.testing.expectEqual(Format.B, Opcode.BEQ.format());
    try std.testing.expectEqual(Format.U, Opcode.LUI.format());
    try std.testing.expectEqual(Format.J, Opcode.JAL.format());
    try std.testing.expectEqual(Format.I, Opcode.JALR.format());
    try std.testing.expectEqual(Format.I, Opcode.ECALL.format());
}
