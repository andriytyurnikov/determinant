/// B-type branch round-trip tests.
const t = @import("test_helpers.zig");
const expectRoundTripB = t.expectRoundTripB;

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
