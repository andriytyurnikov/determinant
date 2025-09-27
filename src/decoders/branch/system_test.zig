/// CSR and FENCE round-trip tests.
const std = @import("std");
const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectRoundTripCsr = t.expectRoundTripCsr;

// --- CSR ---

test "CSR round-trip: CSRRW" {
    try expectRoundTripCsr(0b001, .{ .csr = .CSRRW });
}

test "CSR round-trip: CSRRS" {
    try expectRoundTripCsr(0b010, .{ .csr = .CSRRS });
}

test "CSR round-trip: CSRRC" {
    try expectRoundTripCsr(0b011, .{ .csr = .CSRRC });
}

test "CSR round-trip: CSRRWI" {
    try expectRoundTripCsr(0b101, .{ .csr = .CSRRWI });
}

test "CSR round-trip: CSRRSI" {
    try expectRoundTripCsr(0b110, .{ .csr = .CSRRSI });
}

test "CSR round-trip: CSRRCI" {
    try expectRoundTripCsr(0b111, .{ .csr = .CSRRCI });
}

// --- FENCE ---

test "FENCE round-trip" {
    // Standard FENCE iorw,iorw = 0x0FF0000F
    const inst = try decode(0x0FF0000F);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
}

test "FENCE.I round-trip" {
    // opcode=0b0001111, funct3=001 (Zifencei)
    const raw: u32 = (0b001 << 12) | 0b0001111;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .FENCE_I }, inst.op);
}

test "FENCE with invalid funct3 is illegal" {
    // opcode=0b0001111, funct3=010 (undefined)
    const raw: u32 = (0b010 << 12) | 0b0001111;
    try std.testing.expectError(error.IllegalInstruction, decode(raw));
}
