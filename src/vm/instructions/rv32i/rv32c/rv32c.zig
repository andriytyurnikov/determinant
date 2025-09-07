//! RV32C compressed instruction opcodes and decode logic.
//! Every 16-bit compressed instruction maps to an existing RV32I instruction.
//! Unlike other extensions, rv32c has its own Opcode enum for decode/display purposes only —
//! it is NOT part of the instructions.Opcode tagged union (no execution path, no format).

const fmt = @import("../../format.zig");
const Format = fmt.Format;
const rv32i = @import("../rv32i.zig");
const imm = @import("rv32c_imm.zig");
const rv32c_expand = @import("rv32c_expand.zig");

/// Re-export expand from rv32c_expand.zig — preserves the public API (rv32c.expand).
pub const expand = rv32c_expand.expand;

/// RV32C compressed instruction opcodes (26 variants).
/// Used for self-documenting decode and display (e.g. showing "C.LW" instead of "LW").
pub const Opcode = enum {
    // Quadrant 0
    C_ADDI4SPN,
    C_LW,
    C_SW,
    // Quadrant 1
    C_ADDI, // includes C.NOP (rd=0, imm=0)
    C_JAL,
    C_LI,
    C_ADDI16SP,
    C_LUI,
    C_SRLI,
    C_SRAI,
    C_ANDI,
    C_SUB,
    C_XOR,
    C_OR,
    C_AND,
    C_J,
    C_BEQZ,
    C_BNEZ,
    // Quadrant 2
    C_SLLI,
    C_LWSP,
    C_JR,
    C_MV,
    C_EBREAK,
    C_JALR,
    C_ADD,
    C_SWSP,

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{
            .name_str = comptime dotName(@tagName(self)),
            .fmt = switch (self) {
                .C_LW, .C_SW => .S, // CL/CS format (load/store)
                .C_ADDI4SPN, .C_ADDI, .C_LI, .C_ADDI16SP, .C_LUI => .I,
                .C_SRLI, .C_SRAI, .C_ANDI, .C_SLLI => .I,
                .C_JAL, .C_J => .J,
                .C_BEQZ, .C_BNEZ => .B,
                .C_SUB, .C_XOR, .C_OR, .C_AND, .C_ADD, .C_MV => .R,
                .C_LWSP, .C_SWSP => .I,
                .C_JR, .C_JALR => .I,
                .C_EBREAK => .I,
            },
        };
    }

    pub fn name(self: Opcode) []const u8 {
        return fmt.opcodeName(Opcode, self);
    }

    pub fn format(self: Opcode) Format {
        return fmt.opcodeFormat(Opcode, self);
    }

    fn dotName(comptime tag: []const u8) []const u8 {
        comptime {
            if (tag.len < 2 or tag[0] != 'C' or tag[1] != '_')
                @compileError("expected C_ prefix on rv32c opcode tag");
            var buf: [tag.len]u8 = tag[0..tag.len].*;
            buf[1] = '.';
            const final = buf;
            return &final;
        }
    }
};

/// Expanded compressed instruction — uses rv32i.Opcode directly (sibling-only dependency).
/// The decoder wraps this into a full Instruction with .op = .{ .i = exp.op }.
pub const Expanded = struct {
    op: rv32i.Opcode,
    rd: u5 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm: i32 = 0,
    compressed_op: Opcode,
};

/// Decode a 16-bit compressed instruction into its Opcode.
/// Only fails on truly invalid bit combinations (unknown funct3, reserved funct2b).
/// Does NOT validate operand constraints (nzuimm=0, shamt[5]=1) — that stays in expand().
pub fn decode(half: u16) error{IllegalInstruction}!Opcode {
    return switch (@as(u2, @truncate(half))) {
        0b00 => decodeQ0(half),
        0b01 => decodeQ1(half),
        0b10 => decodeQ2(half),
        0b11 => error.IllegalInstruction, // not compressed
    };
}

fn decodeQ0(half: u16) error{IllegalInstruction}!Opcode {
    return switch (imm.funct3(half)) {
        0b000 => .C_ADDI4SPN,
        0b010 => .C_LW,
        0b110 => .C_SW,
        else => error.IllegalInstruction,
    };
}

fn decodeQ1(half: u16) error{IllegalInstruction}!Opcode {
    return switch (imm.funct3(half)) {
        0b000 => .C_ADDI,
        0b001 => .C_JAL,
        0b010 => .C_LI,
        0b011 => {
            const rd_val: u5 = @truncate(half >> 7);
            return if (rd_val == 2) .C_ADDI16SP else .C_LUI;
        },
        0b100 => decodeQ1Alu(half),
        0b101 => .C_J,
        0b110 => .C_BEQZ,
        0b111 => .C_BNEZ,
    };
}

fn decodeQ1Alu(half: u16) error{IllegalInstruction}!Opcode {
    const funct2: u2 = @truncate(half >> 10);
    return switch (funct2) {
        0b00 => .C_SRLI,
        0b01 => .C_SRAI,
        0b10 => .C_ANDI,
        0b11 => {
            const funct1: u1 = @truncate(half >> 12);
            if (funct1 != 0) return error.IllegalInstruction; // bit 12=1 is RV64C encoding space (C.SUBW/C.ADDW)
            const funct2b: u2 = @truncate(half >> 5);
            return switch (funct2b) {
                0b00 => .C_SUB,
                0b01 => .C_XOR,
                0b10 => .C_OR,
                0b11 => .C_AND,
            };
        },
    };
}

fn decodeQ2(half: u16) error{IllegalInstruction}!Opcode {
    return switch (imm.funct3(half)) {
        0b000 => .C_SLLI,
        0b010 => .C_LWSP,
        0b100 => {
            const bit12: u1 = @truncate(half >> 12);
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            if (bit12 == 0) {
                return if (rs2_val == 0) .C_JR else .C_MV;
            } else {
                if (rs2_val == 0) {
                    return if (rd_rs1 == 0) .C_EBREAK else .C_JALR;
                } else {
                    return .C_ADD;
                }
            }
        },
        0b110 => .C_SWSP,
        else => error.IllegalInstruction,
    };
}

test {
    _ = @import("rv32c_test.zig");
}
