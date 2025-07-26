const t = @import("lut_test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeIAlu = t.encodeIAlu;

// --- I-type ALU tests ---

test "I-type ALU: non-shift instructions" {
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 42)));
    try expectOp(.{ .i = .SLTI }, decode(encodeIAlu(0b010, 42)));
    try expectOp(.{ .i = .SLTIU }, decode(encodeIAlu(0b011, 42)));
    try expectOp(.{ .i = .XORI }, decode(encodeIAlu(0b100, 42)));
    try expectOp(.{ .i = .ORI }, decode(encodeIAlu(0b110, 42)));
    try expectOp(.{ .i = .ANDI }, decode(encodeIAlu(0b111, 42)));
}

test "I-type ALU: non-shift ignores funct7 bits" {
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b0000000_00000)));
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b1111111_11111)));
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b0100000_01010)));
}

test "I-type ALU: shifts use funct7" {
    try expectOp(.{ .i = .SLLI }, decode(encodeIAlu(0b001, 0b0000000_00101)));
    try expectOp(.{ .i = .SRLI }, decode(encodeIAlu(0b101, 0b0000000_00011)));
    try expectOp(.{ .i = .SRAI }, decode(encodeIAlu(0b101, 0b0100000_00011)));
}

test "I-type ALU: shift with invalid funct7 → null" {
    try expectNull(decode(encodeIAlu(0b001, 0b1111111_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0000001_00000)));
}

test "I-type ALU: Zbs 4 I-type instructions" {
    try expectOp(.{ .zbs = .BCLRI }, decode(encodeIAlu(0b001, 0b0100100_00101)));
    try expectOp(.{ .zbs = .BEXTI }, decode(encodeIAlu(0b101, 0b0100100_00011)));
    try expectOp(.{ .zbs = .BINVI }, decode(encodeIAlu(0b001, 0b0110100_00010)));
    try expectOp(.{ .zbs = .BSETI }, decode(encodeIAlu(0b001, 0b0010100_00111)));
}

test "I-type ALU: Zbb RORI (non-rs2-dependent)" {
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_00101)));
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_11111)));
}

test "I-type ALU: Zbb CLZ/CTZ/CPOP/SEXT_B/SEXT_H (rs2-dependent)" {
    try expectOp(.{ .zbb = .CLZ }, decode(encodeIAlu(0b001, 0b0110000_00000)));
    try expectOp(.{ .zbb = .CTZ }, decode(encodeIAlu(0b001, 0b0110000_00001)));
    try expectOp(.{ .zbb = .CPOP }, decode(encodeIAlu(0b001, 0b0110000_00010)));
    try expectOp(.{ .zbb = .SEXT_B }, decode(encodeIAlu(0b001, 0b0110000_00100)));
    try expectOp(.{ .zbb = .SEXT_H }, decode(encodeIAlu(0b001, 0b0110000_00101)));
}

test "I-type ALU: Zbb CLZ group invalid rs2 → null" {
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00011)));
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00110)));
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_11111)));
}

test "I-type ALU: Zbb ORC_B (rs2=7)" {
    try expectOp(.{ .zbb = .ORC_B }, decode(encodeIAlu(0b101, 0b0010100_00111)));
}

test "I-type ALU: Zbb ORC_B rs2≠7 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00110)));
}

test "I-type ALU: Zbb REV8 (rs2=24)" {
    try expectOp(.{ .zbb = .REV8 }, decode(encodeIAlu(0b101, 0b0110100_11000)));
}

test "I-type ALU: Zbb REV8 rs2≠24 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_11001)));
}
