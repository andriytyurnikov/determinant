/// RV32M multiply/divide extension opcodes, decode, and execute.

const std = @import("std");
const fmt = @import("../format.zig");
const Format = fmt.Format;

/// RV32M multiply/divide extension opcodes (8 variants).
pub const Opcode = enum {
    MUL,
    MULH,
    MULHSU,
    MULHU,
    DIV,
    DIVU,
    REM,
    REMU,

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

/// Decode an M-extension R-type instruction from funct3.
/// Returns non-optional: all 8 funct3 values are valid when funct7 = 0b0000001.
/// The caller in decoder.zig guards funct7 before calling — this preserves the
/// type-level guarantee of exhaustive funct3 coverage (no null possible).
pub fn decodeR(f3: u3) Opcode {
    return switch (f3) {
        0b000 => .MUL,
        0b001 => .MULH,
        0b010 => .MULHSU,
        0b011 => .MULHU,
        0b100 => .DIV,
        0b101 => .DIVU,
        0b110 => .REM,
        0b111 => .REMU,
    };
}

/// Execute an M-extension instruction, returning the result for rd.
/// INVARIANT: wrapping multiplication (*%) — overflow must wrap, not trap.
pub fn execute(op: Opcode, rs1_val: u32, rs2_val: u32) u32 {
    return switch (op) {
        .MUL => rs1_val *% rs2_val,
        .MULH => blk: {
            const a: i64 = @as(i32, @bitCast(rs1_val));
            const b: i64 = @as(i32, @bitCast(rs2_val));
            const result: u64 = @bitCast(a *% b);
            break :blk @truncate(result >> 32);
        },
        .MULHSU => blk: {
            const a: i64 = @as(i32, @bitCast(rs1_val));
            const b: i64 = @as(u32, rs2_val);
            const result: u64 = @bitCast(a *% b);
            break :blk @truncate(result >> 32);
        },
        .MULHU => blk: {
            const a: u64 = rs1_val;
            const b: u64 = rs2_val;
            break :blk @truncate((a *% b) >> 32);
        },
        .DIV => blk: {
            const a: i32 = @bitCast(rs1_val);
            const b: i32 = @bitCast(rs2_val);
            const res: i32 = if (b == 0)
                -1
            else if (a == std.math.minInt(i32) and b == -1)
                std.math.minInt(i32)
            else
                @divTrunc(a, b);
            break :blk @bitCast(res);
        },
        .DIVU => if (rs2_val == 0) 0xFFFFFFFF else rs1_val / rs2_val,
        .REM => blk: {
            const a: i32 = @bitCast(rs1_val);
            const b: i32 = @bitCast(rs2_val);
            const res: i32 = if (b == 0)
                a
            else if (a == std.math.minInt(i32) and b == -1)
                0
            else
                @rem(a, b);
            break :blk @bitCast(res);
        },
        .REMU => if (rs2_val == 0) rs1_val else rs1_val % rs2_val,
    };
}

test {
    _ = @import("rv32m_test.zig");
}
