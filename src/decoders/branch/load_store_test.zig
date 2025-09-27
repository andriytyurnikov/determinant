/// Load and store round-trip tests.
const t = @import("test_helpers.zig");
const expectRoundTripI = t.expectRoundTripI;
const expectRoundTripS = t.expectRoundTripS;

// --- I-type loads ---

test "I-type round-trip: LB" {
    try expectRoundTripI(0b0000011, 0b000, .{ .i = .LB });
}

test "I-type round-trip: LW" {
    try expectRoundTripI(0b0000011, 0b010, .{ .i = .LW });
}

// --- S-type stores ---

test "S-type round-trip: SB" {
    try expectRoundTripS(0b000, .{ .i = .SB });
}

test "S-type round-trip: SH" {
    try expectRoundTripS(0b001, .{ .i = .SH });
}

test "S-type round-trip: SW" {
    try expectRoundTripS(0b010, .{ .i = .SW });
}
