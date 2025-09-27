/// U-type, J-type, and JALR round-trip tests.
const std = @import("std");
const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const h = t.h;
const expectRoundTripI = t.expectRoundTripI;
const expectRoundTripU = t.expectRoundTripU;

// --- U-type ---

test "U-type round-trip: LUI" {
    try expectRoundTripU(0b0110111, .{ .i = .LUI });
}

test "U-type round-trip: AUIPC" {
    try expectRoundTripU(0b0010111, .{ .i = .AUIPC });
}

// --- J-type ---

test "J-type round-trip: JAL" {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // J-type immediates have bit 0 always 0, range ±1 MiB (21-bit signed, even)
    const test_imms = [_]i21{ 0, 2, 4, -2, -4, 0x7FE, -0x100000, 0xFFFFE };
    for (test_regs) |rd_v| {
        for (test_imms) |imm_val| {
            const raw = h.encodeJ(rd_v, imm_val);
            const inst = try decode(raw);
            try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            const expected_imm: i32 = imm_val;
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

// --- JALR ---

test "I-type round-trip: JALR" {
    try expectRoundTripI(0b1100111, 0b000, .{ .i = .JALR });
}
