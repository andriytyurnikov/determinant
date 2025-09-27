const t = @import("test_helpers.zig");
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeI = t.encodeI;
const encodeU = t.encodeU;
const encodeJ = t.encodeJ;
const encodeJalr = t.encodeJalr;

// --- LUI/AUIPC ---

test "LUI and AUIPC" {
    try expectOp(.{ .i = .LUI }, decode(encodeU(0b0110111, 1, 0)));
    try expectOp(.{ .i = .LUI }, decode(encodeU(0b0110111, 31, 0xFFFFF)));
    try expectOp(.{ .i = .AUIPC }, decode(encodeU(0b0010111, 1, 0)));
    try expectOp(.{ .i = .AUIPC }, decode(encodeU(0b0010111, 31, 0xFFFFF)));
}

// --- JAL ---

test "JAL" {
    try expectOp(.{ .i = .JAL }, decode(encodeJ(1)));
    try expectOp(.{ .i = .JAL }, decode(encodeJ(31)));
}

// --- JALR ---

test "JALR: funct3=0 → JALR" {
    try expectOp(.{ .i = .JALR }, decode(encodeJalr(1, 2, 0)));
    try expectOp(.{ .i = .JALR }, decode(encodeJalr(1, 2, 100)));
}

test "JALR: funct3≠0 → null" {
    try expectNull(decode(encodeI(0b1100111, 0b001, 1, 2, 0)));
    try expectNull(decode(encodeI(0b1100111, 0b111, 1, 2, 0)));
}
