const std = @import("std");
const rv32c = @import("rv32c.zig");
const rv32i = @import("../rv32i.zig");
const instructions = @import("../../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../../decoders/branch_decoder/branch_decoder.zig");

fn expectExpand(half: u16, expected_op: rv32i.Opcode, expected_rd: u5, expected_rs1: u5, expected_rs2: u5, expected_imm: i32) !void {
    const exp = try rv32c.expand(half);
    try std.testing.expectEqual(expected_op, exp.op);
    try std.testing.expectEqual(expected_rd, exp.rd);
    try std.testing.expectEqual(expected_rs1, exp.rs1);
    try std.testing.expectEqual(expected_rs2, exp.rs2);
    try std.testing.expectEqual(expected_imm, exp.imm);
}

// ============================================================
// Quadrant 2 tests
// ============================================================

test "C.SLLI" {
    try expectExpand(0x0086, .SLLI, 1, 1, 0, 1);
}

test "C.SLLI: shamt[5]=1 illegal on RV32" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x1086));
}

test "C.LWSP: lw rd, offset(x2)" {
    try expectExpand(0x4082, .LW, 1, 2, 0, 0);
}

test "C.LWSP with offset" {
    try expectExpand(0x4092, .LW, 1, 2, 0, 4);
}

test "C.LWSP: rd=0 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x4002));
}

test "C.JR: jalr x0, 0(rs1)" {
    try expectExpand(0x8082, .JALR, 0, 1, 0, 0);
}

test "C.JR: rs1=0 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x8002));
}

test "C.MV: add rd, x0, rs2" {
    try expectExpand(0x808A, .ADD, 1, 0, 2, 0);
}

test "C.EBREAK" {
    try expectExpand(0x9002, .EBREAK, 0, 0, 0, 0);
}

test "C.JALR: jalr x1, 0(rs1)" {
    try expectExpand(0x9082, .JALR, 1, 1, 0, 0);
}

test "C.ADD: add rd, rd, rs2" {
    try expectExpand(0x908A, .ADD, 1, 1, 2, 0);
}

test "C.SWSP: sw rs2, offset(x2)" {
    try expectExpand(0xC006, .SW, 0, 2, 1, 0);
}

test "C.SWSP with offset" {
    try expectExpand(0xC206, .SW, 0, 2, 1, 4);
}

// ============================================================
// Decoder routing test
// ============================================================

test "decoder routes 16-bit instructions" {
    const inst = try decoder.decode(0x0001);
    try std.testing.expectEqual(Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
}

// ============================================================
// Reserved/illegal edge cases
// ============================================================

test "C.SRAI: shamt[5]=1 illegal on RV32" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x9405));
}

// ============================================================
// HINT forms (deliberate behavior)
// ============================================================

test "C.ADDI with nzimm=0 rd!=0 is HINT (expands to NOP-like ADDI)" {
    try expectExpand(0x0081, .ADDI, 1, 1, 0, 0);
}

test "C.LI rd=0 is HINT (expands to ADDI x0)" {
    try expectExpand(0x4015, .ADDI, 0, 0, 0, 5);
}

test "C.SLLI with shamt=0 is HINT" {
    try expectExpand(0x0082, .SLLI, 1, 1, 0, 0);
}

test "C.MV rd=0 is HINT (expands to ADD x0)" {
    try expectExpand(0x800A, .ADD, 0, 0, 2, 0);
}

test "C.ADD rd=0 is HINT (expands to ADD x0)" {
    try expectExpand(0x900A, .ADD, 0, 0, 2, 0);
}

// ============================================================
// Edge cases: shift amounts
// ============================================================

test "C.SRLI with shamt=0" {
    try expectExpand(0x8001, .SRLI, 8, 8, 0, 0);
}

test "C.SRAI with shamt=0" {
    try expectExpand(0x8401, .SRAI, 8, 8, 0, 0);
}

// ============================================================
// Q1 ALU bit[12]=1 reserved
// ============================================================

test "Q1 ALU bit[12]=1 funct2b reserved is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x9C01));
}

// ============================================================
// Invalid funct3 in Q0 and Q2
// ============================================================

test "Q0 invalid funct3=001 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x2000));
}

test "Q0 invalid funct3=011 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6000));
}

test "Q2 invalid funct3=001 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x2002));
}

test "Q2 invalid funct3=011 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6002));
}
