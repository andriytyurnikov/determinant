//! Zbs single-bit manipulation extension — 8 opcodes (4 R-type + 4 I-type).

const fmt = @import("format.zig");
const Format = fmt.Format;

/// Zbs single-bit manipulation extension opcodes (8 variants).
pub const Opcode = enum {
    // R-type
    BCLR,
    BEXT,
    BINV,
    BSET,
    // I-type
    BCLRI,
    BEXTI,
    BINVI,
    BSETI,

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{
            .name_str = @tagName(self),
            .fmt = switch (self) {
                .BCLR, .BEXT, .BINV, .BSET => .R,
                .BCLRI, .BEXTI, .BINVI, .BSETI => .I,
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

/// Decode a Zbs R-type instruction from funct3 and funct7.
pub fn decodeR(f3: u3, f7: u7) ?Opcode {
    return switch (f7) {
        0b0100100 => switch (f3) {
            0b001 => .BCLR,
            0b101 => .BEXT,
            else => null,
        },
        0b0110100 => if (f3 == 0b001) .BINV else null,
        0b0010100 => if (f3 == 0b001) .BSET else null,
        else => null,
    };
}

/// Decode a Zbs I-type ALU instruction from funct3 and funct7.
pub fn decodeIAlu(f3: u3, f7: u7) ?Opcode {
    return switch (f7) {
        0b0100100 => switch (f3) {
            0b001 => .BCLRI,
            0b101 => .BEXTI,
            else => null,
        },
        0b0110100 => if (f3 == 0b001) .BINVI else null,
        0b0010100 => if (f3 == 0b001) .BSETI else null,
        else => null,
    };
}

/// Execute a Zbs instruction, returning the result for rd.
/// src2 is rs2_val for R-type or the immediate for I-type.
pub fn execute(op: Opcode, rs1_val: u32, src2: u32) u32 {
    const shamt: u5 = @truncate(src2);
    return switch (op) {
        .BCLR, .BCLRI => rs1_val & ~(@as(u32, 1) << shamt),
        .BEXT, .BEXTI => (rs1_val >> shamt) & 1,
        .BINV, .BINVI => rs1_val ^ (@as(u32, 1) << shamt),
        .BSET, .BSETI => rs1_val | (@as(u32, 1) << shamt),
    };
}

test {
    _ = @import("zbs/tests.zig");
}
