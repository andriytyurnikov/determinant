/// I-type + S-type + B-type round-trip tests.
const std = @import("std");
const decoder = @import("../branch.zig");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("../../instructions/test_helpers.zig");

// --- I-type round-trip ---

test "I-type round-trip: ADDI" {
    try expectRoundTripI(0b0010011, 0b000, .{ .i = .ADDI });
}

test "I-type round-trip: SLTI" {
    try expectRoundTripI(0b0010011, 0b010, .{ .i = .SLTI });
}

test "I-type round-trip: XORI" {
    try expectRoundTripI(0b0010011, 0b100, .{ .i = .XORI });
}

test "I-type round-trip: ORI" {
    try expectRoundTripI(0b0010011, 0b110, .{ .i = .ORI });
}

test "I-type round-trip: SLTIU" {
    try expectRoundTripI(0b0010011, 0b011, .{ .i = .SLTIU });
}

test "I-type round-trip: ANDI" {
    try expectRoundTripI(0b0010011, 0b111, .{ .i = .ANDI });
}

test "I-type round-trip: LB" {
    try expectRoundTripI(0b0000011, 0b000, .{ .i = .LB });
}

test "I-type round-trip: LW" {
    try expectRoundTripI(0b0000011, 0b010, .{ .i = .LW });
}

test "I-type round-trip: JALR" {
    try expectRoundTripI(0b1100111, 0b000, .{ .i = .JALR });
}

fn expectRoundTripI(opcode: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // Test various immediate values including sign-extension boundary cases
    const test_imms = [_]u12{ 0, 1, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeI(opcode, f3, rd_v, rs1_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                // Verify immediate: sign-extend u12 → i32
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- S-type round-trip ---

test "S-type round-trip: SB" {
    try expectRoundTripS(0b000, .{ .i = .SB });
}

test "S-type round-trip: SH" {
    try expectRoundTripS(0b001, .{ .i = .SH });
}

test "S-type round-trip: SW" {
    try expectRoundTripS(0b010, .{ .i = .SW });
}

fn expectRoundTripS(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u12{ 0, 1, 0x1F, 0x7E0, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeS(f3, rs1_v, rs2_v, imm12);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

// --- B-type round-trip ---

test "B-type round-trip: BEQ" {
    try expectRoundTripB(0b000, .{ .i = .BEQ });
}

test "B-type round-trip: BNE" {
    try expectRoundTripB(0b001, .{ .i = .BNE });
}

test "B-type round-trip: BLT" {
    try expectRoundTripB(0b100, .{ .i = .BLT });
}

test "B-type round-trip: BGE" {
    try expectRoundTripB(0b101, .{ .i = .BGE });
}

test "B-type round-trip: BLTU" {
    try expectRoundTripB(0b110, .{ .i = .BLTU });
}

test "B-type round-trip: BGEU" {
    try expectRoundTripB(0b111, .{ .i = .BGEU });
}

fn expectRoundTripB(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // B-type immediates have bit 0 always 0, range -4096..4094 (13-bit signed, even)
    const test_imms = [_]i13{ 0, 2, 4, -2, -4, 0x7FE, -0x1000, 0xE };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm_val| {
                const raw = h.encodeB(f3, rs1_v, rs2_v, imm_val);
                const inst = try decoder.decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = imm_val;
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}
