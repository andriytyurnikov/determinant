/// I-type shift round-trip tests for RV32I/Zbb/Zbs.
const std = @import("std");
const decoder = @import("../branch.zig");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("../../instructions/test_helpers.zig");

// --- RV32I I-type shift round-trips ---

test "I-type shift round-trip: SRLI" {
    try expectRoundTripIShift(0b0000000, 0b101, .{ .i = .SRLI });
}

test "I-type shift round-trip: SRAI" {
    try expectRoundTripIShift(0b0100000, 0b101, .{ .i = .SRAI });
}

test "I-type shift round-trip: SLLI" {
    try expectRoundTripIShift(0b0000000, 0b001, .{ .i = .SLLI });
}

// --- Zbb I-type shift round-trips ---

test "I-type shift round-trip: CLZ (Zbb)" {
    try expectRoundTripIFixed(0b001, 0b0110000, 0, .{ .zbb = .CLZ });
}

test "I-type shift round-trip: CTZ (Zbb)" {
    try expectRoundTripIFixed(0b001, 0b0110000, 1, .{ .zbb = .CTZ });
}

test "I-type shift round-trip: CPOP (Zbb)" {
    try expectRoundTripIFixed(0b001, 0b0110000, 2, .{ .zbb = .CPOP });
}

test "I-type shift round-trip: SEXT_B (Zbb)" {
    try expectRoundTripIFixed(0b001, 0b0110000, 4, .{ .zbb = .SEXT_B });
}

test "I-type shift round-trip: SEXT_H (Zbb)" {
    try expectRoundTripIFixed(0b001, 0b0110000, 5, .{ .zbb = .SEXT_H });
}

test "I-type shift round-trip: RORI (Zbb)" {
    try expectRoundTripIShift(0b0110000, 0b101, .{ .zbb = .RORI });
}

test "I-type shift round-trip: ORC_B (Zbb)" {
    try expectRoundTripIFixed(0b101, 0b0010100, 7, .{ .zbb = .ORC_B });
}

test "I-type shift round-trip: REV8 (Zbb)" {
    try expectRoundTripIFixed(0b101, 0b0110100, 24, .{ .zbb = .REV8 });
}

// --- Zbs I-type shift round-trips ---

test "I-type shift round-trip: BCLRI (Zbs)" {
    try expectRoundTripIShift(0b0100100, 0b001, .{ .zbs = .BCLRI });
}

test "I-type shift round-trip: BEXTI (Zbs)" {
    try expectRoundTripIShift(0b0100100, 0b101, .{ .zbs = .BEXTI });
}

test "I-type shift round-trip: BINVI (Zbs)" {
    try expectRoundTripIShift(0b0110100, 0b001, .{ .zbs = .BINVI });
}

test "I-type shift round-trip: BSETI (Zbs)" {
    try expectRoundTripIShift(0b0010100, 0b001, .{ .zbs = .BSETI });
}

/// Round-trip helper for I-type shift instructions (funct7 + shamt in immediate field).
/// Tests representative shamt values (0, 1, 15, 31) across register combos.
fn expectRoundTripIShift(f7: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_shamts = [_]u5{ 0, 1, 15, 31 };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_shamts) |shamt| {
                const imm12: u12 = (@as(u12, f7) << 5) | @as(u12, shamt);
                const raw = h.encodeI(0b0010011, f3, rd_v, rs1_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(@as(i32, shamt), inst.imm);
            }
        }
    }
}

/// Round-trip helper for I-type instructions with a fixed rs2/shamt field.
/// Used for Zbb unary ops (CLZ, CTZ, CPOP, SEXT_B, SEXT_H, ORC_B, REV8).
fn expectRoundTripIFixed(f3: u3, f7: u7, fixed_rs2: u5, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const imm12: u12 = (@as(u12, f7) << 5) | @as(u12, fixed_rs2);
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            const raw = h.encodeI(0b0010011, f3, rd_v, rs1_v, imm12);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(expected_op, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            try std.testing.expectEqual(rs1_v, inst.rs1);
        }
    }
}
