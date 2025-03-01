const Format = @import("format.zig").Format;

/// RV32A atomic extension opcodes (11 variants).
pub const Opcode = enum {
    LR_W,
    SC_W,
    AMOSWAP_W,
    AMOADD_W,
    AMOXOR_W,
    AMOAND_W,
    AMOOR_W,
    AMOMIN_W,
    AMOMAX_W,
    AMOMINU_W,
    AMOMAXU_W,

    pub fn format(self: Opcode) Format {
        _ = self;
        return .R;
    }
};

/// Decode an A-extension R-type instruction from funct7.
/// The funct5 field (bits [6:2] of funct7) determines the operation.
/// aq/rl bits (bits [1:0] of funct7) are ignored on single-hart.
pub fn decodeR(f7: u7) ?Opcode {
    const funct5: u5 = @truncate(f7 >> 2);
    return switch (funct5) {
        0b00010 => .LR_W,
        0b00011 => .SC_W,
        0b00001 => .AMOSWAP_W,
        0b00000 => .AMOADD_W,
        0b00100 => .AMOXOR_W,
        0b01100 => .AMOAND_W,
        0b01000 => .AMOOR_W,
        0b10000 => .AMOMIN_W,
        0b10100 => .AMOMAX_W,
        0b11000 => .AMOMINU_W,
        0b11100 => .AMOMAXU_W,
        else => null,
    };
}

/// Compute the result of an AMO operation given the old memory value and rs2.
/// Only valid for AMO opcodes (not LR_W/SC_W).
pub fn computeAmo(op: Opcode, old: u32, rs2_val: u32) u32 {
    return switch (op) {
        .AMOSWAP_W => rs2_val,
        .AMOADD_W => old +% rs2_val,
        .AMOXOR_W => old ^ rs2_val,
        .AMOAND_W => old & rs2_val,
        .AMOOR_W => old | rs2_val,
        .AMOMIN_W => @bitCast(@min(@as(i32, @bitCast(old)), @as(i32, @bitCast(rs2_val)))),
        .AMOMAX_W => @bitCast(@max(@as(i32, @bitCast(old)), @as(i32, @bitCast(rs2_val)))),
        .AMOMINU_W => @min(old, rs2_val),
        .AMOMAXU_W => @max(old, rs2_val),
        .LR_W, .SC_W => unreachable,
    };
}

test {
    _ = @import("rv32a_test.zig");
}
