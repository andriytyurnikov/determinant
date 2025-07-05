//! Opcode registry — single source of truth for all 94 supported opcodes.
//!
//! Each entry specifies the instruction's encoding fields. The comptime
//! generator in `lut_decoder.zig` derives all lookup tables from this list.
//!
//! Fields:
//!   op      — tagged union variant from instructions.Opcode
//!   opcode7 — bits [6:0], selects the decode strategy
//!   f3      — bits [14:12]; null if not used for identification
//!   f7      — bits [31:25]; null if not used for identification
//!   rs2_eq  — bits [24:20] must equal this value (Zbb special cases)
//!   f5      — bits [31:27], atomics only
//!   f12     — bits [31:20], ECALL/EBREAK only

const instructions = @import("../instructions.zig");
pub const Opcode = instructions.Opcode;

pub const Entry = struct {
    op: Opcode,
    opcode7: u7,
    f3: ?u3 = null,
    f7: ?u7 = null,
    rs2_eq: ?u5 = null,
    f5: ?u5 = null,
    f12: ?u12 = null,
};

pub const registry = [_]Entry{
    // ---- RV32I R-type (10) ---- opcode 0b0110011
    .{ .op = .{ .i = .ADD }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SUB }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0100000 },
    .{ .op = .{ .i = .SLL }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SLT }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SLTU }, .opcode7 = 0b0110011, .f3 = 0b011, .f7 = 0b0000000 },
    .{ .op = .{ .i = .XOR }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRL }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRA }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100000 },
    .{ .op = .{ .i = .OR }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000000 },
    .{ .op = .{ .i = .AND }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000000 },

    // ---- RV32M (8) ---- opcode 0b0110011, funct7 = 0b0000001
    .{ .op = .{ .m = .MUL }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULH }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULHSU }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULHU }, .opcode7 = 0b0110011, .f3 = 0b011, .f7 = 0b0000001 },
    .{ .op = .{ .m = .DIV }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000001 },
    .{ .op = .{ .m = .DIVU }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000001 },
    .{ .op = .{ .m = .REM }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000001 },
    .{ .op = .{ .m = .REMU }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000001 },

    // ---- Zba R-type (3) ---- opcode 0b0110011, funct7 = 0b0010000
    .{ .op = .{ .zba = .SH1ADD }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0010000 },
    .{ .op = .{ .zba = .SH2ADD }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0010000 },
    .{ .op = .{ .zba = .SH3ADD }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0010000 },

    // ---- Zbb R-type (10) ---- opcode 0b0110011
    .{ .op = .{ .zbb = .ANDN }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .ORN }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .XNOR }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .MIN }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MINU }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MAX }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MAXU }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .ROL }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .ROR }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .ZEXT_H }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000100, .rs2_eq = 0 },

    // ---- Zbs R-type (4) ---- opcode 0b0110011
    .{ .op = .{ .zbs = .BCLR }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BEXT }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BINV }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0110100 },
    .{ .op = .{ .zbs = .BSET }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0010100 },

    // ---- RV32I I-ALU non-shift (6) ---- opcode 0b0010011
    .{ .op = .{ .i = .ADDI }, .opcode7 = 0b0010011, .f3 = 0b000 },
    .{ .op = .{ .i = .SLTI }, .opcode7 = 0b0010011, .f3 = 0b010 },
    .{ .op = .{ .i = .SLTIU }, .opcode7 = 0b0010011, .f3 = 0b011 },
    .{ .op = .{ .i = .XORI }, .opcode7 = 0b0010011, .f3 = 0b100 },
    .{ .op = .{ .i = .ORI }, .opcode7 = 0b0010011, .f3 = 0b110 },
    .{ .op = .{ .i = .ANDI }, .opcode7 = 0b0010011, .f3 = 0b111 },

    // ---- RV32I I-ALU shift (3) ---- opcode 0b0010011
    .{ .op = .{ .i = .SLLI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRLI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRAI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0100000 },

    // ---- Zbb I-ALU (8) ---- opcode 0b0010011
    .{ .op = .{ .zbb = .RORI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .CLZ }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 0 },
    .{ .op = .{ .zbb = .CTZ }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 1 },
    .{ .op = .{ .zbb = .CPOP }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 2 },
    .{ .op = .{ .zbb = .SEXT_B }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 4 },
    .{ .op = .{ .zbb = .SEXT_H }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 5 },
    .{ .op = .{ .zbb = .ORC_B }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0010100, .rs2_eq = 7 },
    .{ .op = .{ .zbb = .REV8 }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110100, .rs2_eq = 24 },

    // ---- Zbs I-ALU shift (4) ---- opcode 0b0010011
    .{ .op = .{ .zbs = .BCLRI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BEXTI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BINVI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110100 },
    .{ .op = .{ .zbs = .BSETI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0010100 },

    // ---- Load (5) ---- opcode 0b0000011
    .{ .op = .{ .i = .LB }, .opcode7 = 0b0000011, .f3 = 0b000 },
    .{ .op = .{ .i = .LH }, .opcode7 = 0b0000011, .f3 = 0b001 },
    .{ .op = .{ .i = .LW }, .opcode7 = 0b0000011, .f3 = 0b010 },
    .{ .op = .{ .i = .LBU }, .opcode7 = 0b0000011, .f3 = 0b100 },
    .{ .op = .{ .i = .LHU }, .opcode7 = 0b0000011, .f3 = 0b101 },

    // ---- Store (3) ---- opcode 0b0100011
    .{ .op = .{ .i = .SB }, .opcode7 = 0b0100011, .f3 = 0b000 },
    .{ .op = .{ .i = .SH }, .opcode7 = 0b0100011, .f3 = 0b001 },
    .{ .op = .{ .i = .SW }, .opcode7 = 0b0100011, .f3 = 0b010 },

    // ---- Branch (6) ---- opcode 0b1100011
    .{ .op = .{ .i = .BEQ }, .opcode7 = 0b1100011, .f3 = 0b000 },
    .{ .op = .{ .i = .BNE }, .opcode7 = 0b1100011, .f3 = 0b001 },
    .{ .op = .{ .i = .BLT }, .opcode7 = 0b1100011, .f3 = 0b100 },
    .{ .op = .{ .i = .BGE }, .opcode7 = 0b1100011, .f3 = 0b101 },
    .{ .op = .{ .i = .BLTU }, .opcode7 = 0b1100011, .f3 = 0b110 },
    .{ .op = .{ .i = .BGEU }, .opcode7 = 0b1100011, .f3 = 0b111 },

    // ---- Atomic (11) ---- opcode 0b0101111, funct3 = 0b010
    .{ .op = .{ .a = .LR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00010 },
    .{ .op = .{ .a = .SC_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00011 },
    .{ .op = .{ .a = .AMOSWAP_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00001 },
    .{ .op = .{ .a = .AMOADD_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00000 },
    .{ .op = .{ .a = .AMOXOR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00100 },
    .{ .op = .{ .a = .AMOAND_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b01100 },
    .{ .op = .{ .a = .AMOOR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b01000 },
    .{ .op = .{ .a = .AMOMIN_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10000 },
    .{ .op = .{ .a = .AMOMAX_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10100 },
    .{ .op = .{ .a = .AMOMINU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11000 },
    .{ .op = .{ .a = .AMOMAXU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11100 },

    // ---- System (8) ---- opcode 0b1110011
    .{ .op = .{ .i = .ECALL }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x000 },
    .{ .op = .{ .i = .EBREAK }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x001 },
    .{ .op = .{ .csr = .CSRRW }, .opcode7 = 0b1110011, .f3 = 0b001 },
    .{ .op = .{ .csr = .CSRRS }, .opcode7 = 0b1110011, .f3 = 0b010 },
    .{ .op = .{ .csr = .CSRRC }, .opcode7 = 0b1110011, .f3 = 0b011 },
    .{ .op = .{ .csr = .CSRRWI }, .opcode7 = 0b1110011, .f3 = 0b101 },
    .{ .op = .{ .csr = .CSRRSI }, .opcode7 = 0b1110011, .f3 = 0b110 },
    .{ .op = .{ .csr = .CSRRCI }, .opcode7 = 0b1110011, .f3 = 0b111 },

    // ---- Fixed opcodes (5) ----
    .{ .op = .{ .i = .LUI }, .opcode7 = 0b0110111 },
    .{ .op = .{ .i = .AUIPC }, .opcode7 = 0b0010111 },
    .{ .op = .{ .i = .JAL }, .opcode7 = 0b1101111 },
    .{ .op = .{ .i = .JALR }, .opcode7 = 0b1100111, .f3 = 0b000 },
    .{ .op = .{ .i = .FENCE }, .opcode7 = 0b0001111, .f3 = 0b000 },
};

/// Decode strategies — what sub-table to consult after level-1 lookup.
pub const Strategy = enum(u8) {
    illegal,
    r_type, // → r_table[funct3][funct7]
    i_alu, // → i_alu_base[funct3] or shift_table[idx][funct7]
    load, // → load_table[funct3]
    store, // → store_table[funct3]
    branch, // → branch_table[funct3]
    atomic, // → atomic_table[funct5], funct3==010 guard
    system, // → system_table[funct3], or ECALL/EBREAK by funct12
    lui, // fixed .{ .i = .LUI }
    auipc, // fixed .{ .i = .AUIPC }
    jal, // fixed .{ .i = .JAL }
    jalr, // funct3==0 guard, fixed .{ .i = .JALR }
    fence, // funct3==0 guard, fixed .{ .i = .FENCE }
};

pub fn strategyFor(opcode7: u7) Strategy {
    return switch (opcode7) {
        0b0110011 => .r_type,
        0b0010011 => .i_alu,
        0b0000011 => .load,
        0b0100011 => .store,
        0b1100011 => .branch,
        0b0101111 => .atomic,
        0b1110011 => .system,
        0b0110111 => .lui,
        0b0010111 => .auipc,
        0b1101111 => .jal,
        0b1100111 => .jalr,
        0b0001111 => .fence,
        else => .illegal,
    };
}
