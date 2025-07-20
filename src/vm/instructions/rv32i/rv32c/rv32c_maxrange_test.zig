const std = @import("std");
const rv32c = @import("rv32c.zig");
const rv32i = @import("../rv32i.zig");

fn expectExpand(half: u16, expected_op: rv32i.Opcode, expected_rd: u5, expected_rs1: u5, expected_rs2: u5, expected_imm: i32) !void {
    const exp = try rv32c.expand(half);
    try std.testing.expectEqual(expected_op, exp.op);
    try std.testing.expectEqual(expected_rd, exp.rd);
    try std.testing.expectEqual(expected_rs1, exp.rs1);
    try std.testing.expectEqual(expected_rs2, exp.rs2);
    try std.testing.expectEqual(expected_imm, exp.imm);
    try std.testing.expectEqual(@as(u32, half), exp.raw);
}

// ============================================================
// Max-range bit extraction tests
// ============================================================

test "C.ADDI4SPN max nzuimm=1020" {
    try expectExpand(0x1FE0, .ADDI, 8, 2, 0, 1020);
}

test "C.LW/SW max offset=124" {
    try expectExpand(0x5C60, .LW, 8, 8, 0, 124);
}

test "C.ADDI imm=+31" {
    try expectExpand(0x00FD, .ADDI, 1, 1, 0, 31);
}

test "C.ADDI imm=-32" {
    try expectExpand(0x1081, .ADDI, 1, 1, 0, -32);
}

test "C.SLLI/SRLI max shamt=31" {
    try expectExpand(0x00FE, .SLLI, 1, 1, 0, 31);
}

test "C.ADDI16SP imm=+496" {
    try expectExpand(0x617D, .ADDI, 2, 2, 0, 496);
}

test "C.ADDI16SP imm=-512" {
    try expectExpand(0x7101, .ADDI, 2, 2, 0, -512);
}

test "C.J max positive offset=+2046" {
    try expectExpand(0xAFFD, .JAL, 0, 0, 0, 2046);
}

test "C.J max negative offset=-2048" {
    try expectExpand(0xB001, .JAL, 0, 0, 0, -2048);
}

test "C.BEQZ max positive offset=+254" {
    try expectExpand(0xCC7D, .BEQ, 0, 8, 0, 254);
}

test "C.BNEZ max negative offset=-256" {
    try expectExpand(0xF001, .BNE, 0, 8, 0, -256);
}

test "C.LWSP max offset=252" {
    try expectExpand(0x50FE, .LW, 1, 2, 0, 252);
}

test "C.SWSP max offset=252" {
    try expectExpand(0xDF86, .SW, 0, 2, 1, 252);
}
