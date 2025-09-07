//! Shared expandCompressed(): wraps rv32c.Expanded into a full Instruction (used by both decoders).

const std = @import("std");
const instructions = @import("../instructions.zig");
const rv32c = instructions.rv32i.rv32c;
const Instruction = instructions.Instruction;

/// Expand a 16-bit compressed instruction (zero-extended to u32) into a full Instruction.
/// Shared by both branch_decoder and lut_decoder — single source of truth for RV32C expansion.
pub fn expandCompressed(raw: u32) error{IllegalInstruction}!Instruction {
    const exp = try rv32c.expand(@truncate(raw));
    return .{
        .op = .{ .i = exp.op },
        .rd = exp.rd,
        .rs1 = exp.rs1,
        .rs2 = exp.rs2,
        .imm = exp.imm,
        .raw = raw,
        .compressed_op = exp.compressed_op,
    };
}

test "expandCompressed: C.NOP sets compressed_op" {
    // C.NOP = C.ADDI x0, 0 → encoding: 0x0001
    const inst = try expandCompressed(0x0001);
    try std.testing.expectEqual(instructions.Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(rv32c.Opcode.C_ADDI, inst.compressed_op.?);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

test "expandCompressed: C.LW sets compressed_op" {
    // C.LW x8, 0(x8) → funct3=010, quadrant 00
    // Encoding: 010 000 000 00 000 00 = 0x4000
    const inst = try expandCompressed(0x4000);
    try std.testing.expectEqual(instructions.Opcode{ .i = .LW }, inst.op);
    try std.testing.expectEqual(rv32c.Opcode.C_LW, inst.compressed_op.?);
}

test "expandCompressed: 32-bit instruction encoding rejected" {
    // bits [1:0] = 0b11 means 32-bit, not compressed — rv32c.decode returns IllegalInstruction
    try std.testing.expectError(error.IllegalInstruction, expandCompressed(0x00000033));
}
