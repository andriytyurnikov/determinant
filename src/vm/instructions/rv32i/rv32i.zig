/// RV32I base integer instruction set opcodes and decode helpers.

const fmt = @import("../format.zig");
const Format = fmt.Format;

pub const rv32c = @import("rv32c/rv32c.zig");

/// RV32I opcodes (39 variants).
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

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{
            .name_str = @tagName(self),
            .fmt = switch (self) {
                .ADD, .SUB, .SLL, .SLT, .SLTU, .XOR, .SRL, .SRA, .OR, .AND => .R,
                .ADDI, .SLTI, .SLTIU, .XORI, .ORI, .ANDI, .SLLI, .SRLI, .SRAI => .I,
                .LB, .LH, .LW, .LBU, .LHU => .I,
                .JALR => .I,
                .ECALL, .EBREAK => .I,
                .SB, .SH, .SW => .S,
                .BEQ, .BNE, .BLT, .BGE, .BLTU, .BGEU => .B,
                .LUI, .AUIPC => .U,
                .JAL => .J,
            },
        };
    }

    pub fn name(self: Opcode) []const u8 {
        return fmt.opcodeName(Opcode, self);
    }

    pub fn format(self: Opcode) Format {
        return fmt.opcodeFormat(Opcode, self);
    }
};

/// Decode an R-type base integer instruction from funct3 and funct7.
/// Returns null for illegal funct3/funct7 combinations.
pub fn decodeR(f3: u3, f7: u7) ?Opcode {
    return switch (f3) {
        0b000 => switch (f7) {
            0b0000000 => .ADD,
            0b0100000 => .SUB,
            else => null,
        },
        0b001 => if (f7 == 0b0000000) .SLL else null,
        0b010 => if (f7 == 0b0000000) .SLT else null,
        0b011 => if (f7 == 0b0000000) .SLTU else null,
        0b100 => if (f7 == 0b0000000) .XOR else null,
        0b101 => switch (f7) {
            0b0000000 => .SRL,
            0b0100000 => .SRA,
            else => null,
        },
        0b110 => if (f7 == 0b0000000) .OR else null,
        0b111 => if (f7 == 0b0000000) .AND else null,
    };
}

/// Decode an I-type ALU instruction from funct3 and funct7 (for shifts).
/// Returns null for illegal combinations.
pub fn decodeIAlu(f3: u3, f7: u7) ?Opcode {
    return switch (f3) {
        0b000 => .ADDI,
        0b010 => .SLTI,
        0b011 => .SLTIU,
        0b100 => .XORI,
        0b110 => .ORI,
        0b111 => .ANDI,
        0b001 => if (f7 == 0b0000000) .SLLI else null,
        0b101 => switch (f7) {
            0b0000000 => .SRLI,
            0b0100000 => .SRAI,
            else => null,
        },
    };
}

/// Decode a load instruction from funct3.
pub fn decodeLoad(f3: u3) ?Opcode {
    return switch (f3) {
        0b000 => .LB,
        0b001 => .LH,
        0b010 => .LW,
        0b100 => .LBU,
        0b101 => .LHU,
        else => null,
    };
}

/// Decode a store instruction from funct3.
pub fn decodeStore(f3: u3) ?Opcode {
    return switch (f3) {
        0b000 => .SB,
        0b001 => .SH,
        0b010 => .SW,
        else => null,
    };
}

/// Decode a branch instruction from funct3.
pub fn decodeBranch(f3: u3) ?Opcode {
    return switch (f3) {
        0b000 => .BEQ,
        0b001 => .BNE,
        0b100 => .BLT,
        0b101 => .BGE,
        0b110 => .BLTU,
        0b111 => .BGEU,
        else => null,
    };
}

test {
    _ = @import("rv32i_test.zig");
    _ = @import("rv32c/rv32c.zig");
}
