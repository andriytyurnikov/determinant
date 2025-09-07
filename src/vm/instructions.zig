//! Tagged union Opcode spanning all ISA extensions, plus Instruction struct.

const std = @import("std");

pub const rv32i = @import("instructions/rv32i/rv32i.zig");
pub const rv32m = @import("instructions/rv32m/rv32m.zig");
pub const rv32a = @import("instructions/rv32a/rv32a.zig");
pub const zicsr = @import("instructions/zicsr/zicsr.zig");
pub const zba = @import("instructions/zba/zba.zig");
pub const zbb = @import("instructions/zbb/zbb.zig");
pub const zbs = @import("instructions/zbs/zbs.zig");

pub const Format = @import("instructions/format.zig").Format;

/// Tagged union opcode spanning all supported ISA extensions.
pub const Opcode = union(enum) {
    i: rv32i.Opcode,
    m: rv32m.Opcode,
    a: rv32a.Opcode,
    csr: zicsr.Opcode,
    zba: zba.Opcode,
    zbb: zbb.Opcode,
    zbs: zbs.Opcode,

    pub fn format(self: Opcode) Format {
        return switch (self) {
            inline else => |op| op.format(),
        };
    }

    pub fn name(self: Opcode) []const u8 {
        return switch (self) {
            inline else => |op| op.name(),
        };
    }
};

/// Returns true if the raw instruction bits represent a 16-bit compressed (RV32C) instruction.
/// Compressed instructions have bits [1:0] != 0b11.
/// INVARIANT: single source of truth for 16-bit vs 32-bit detection — all call sites use this.
pub fn isCompressed(raw: u32) bool {
    return (raw & 0b11) != 0b11;
}

/// Decoded RV32 instruction.
pub const Instruction = struct {
    op: Opcode,
    rd: u5 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    /// Decoded immediate, sign-extended to 32 bits.
    /// For unsigned use (addresses, shifts), call immUnsigned().
    /// For CSR addresses (I-format), call csrAddr().
    /// Note: for unary I-type Zbb ops (CLZ, CTZ, CPOP, SEXT_B, SEXT_H) the imm field
    /// contains the rs2 encoding (0-5) used to distinguish them — not a meaningful operand.
    imm: i32 = 0,
    raw: u32,
    /// Original compressed opcode when this instruction was expanded from RV32C.
    /// null for 32-bit instructions.
    compressed_op: ?rv32i.rv32c.Opcode = null,

    /// Return the immediate reinterpreted as an unsigned 32-bit value.
    pub fn immUnsigned(self: Instruction) u32 {
        return @bitCast(self.imm);
    }

    /// Extract the 12-bit CSR address from the immediate field.
    pub fn csrAddr(self: Instruction) u12 {
        return @truncate(self.immUnsigned());
    }
};

test "opcode format mapping" {
    try std.testing.expectEqual(Format.R, (Opcode{ .i = .ADD }).format());
    try std.testing.expectEqual(Format.I, (Opcode{ .i = .ADDI }).format());
    try std.testing.expectEqual(Format.I, (Opcode{ .i = .LW }).format());
    try std.testing.expectEqual(Format.S, (Opcode{ .i = .SW }).format());
    try std.testing.expectEqual(Format.B, (Opcode{ .i = .BEQ }).format());
    try std.testing.expectEqual(Format.U, (Opcode{ .i = .LUI }).format());
    try std.testing.expectEqual(Format.J, (Opcode{ .i = .JAL }).format());
    try std.testing.expectEqual(Format.I, (Opcode{ .i = .JALR }).format());
    try std.testing.expectEqual(Format.I, (Opcode{ .i = .ECALL }).format());
    try std.testing.expectEqual(Format.R, (Opcode{ .m = .MUL }).format());
    try std.testing.expectEqual(Format.R, (Opcode{ .m = .DIV }).format());
}

test "opcode name" {
    try std.testing.expectEqualStrings("ADD", (Opcode{ .i = .ADD }).name());
    try std.testing.expectEqualStrings("MUL", (Opcode{ .m = .MUL }).name());
    try std.testing.expectEqualStrings("SH1ADD", (Opcode{ .zba = .SH1ADD }).name());
    try std.testing.expectEqualStrings("SEXT.B", (Opcode{ .zbb = .SEXT_B }).name());
    try std.testing.expectEqualStrings("BCLR", (Opcode{ .zbs = .BCLR }).name());
}

test "immUnsigned: negative value" {
    const inst = Instruction{ .op = .{ .i = .ADDI }, .imm = -1, .raw = 0 };
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), inst.immUnsigned());
}

test "immUnsigned: positive value" {
    const inst = Instruction{ .op = .{ .i = .ADDI }, .imm = 42, .raw = 0 };
    try std.testing.expectEqual(@as(u32, 42), inst.immUnsigned());
}

test "csrAddr: recovers 0xC00 from sign-extended immediate" {
    // CSR address 0xC00 is stored as immI sign-extended: 0xFFFFF_C00 as u32, -1024 as i32
    const inst = Instruction{ .op = .{ .csr = .CSRRS }, .imm = -1024, .raw = 0 };
    try std.testing.expectEqual(@as(u12, 0xC00), inst.csrAddr());
}

test "csrAddr: recovers 0x340 (mscratch)" {
    const inst = Instruction{ .op = .{ .csr = .CSRRW }, .imm = 0x340, .raw = 0 };
    try std.testing.expectEqual(@as(u12, 0x340), inst.csrAddr());
}
