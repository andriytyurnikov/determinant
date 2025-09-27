const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeLoad = t.encodeLoad;
const encodeStore = t.encodeStore;
const encodeBranch = t.encodeBranch;

// --- Loads ---

test "Load: all 5 load instructions" {
    try expectOp(.{ .i = .LB }, decode(encodeLoad(0b000, 1, 2, 0)));
    try expectOp(.{ .i = .LH }, decode(encodeLoad(0b001, 1, 2, 0)));
    try expectOp(.{ .i = .LW }, decode(encodeLoad(0b010, 1, 2, 0)));
    try expectOp(.{ .i = .LBU }, decode(encodeLoad(0b100, 1, 2, 0)));
    try expectOp(.{ .i = .LHU }, decode(encodeLoad(0b101, 1, 2, 0)));
}

test "Load: invalid funct3 → null" {
    try expectNull(decode(encodeLoad(0b011, 1, 2, 0)));
    try expectNull(decode(encodeLoad(0b110, 1, 2, 0)));
    try expectNull(decode(encodeLoad(0b111, 1, 2, 0)));
}

// --- Stores ---

test "Store: all 3 store instructions" {
    try expectOp(.{ .i = .SB }, decode(encodeStore(0b000, 1, 2, 0)));
    try expectOp(.{ .i = .SH }, decode(encodeStore(0b001, 1, 2, 0)));
    try expectOp(.{ .i = .SW }, decode(encodeStore(0b010, 1, 2, 0)));
}

test "Store: invalid funct3 → null" {
    try expectNull(decode(encodeStore(0b011, 1, 2, 0)));
    try expectNull(decode(encodeStore(0b100, 1, 2, 0)));
    try expectNull(decode(encodeStore(0b101, 1, 2, 0)));
    try expectNull(decode(encodeStore(0b110, 1, 2, 0)));
    try expectNull(decode(encodeStore(0b111, 1, 2, 0)));
}

// --- Branches ---

test "Branch: all 6 branch instructions" {
    try expectOp(.{ .i = .BEQ }, decode(encodeBranch(0b000, 1, 2)));
    try expectOp(.{ .i = .BNE }, decode(encodeBranch(0b001, 1, 2)));
    try expectOp(.{ .i = .BLT }, decode(encodeBranch(0b100, 1, 2)));
    try expectOp(.{ .i = .BGE }, decode(encodeBranch(0b101, 1, 2)));
    try expectOp(.{ .i = .BLTU }, decode(encodeBranch(0b110, 1, 2)));
    try expectOp(.{ .i = .BGEU }, decode(encodeBranch(0b111, 1, 2)));
}

test "Branch: invalid funct3 → null" {
    try expectNull(decode(encodeBranch(0b010, 1, 2)));
    try expectNull(decode(encodeBranch(0b011, 1, 2)));
}
