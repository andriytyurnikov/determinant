//! Zba address generation extension — SH1ADD, SH2ADD, SH3ADD.

const fmt = @import("../format.zig");
const Format = fmt.Format;

/// Zba address generation extension opcodes (3 variants).
pub const Opcode = enum {
    SH1ADD,
    SH2ADD,
    SH3ADD,

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{ .name_str = @tagName(self), .fmt = .R };
    }

    pub fn name(self: Opcode) []const u8 {
        return fmt.opcodeName(Opcode, self);
    }

    pub fn format(self: Opcode) Format {
        return fmt.opcodeFormat(Opcode, self);
    }
};

/// Decode a Zba R-type instruction from funct3 and funct7.
pub fn decodeR(f3: u3, f7: u7) ?Opcode {
    if (f7 != 0b0010000) return null;
    return switch (f3) {
        0b010 => .SH1ADD,
        0b100 => .SH2ADD,
        0b110 => .SH3ADD,
        else => null,
    };
}

/// Execute a Zba instruction, returning the result for rd.
/// INVARIANT: wrapping addition (+%) — shifted-adds must wrap, not trap.
pub fn execute(op: Opcode, rs1_val: u32, rs2_val: u32) u32 {
    return switch (op) {
        .SH1ADD => (rs1_val << 1) +% rs2_val,
        .SH2ADD => (rs1_val << 2) +% rs2_val,
        .SH3ADD => (rs1_val << 3) +% rs2_val,
    };
}

test {
    _ = @import("zba_test.zig");
}
