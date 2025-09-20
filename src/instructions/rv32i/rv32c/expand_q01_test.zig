const std = @import("std");
const rv32c = @import("../rv32c.zig");
const rv32i = @import("../../rv32i.zig");

fn expectExpand(half: u16, expected_op: rv32i.Opcode, expected_rd: u5, expected_rs1: u5, expected_rs2: u5, expected_imm: i32) !void {
    const exp = try rv32c.expand(half);
    try std.testing.expectEqual(expected_op, exp.op);
    try std.testing.expectEqual(expected_rd, exp.rd);
    try std.testing.expectEqual(expected_rs1, exp.rs1);
    try std.testing.expectEqual(expected_rs2, exp.rs2);
    try std.testing.expectEqual(expected_imm, exp.imm);
}

// ============================================================
// Quadrant 0 tests
// ============================================================

test "C.ADDI4SPN: addi rd', x2, nzuimm" {
    try expectExpand(0x0020, .ADDI, 8, 2, 0, 8);
}

test "C.ADDI4SPN: nzuimm=0 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x0000));
}

test "C.LW: lw rd', offset(rs1')" {
    try expectExpand(0x4000, .LW, 8, 8, 0, 0);
}

test "C.LW with offset" {
    try expectExpand(0x4144, .LW, 9, 10, 0, 4);
}

test "C.SW: sw rs2', offset(rs1')" {
    try expectExpand(0xC000, .SW, 0, 8, 8, 0);
}

// ============================================================
// Quadrant 1 tests
// ============================================================

test "C.NOP" {
    try expectExpand(0x0001, .ADDI, 0, 0, 0, 0);
}

test "C.ADDI: addi rd, rd, nzimm" {
    try expectExpand(0x0085, .ADDI, 1, 1, 0, 1);
}

test "C.ADDI negative" {
    try expectExpand(0x10FD, .ADDI, 1, 1, 0, -1);
}

test "C.JAL: jal x1, offset" {
    try expectExpand(0x2001, .JAL, 1, 0, 0, 0);
}

test "C.LI: addi rd, x0, imm" {
    try expectExpand(0x4095, .ADDI, 1, 0, 0, 5);
}

test "C.LI negative" {
    try expectExpand(0x50FD, .ADDI, 1, 0, 0, -1);
}

test "C.ADDI16SP: addi x2, x2, nzimm" {
    try expectExpand(0x6141, .ADDI, 2, 2, 0, 16);
}

test "C.ADDI16SP negative" {
    try expectExpand(0x717D, .ADDI, 2, 2, 0, -16);
}

test "C.ADDI16SP: nzimm=0 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6101));
}

test "C.LUI: lui rd, nzimm" {
    try expectExpand(0x6085, .LUI, 1, 0, 0, 4096);
}

test "C.LUI negative" {
    try expectExpand(0x70FD, .LUI, 1, 0, 0, @bitCast(@as(u32, 0xFFFFF000)));
}

test "C.LUI: nzimm=0 is illegal" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6081));
}

test "C.SRLI" {
    try expectExpand(0x8005, .SRLI, 8, 8, 0, 1);
}

test "C.SRLI: shamt[5]=1 illegal on RV32" {
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x9005));
}

test "C.SRAI" {
    try expectExpand(0x8405, .SRAI, 8, 8, 0, 1);
}

test "C.ANDI" {
    try expectExpand(0x880D, .ANDI, 8, 8, 0, 3);
}

test "C.ANDI negative" {
    try expectExpand(0x987D, .ANDI, 8, 8, 0, -1);
}

test "C.SUB" {
    try expectExpand(0x8C05, .SUB, 8, 8, 9, 0);
}

test "C.XOR" {
    try expectExpand(0x8C25, .XOR, 8, 8, 9, 0);
}

test "C.OR" {
    try expectExpand(0x8C45, .OR, 8, 8, 9, 0);
}

test "C.AND" {
    try expectExpand(0x8C65, .AND, 8, 8, 9, 0);
}

test "C.J: jal x0, offset" {
    try expectExpand(0xA001, .JAL, 0, 0, 0, 0);
}

test "C.BEQZ: beq rs1', x0, offset" {
    try expectExpand(0xC001, .BEQ, 0, 8, 0, 0);
}

test "C.BNEZ: bne rs1', x0, offset" {
    try expectExpand(0xE001, .BNE, 0, 8, 0, 0);
}
