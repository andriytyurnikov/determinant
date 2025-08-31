/// Zbb basic bit manipulation extension opcodes, decode, and execute.
const fmt = @import("../format.zig");
const Format = fmt.Format;

/// Zbb basic bit manipulation extension opcodes (18 variants).
pub const Opcode = enum {
    // R-type
    ANDN,
    ORN,
    XNOR,
    MAX,
    MAXU,
    MIN,
    MINU,
    ROL,
    ROR,
    ZEXT_H,

    // I-type
    CLZ,
    CTZ,
    CPOP,
    SEXT_B,
    SEXT_H,
    RORI,
    ORC_B,
    REV8,

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{
            .name_str = switch (self) {
                .SEXT_B => "SEXT.B",
                .SEXT_H => "SEXT.H",
                .ZEXT_H => "ZEXT.H",
                .ORC_B => "ORC.B",
                else => @tagName(self),
            },
            .fmt = switch (self) {
                .ANDN, .ORN, .XNOR, .MAX, .MAXU, .MIN, .MINU, .ROL, .ROR, .ZEXT_H => .R,
                .CLZ, .CTZ, .CPOP, .SEXT_B, .SEXT_H, .RORI, .ORC_B, .REV8 => .I,
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

/// Decode a Zbb R-type instruction from funct3, funct7, and rs2 field.
pub fn decodeR(f3: u3, f7: u7, rs2_field: u5) ?Opcode {
    return switch (f7) {
        0b0100000 => switch (f3) {
            0b100 => .XNOR,
            0b110 => .ORN,
            0b111 => .ANDN,
            else => null,
        },
        0b0000101 => switch (f3) {
            0b100 => .MIN,
            0b101 => .MINU,
            0b110 => .MAX,
            0b111 => .MAXU,
            else => null,
        },
        0b0110000 => switch (f3) {
            0b001 => .ROL,
            0b101 => .ROR,
            else => null,
        },
        0b0000100 => if (f3 == 0b100 and rs2_field == 0) .ZEXT_H else null,
        else => null,
    };
}

/// Decode a Zbb I-type ALU instruction from funct3, funct7, and rs2 field.
pub fn decodeIAlu(f3: u3, f7: u7, rs2_field: u5) ?Opcode {
    return switch (f3) {
        0b001 => if (f7 == 0b0110000) switch (rs2_field) {
            0 => .CLZ,
            1 => .CTZ,
            2 => .CPOP,
            4 => .SEXT_B,
            5 => .SEXT_H,
            else => null,
        } else null,
        0b101 => switch (f7) {
            0b0110000 => .RORI,
            0b0010100 => if (rs2_field == 7) .ORC_B else null,
            0b0110100 => if (rs2_field == 24) .REV8 else null,
            else => null,
        },
        else => null,
    };
}

/// Execute a Zbb instruction, returning the result for rd.
/// src2 is rs2_val for R-type or the immediate for I-type.
pub fn execute(op: Opcode, rs1_val: u32, src2: u32) u32 {
    return switch (op) {
        .ANDN => rs1_val & ~src2,
        .ORN => rs1_val | ~src2,
        .XNOR => rs1_val ^ ~src2,
        .CLZ => @clz(rs1_val),
        .CTZ => @ctz(rs1_val),
        .CPOP => @popCount(rs1_val),
        .MAX => @bitCast(@max(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2)))),
        .MAXU => @max(rs1_val, src2),
        .MIN => @bitCast(@min(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2)))),
        .MINU => @min(rs1_val, src2),
        .SEXT_B => blk: {
            const byte: u8 = @truncate(rs1_val);
            break :blk @bitCast(@as(i32, @as(i8, @bitCast(byte))));
        },
        .SEXT_H => blk: {
            const half: u16 = @truncate(rs1_val);
            break :blk @bitCast(@as(i32, @as(i16, @bitCast(half))));
        },
        .ZEXT_H => rs1_val & 0xFFFF,
        .ROL => blk: {
            const shamt: u5 = @truncate(src2);
            const compl: u5 = 0 -% shamt; // INVARIANT: wrapping subtraction for rotate complement
            break :blk (rs1_val << shamt) | (rs1_val >> compl);
        },
        .ROR, .RORI => blk: {
            const shamt: u5 = @truncate(src2);
            const compl: u5 = 0 -% shamt; // INVARIANT: wrapping subtraction for rotate complement
            break :blk (rs1_val >> shamt) | (rs1_val << compl);
        },
        .ORC_B => blk: {
            var result: u32 = 0;
            if ((rs1_val & 0x000000FF) != 0) result |= 0x000000FF;
            if ((rs1_val & 0x0000FF00) != 0) result |= 0x0000FF00;
            if ((rs1_val & 0x00FF0000) != 0) result |= 0x00FF0000;
            if ((rs1_val & 0xFF000000) != 0) result |= 0xFF000000;
            break :blk result;
        },
        .REV8 => @byteSwap(rs1_val),
    };
}

test {
    _ = @import("zbb_test.zig");
}
