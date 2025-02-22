/// Zicsr extension: Control and Status Register instructions (6 variants).
/// This module does NOT import instruction.zig — it is imported BY it.

pub const Opcode = enum {
    CSRRW,
    CSRRS,
    CSRRC,
    CSRRWI,
    CSRRSI,
    CSRRCI,
};

/// Decode a SYSTEM instruction's funct3 into a Zicsr opcode.
/// Returns null for funct3 values that belong to other SYSTEM instructions
/// (0b000 = ECALL/EBREAK, 0b100 = reserved).
pub fn decodeSystem(f3: u3) ?Opcode {
    return switch (f3) {
        0b001 => .CSRRW,
        0b010 => .CSRRS,
        0b011 => .CSRRC,
        0b101 => .CSRRWI,
        0b110 => .CSRRSI,
        0b111 => .CSRRCI,
        else => null,
    };
}

test {
    _ = @import("zicsr_test.zig");
}
