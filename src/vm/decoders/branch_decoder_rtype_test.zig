/// R-type round-trip tests for RV32I/M/Zba/Zbb/Zbs.
const std = @import("std");
const decoder = @import("branch_decoder.zig");
const instructions = @import("../instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("../instructions/test_helpers.zig");

test "R-type round-trip: ADD" {
    try expectRoundTripR(0b0000000, 0b000, .{ .i = .ADD });
}

test "R-type round-trip: SUB" {
    try expectRoundTripR(0b0100000, 0b000, .{ .i = .SUB });
}

test "R-type round-trip: SLL" {
    try expectRoundTripR(0b0000000, 0b001, .{ .i = .SLL });
}

test "R-type round-trip: SLT" {
    try expectRoundTripR(0b0000000, 0b010, .{ .i = .SLT });
}

test "R-type round-trip: SLTU" {
    try expectRoundTripR(0b0000000, 0b011, .{ .i = .SLTU });
}

test "R-type round-trip: XOR" {
    try expectRoundTripR(0b0000000, 0b100, .{ .i = .XOR });
}

test "R-type round-trip: SRL" {
    try expectRoundTripR(0b0000000, 0b101, .{ .i = .SRL });
}

test "R-type round-trip: SRA" {
    try expectRoundTripR(0b0100000, 0b101, .{ .i = .SRA });
}

test "R-type round-trip: OR" {
    try expectRoundTripR(0b0000000, 0b110, .{ .i = .OR });
}

test "R-type round-trip: AND" {
    try expectRoundTripR(0b0000000, 0b111, .{ .i = .AND });
}

test "R-type round-trip: MUL (M-ext)" {
    try expectRoundTripR(0b0000001, 0b000, .{ .m = .MUL });
}

test "R-type round-trip: MULH (M-ext)" {
    try expectRoundTripR(0b0000001, 0b001, .{ .m = .MULH });
}

test "R-type round-trip: MULHSU (M-ext)" {
    try expectRoundTripR(0b0000001, 0b010, .{ .m = .MULHSU });
}

test "R-type round-trip: MULHU (M-ext)" {
    try expectRoundTripR(0b0000001, 0b011, .{ .m = .MULHU });
}

test "R-type round-trip: DIV (M-ext)" {
    try expectRoundTripR(0b0000001, 0b100, .{ .m = .DIV });
}

test "R-type round-trip: DIVU (M-ext)" {
    try expectRoundTripR(0b0000001, 0b101, .{ .m = .DIVU });
}

test "R-type round-trip: REM (M-ext)" {
    try expectRoundTripR(0b0000001, 0b110, .{ .m = .REM });
}

test "R-type round-trip: REMU (M-ext)" {
    try expectRoundTripR(0b0000001, 0b111, .{ .m = .REMU });
}

// --- Zba R-type round-trips ---

test "R-type round-trip: SH1ADD (Zba)" {
    try expectRoundTripR(0b0010000, 0b010, .{ .zba = .SH1ADD });
}

test "R-type round-trip: SH2ADD (Zba)" {
    try expectRoundTripR(0b0010000, 0b100, .{ .zba = .SH2ADD });
}

test "R-type round-trip: SH3ADD (Zba)" {
    try expectRoundTripR(0b0010000, 0b110, .{ .zba = .SH3ADD });
}

// --- Zbb R-type round-trips ---

test "R-type round-trip: ANDN (Zbb)" {
    try expectRoundTripR(0b0100000, 0b111, .{ .zbb = .ANDN });
}

test "R-type round-trip: ORN (Zbb)" {
    try expectRoundTripR(0b0100000, 0b110, .{ .zbb = .ORN });
}

test "R-type round-trip: XNOR (Zbb)" {
    try expectRoundTripR(0b0100000, 0b100, .{ .zbb = .XNOR });
}

test "R-type round-trip: MIN (Zbb)" {
    try expectRoundTripR(0b0000101, 0b100, .{ .zbb = .MIN });
}

test "R-type round-trip: MINU (Zbb)" {
    try expectRoundTripR(0b0000101, 0b101, .{ .zbb = .MINU });
}

test "R-type round-trip: MAX (Zbb)" {
    try expectRoundTripR(0b0000101, 0b110, .{ .zbb = .MAX });
}

test "R-type round-trip: MAXU (Zbb)" {
    try expectRoundTripR(0b0000101, 0b111, .{ .zbb = .MAXU });
}

test "R-type round-trip: ROL (Zbb)" {
    try expectRoundTripR(0b0110000, 0b001, .{ .zbb = .ROL });
}

test "R-type round-trip: ROR (Zbb)" {
    try expectRoundTripR(0b0110000, 0b101, .{ .zbb = .ROR });
}

// --- Zbs R-type round-trips ---

test "R-type round-trip: BCLR (Zbs)" {
    try expectRoundTripR(0b0100100, 0b001, .{ .zbs = .BCLR });
}

test "R-type round-trip: BEXT (Zbs)" {
    try expectRoundTripR(0b0100100, 0b101, .{ .zbs = .BEXT });
}

test "R-type round-trip: BINV (Zbs)" {
    try expectRoundTripR(0b0110100, 0b001, .{ .zbs = .BINV });
}

test "R-type round-trip: BSET (Zbs)" {
    try expectRoundTripR(0b0010100, 0b001, .{ .zbs = .BSET });
}

fn expectRoundTripR(f7: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_regs) |rs2_v| {
                const raw = h.encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
            }
        }
    }
}
