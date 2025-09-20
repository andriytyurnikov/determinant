const std = @import("std");
const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeRBase = t.encodeRBase;

// --- R-type tests ---

test "R-type: all 10 base instructions" {
    const cases = [_]struct { u3, u7, Opcode }{
        .{ 0b000, 0b0000000, .{ .i = .ADD } },
        .{ 0b000, 0b0100000, .{ .i = .SUB } },
        .{ 0b001, 0b0000000, .{ .i = .SLL } },
        .{ 0b010, 0b0000000, .{ .i = .SLT } },
        .{ 0b011, 0b0000000, .{ .i = .SLTU } },
        .{ 0b100, 0b0000000, .{ .i = .XOR } },
        .{ 0b101, 0b0000000, .{ .i = .SRL } },
        .{ 0b101, 0b0100000, .{ .i = .SRA } },
        .{ 0b110, 0b0000000, .{ .i = .OR } },
        .{ 0b111, 0b0000000, .{ .i = .AND } },
    };
    for (cases) |c| {
        try expectOp(c[2], decode(encodeRBase(c[0], c[1], 1, 2, 3)));
    }
}

test "R-type: RV32M all 8 instructions" {
    const cases = [_]struct { u3, Opcode }{
        .{ 0b000, .{ .m = .MUL } },
        .{ 0b001, .{ .m = .MULH } },
        .{ 0b010, .{ .m = .MULHSU } },
        .{ 0b011, .{ .m = .MULHU } },
        .{ 0b100, .{ .m = .DIV } },
        .{ 0b101, .{ .m = .DIVU } },
        .{ 0b110, .{ .m = .REM } },
        .{ 0b111, .{ .m = .REMU } },
    };
    for (cases) |c| {
        try expectOp(c[1], decode(encodeRBase(c[0], 0b0000001, 1, 2, 3)));
    }
}

test "R-type: Zba all 3 instructions" {
    try expectOp(.{ .zba = .SH1ADD }, decode(encodeRBase(0b010, 0b0010000, 1, 2, 3)));
    try expectOp(.{ .zba = .SH2ADD }, decode(encodeRBase(0b100, 0b0010000, 1, 2, 3)));
    try expectOp(.{ .zba = .SH3ADD }, decode(encodeRBase(0b110, 0b0010000, 1, 2, 3)));
}

test "R-type: Zbs 4 R-type instructions" {
    try expectOp(.{ .zbs = .BCLR }, decode(encodeRBase(0b001, 0b0100100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BEXT }, decode(encodeRBase(0b101, 0b0100100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BINV }, decode(encodeRBase(0b001, 0b0110100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BSET }, decode(encodeRBase(0b001, 0b0010100, 1, 2, 3)));
}

test "R-type: invalid funct7 → null" {
    try expectNull(decode(encodeRBase(0b000, 0b1111111, 0, 0, 0)));
}

// --- Zbb R-type ---

test "R-type: Zbb 9 non-rs2-dependent R-type" {
    const cases = [_]struct { u3, u7, Opcode }{
        .{ 0b111, 0b0100000, .{ .zbb = .ANDN } },
        .{ 0b110, 0b0100000, .{ .zbb = .ORN } },
        .{ 0b100, 0b0100000, .{ .zbb = .XNOR } },
        .{ 0b100, 0b0000101, .{ .zbb = .MIN } },
        .{ 0b101, 0b0000101, .{ .zbb = .MINU } },
        .{ 0b110, 0b0000101, .{ .zbb = .MAX } },
        .{ 0b111, 0b0000101, .{ .zbb = .MAXU } },
        .{ 0b001, 0b0110000, .{ .zbb = .ROL } },
        .{ 0b101, 0b0110000, .{ .zbb = .ROR } },
    };
    for (cases) |c| {
        try expectOp(c[2], decode(encodeRBase(c[0], c[1], 1, 2, 3)));
    }
}

test "R-type: Zbb ZEXT_H (rs2=0)" {
    try expectOp(.{ .zbb = .ZEXT_H }, decode(encodeRBase(0b100, 0b0000100, 1, 2, 0)));
}

test "R-type: Zbb ZEXT_H rs2≠0 → null" {
    try expectNull(decode(encodeRBase(0b100, 0b0000100, 1, 2, 1)));
    try expectNull(decode(encodeRBase(0b100, 0b0000100, 1, 2, 31)));
}
