/// Cross-validation tests for RV32C compressed instruction expansion (Q0+Q1).
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

// ============================================================
// Quadrant 0
// ============================================================

test "cross: C.ADDI4SPN matches ADDI" {
    // C.ADDI4SPN x10, x2, 8 → ADDI x10, x2, 8
    const expanded = try rv32c.expand(0x0020);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 8, 2, 8));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADDI4SPN x9, x2, 1020" {
    const expanded = try rv32c.expand(0x1FE4);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 9, 2, 1020));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LW matches LW" {
    // C.LW x8, 0(x8) → LW x8, 0(x8)
    const expanded = try rv32c.expand(0x4000);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 8, 8, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LW with offset matches LW" {
    // C.LW x9, 4(x10) → LW x9, 4(x10)
    const expanded = try rv32c.expand(0x4144);
    const equiv = try decoder.decode(h.encodeI(0b0000011, 0b010, 9, 10, 4));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SW matches SW" {
    // C.SW x8, 0(x8) → SW x8, 0(x8)
    const expanded = try rv32c.expand(0xC000);
    const equiv = try decoder.decode(h.encodeS(0b010, 8, 8, 0));
    try expectSameSemantics(expanded, equiv);
}

// ============================================================
// Quadrant 1
// ============================================================

test "cross: C.NOP matches ADDI x0, x0, 0" {
    const expanded = try rv32c.expand(0x0001);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 0, 0, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADDI matches ADDI" {
    // C.ADDI x1, x1, 1 → ADDI x1, x1, 1
    const expanded = try rv32c.expand(0x0085);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 1, 1, 1));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADDI negative matches ADDI" {
    // C.ADDI x1, x1, -1 → ADDI x1, x1, -1
    const expanded = try rv32c.expand(0x10FD);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 1, 1, @bitCast(@as(i12, -1))));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.JAL matches JAL x1" {
    // C.JAL offset=0 → JAL x1, 0
    const expanded = try rv32c.expand(0x2001);
    const equiv = try decoder.decode(h.encodeJ(1, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LI matches ADDI rd, x0, imm" {
    // C.LI x1, 5 → ADDI x1, x0, 5
    const expanded = try rv32c.expand(0x4095);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 1, 0, 5));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LI negative matches ADDI" {
    // C.LI x1, -1 → ADDI x1, x0, -1
    const expanded = try rv32c.expand(0x50FD);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 1, 0, @bitCast(@as(i12, -1))));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADDI16SP matches ADDI x2, x2, imm" {
    // C.ADDI16SP 16 → ADDI x2, x2, 16
    const expanded = try rv32c.expand(0x6141);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 2, 2, 16));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ADDI16SP negative matches ADDI" {
    // C.ADDI16SP -16 → ADDI x2, x2, -16
    const expanded = try rv32c.expand(0x717D);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b000, 2, 2, @bitCast(@as(i12, -16))));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.LUI matches LUI" {
    // C.LUI x1, 0x1000 → LUI x1, 1
    const expanded = try rv32c.expand(0x6085);
    const equiv = try decoder.decode(h.encodeU(0b0110111, 1, 1));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SRLI matches SRLI" {
    // C.SRLI x8, 1 → SRLI x8, x8, 1
    const expanded = try rv32c.expand(0x8005);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b101, 8, 8, 1));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SRAI matches SRAI" {
    // C.SRAI x8, 1 → SRAI x8, x8, 1
    const expanded = try rv32c.expand(0x8405);
    // SRAI: funct7=0b0100000, shamt=1 → imm12 = 0b0100000_00001 = 0x401
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b101, 8, 8, 0x401));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.ANDI matches ANDI" {
    // C.ANDI x8, 3 → ANDI x8, x8, 3
    const expanded = try rv32c.expand(0x880D);
    const equiv = try decoder.decode(h.encodeI(0b0010011, 0b111, 8, 8, 3));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.SUB matches SUB" {
    // C.SUB x8, x9 → SUB x8, x8, x9
    const expanded = try rv32c.expand(0x8C05);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b000, 0b0100000, 8, 8, 9));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.XOR matches XOR" {
    const expanded = try rv32c.expand(0x8C25);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b100, 0b0000000, 8, 8, 9));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.OR matches OR" {
    const expanded = try rv32c.expand(0x8C45);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b110, 0b0000000, 8, 8, 9));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.AND matches AND" {
    const expanded = try rv32c.expand(0x8C65);
    const equiv = try decoder.decode(h.encodeR(0b0110011, 0b111, 0b0000000, 8, 8, 9));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.J matches JAL x0" {
    // C.J offset=0 → JAL x0, 0
    const expanded = try rv32c.expand(0xA001);
    const equiv = try decoder.decode(h.encodeJ(0, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.BEQZ matches BEQ rs1', x0" {
    // C.BEQZ x8, 0 → BEQ x8, x0, 0
    const expanded = try rv32c.expand(0xC001);
    const equiv = try decoder.decode(h.encodeB(0b000, 8, 0, 0));
    try expectSameSemantics(expanded, equiv);
}

test "cross: C.BNEZ matches BNE rs1', x0" {
    // C.BNEZ x8, 0 → BNE x8, x0, 0
    const expanded = try rv32c.expand(0xE001);
    const equiv = try decoder.decode(h.encodeB(0b001, 8, 0, 0));
    try expectSameSemantics(expanded, equiv);
}
