const std = @import("std");

pub const rv32i = @import("instruction/rv32i.zig");
pub const rv32m = @import("instruction/rv32m.zig");
pub const rv32a = @import("instruction/rv32a.zig");
pub const zicsr = @import("instruction/zicsr.zig");
pub const zba = @import("instruction/zba.zig");
pub const zbb = @import("instruction/zbb.zig");
pub const zbs = @import("instruction/zbs.zig");

pub const Format = @import("instruction/format.zig").Format;

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
pub fn isCompressed(raw: u32) bool {
    return (raw & 0b11) != 0b11;
}

/// Decoded RV32 instruction.
pub const Instruction = struct {
    op: Opcode,
    rd: u5 = 0,
    rs1: u5 = 0,
    rs2: u5 = 0,
    imm: i32 = 0,
    raw: u32,
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
