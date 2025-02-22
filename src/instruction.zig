const std = @import("std");

pub const rv32i = @import("instruction/rv32i.zig");
pub const rv32m = @import("instruction/rv32m.zig");
pub const rv32a = @import("instruction/rv32a.zig");
pub const zicsr = @import("instruction/zicsr.zig");

/// RV32 instruction formats.
pub const Format = enum {
    R,
    I,
    S,
    B,
    U,
    J,
};

/// Tagged union opcode spanning all supported ISA extensions.
pub const Opcode = union(enum) {
    i: rv32i.Opcode,
    m: rv32m.Opcode,
    a: rv32a.Opcode,
    csr: zicsr.Opcode,

    pub fn format(self: Opcode) Format {
        return switch (self) {
            .m, .a => .R,
            .csr => .I,
            .i => |op| switch (op) {
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
        return switch (self) {
            .i => |op| @tagName(op),
            .m => |op| @tagName(op),
            .a => |op| @tagName(op),
            .csr => |op| @tagName(op),
        };
    }
};

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
}
