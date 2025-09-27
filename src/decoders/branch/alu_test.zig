/// I-type ALU round-trip tests.
const t = @import("test_helpers.zig");
const expectRoundTripI = t.expectRoundTripI;

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
