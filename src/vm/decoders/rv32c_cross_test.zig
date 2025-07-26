/// Cross-validation tests for RV32C compressed instruction expansion.
/// For each compressed instruction, verify that rv32c.expand() produces an Expanded
/// with the same fields as the equivalent 32-bit instruction decoded by decoder.decode().
const std = @import("std");
const instructions = @import("../instructions.zig");
const rv32c = instructions.rv32i.rv32c;
const Opcode = instructions.Opcode;
const Instruction = instructions.Instruction;
const decoder = @import("branch_decoder.zig");
const h = @import("../instructions/test_helpers.zig");

/// Compare expanded compressed instruction against the equivalent 32-bit decoded instruction.
/// The `raw` field will differ (16-bit vs 32-bit), so we compare only semantic fields.
fn expectSameSemantics(compressed: rv32c.Expanded, full: Instruction) !void {
    try std.testing.expectEqual(full.op, Opcode{ .i = compressed.op });
    try std.testing.expectEqual(full.rd, compressed.rd);
    try std.testing.expectEqual(full.rs1, compressed.rs1);
    try std.testing.expectEqual(full.rs2, compressed.rs2);
    try std.testing.expectEqual(full.imm, compressed.imm);
}

// Q0+Q1 tests in split file
comptime {
    _ = @import("rv32c_cross_q01_test.zig");
}

// ============================================================
// Quadrant 2
// ============================================================

test "cross: C.SLLI matches SLLI" {
    // C.SLLI x1, 1 → SLLI x1, x1, 1
    const expanded = try rv32c.expand(0x0086);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b001, 1, 1, 1));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LWSP matches LW rd, offset(x2)" {
    // C.LWSP x1, 0(x2) → LW x1, 0(x2)
    const expanded = try rv32c.expand(0x4082);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 1, 2, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LWSP with offset matches LW" {
    // C.LWSP x1, 4(x2) → LW x1, 4(x2)
    const expanded = try rv32c.expand(0x4092);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 1, 2, 4));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.JR matches JALR x0, 0(rs1)" {
    // C.JR x1 → JALR x0, 0(x1)
    const expanded = try rv32c.expand(0x8082);
    const equiv = try decoder.decode(h.encodeI(0b1100111, 0b000, 0, 1, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.MV matches ADD rd, x0, rs2" {
    // C.MV x1, x2 → ADD x1, x0, x2
    const expanded = try rv32c.expand(0x808A);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b000, 0b0000000, 1, 0, 2));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.JALR matches JALR x1, 0(rs1)" {
    // C.JALR x1 → JALR x1, 0(x1)
    const expanded = try rv32c.expand(0x9082);
    const equiv = try decoder.decode(h.encodeI(0b1100111, 0b000, 1, 1, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADD matches ADD rd, rd, rs2" {
    // C.ADD x1, x2 → ADD x1, x1, x2
    const expanded = try rv32c.expand(0x908A);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b000, 0b0000000, 1, 1, 2));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SWSP matches SW rs2, offset(x2)" {
    // C.SWSP x1, 0(x2) → SW x1, 0(x2)
    const expanded = try rv32c.expand(0xC006);
    const equiv = try decoder.decode(h.encodeS(0b010, 2, 1, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SWSP with offset matches SW" {
    // C.SWSP x1, 4(x2) → SW x1, 4(x2)
    const expanded = try rv32c.expand(0xC206);
    const equiv = try decoder.decode(h.encodeS(0b010, 2, 1, 4));
    try expectSameSemantics(expanded, equiv);
}

// ============================================================
// Max-range cross-validation
// ============================================================

test "cross: C.J large positive offset=+2046" {
    // C.J +2046 from rv32c_test max-range: 0xAFFD
    const expanded = try rv32c.expand(0xAFFD);
    const equiv = try decoder.decode(h.encodeJ(0, 2046));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.J large negative offset=-2048" {
    // C.J -2048 from rv32c_test max-range: 0xB001
    const expanded = try rv32c.expand(0xB001);
    const equiv = try decoder.decode(h.encodeJ(0, -2048));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.JAL large positive offset=+2046" {
    // C.JAL: funct3=001, same offset encoding as C.J
    // Construct halfword: take 0xAFFD and change funct3 from 101 to 001
    // 0xAFFD = 0b101_0_1111_1_1_1_111_1_01
    // Change bits[15:13] from 101 to 001 → 0b001_0_1111_1_1_1_111_1_01 = 0x2FFD
    const expanded = try rv32c.expand(0x2FFD);
    const equiv = try decoder.decode(h.encodeJ(1, 2046));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.BEQZ large positive offset=+254" {
    // C.BEQZ x8, +254: 0xCC7D from rv32c_test
    const expanded = try rv32c.expand(0xCC7D);
    const equiv = try decoder.decode(h.encodeB(0b000, 8, 0, 254));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.BNEZ large negative offset=-256" {
    // C.BNEZ x8, -256: 0xF001 from rv32c_test
    const expanded = try rv32c.expand(0xF001);
    const equiv = try decoder.decode(h.encodeB(0b001, 8, 0, -256));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LWSP max offset=252" {
    // C.LWSP x1, 252(x2): 0x50FE from rv32c_test
    const expanded = try rv32c.expand(0x50FE);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 1, 2, 252));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SWSP max offset=252" {
    // C.SWSP x1, 252(x2): 0xDF86 from rv32c_test
    const expanded = try rv32c.expand(0xDF86);
    const equiv = try decoder.decode(h.encodeS(0b010, 2, 1, 252));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LW max offset=124" {
    // C.LW x8, 124(x8): 0x5C60 from rv32c_test
    const expanded = try rv32c.expand(0x5C60);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 8, 8, 124));
    try expectSameSemantics(expanded, equiv);
}

// Note: C.EBREAK is not cross-validated via encode helpers because EBREAK is detected
// by exact raw value match (0x00100073), not by field encoding. The existing unit tests
// in rv32c_test.zig cover this case.
