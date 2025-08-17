const t = @import("lut_test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeI = t.encodeI;
const encodeLoad = t.encodeLoad;
const encodeStore = t.encodeStore;
const encodeBranch = t.encodeBranch;
const encodeU = t.encodeU;
const encodeJ = t.encodeJ;
const encodeJalr = t.encodeJalr;
const encodeFence = t.encodeFence;

// --- Load/Store/Branch ---

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

// --- LUI/AUIPC/JAL/JALR/FENCE ---

test "LUI and AUIPC" {
    try expectOp(.{ .i = .LUI }, decode(encodeU(0b0110111, 1, 0)));
    try expectOp(.{ .i = .LUI }, decode(encodeU(0b0110111, 31, 0xFFFFF)));
    try expectOp(.{ .i = .AUIPC }, decode(encodeU(0b0010111, 1, 0)));
    try expectOp(.{ .i = .AUIPC }, decode(encodeU(0b0010111, 31, 0xFFFFF)));
}

test "JAL" {
    try expectOp(.{ .i = .JAL }, decode(encodeJ(1)));
    try expectOp(.{ .i = .JAL }, decode(encodeJ(31)));
}

test "JALR: funct3=0 → JALR" {
    try expectOp(.{ .i = .JALR }, decode(encodeJalr(1, 2, 0)));
    try expectOp(.{ .i = .JALR }, decode(encodeJalr(1, 2, 100)));
}

test "JALR: funct3≠0 → null" {
    try expectNull(decode(encodeI(0b1100111, 0b001, 1, 2, 0)));
    try expectNull(decode(encodeI(0b1100111, 0b111, 1, 2, 0)));
}

test "FENCE: funct3=0 → FENCE" {
    try expectOp(.{ .i = .FENCE }, decode(encodeFence()));
}

test "FENCE.I: funct3=001 → FENCE_I" {
    try expectOp(.{ .i = .FENCE_I }, decode(encodeI(0b0001111, 0b001, 0, 0, 0)));
}

test "FENCE: funct3≥2 → null" {
    try expectNull(decode(encodeI(0b0001111, 0b010, 0, 0, 0)));
    try expectNull(decode(encodeI(0b0001111, 0b111, 0, 0, 0)));
}
