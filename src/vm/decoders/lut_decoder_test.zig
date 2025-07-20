const std = @import("std");
const t = @import("lut_test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const expectOp = t.expectOp;
const expectNull = t.expectNull;
const encodeRBase = t.encodeRBase;
const encodeIAlu = t.encodeIAlu;
const encodeI = t.encodeI;
const encodeLoad = t.encodeLoad;
const encodeStore = t.encodeStore;
const encodeBranch = t.encodeBranch;
const encodeU = t.encodeU;
const encodeJ = t.encodeJ;
const encodeJalr = t.encodeJalr;
const encodeFence = t.encodeFence;
const encodeAtomic = t.encodeAtomic;
const encodeSystem = t.encodeSystem;

// --- R-type tests ---

test "R-type: all 10 base instructions" {
    const cases = [_]struct { u3, u7, Opcode }{
        .{ 0b000, 0b0000000, .{ .i = .ADD } },
        .{ 0b000, 0b0100000, .{ .i = .SUB } },
        .{ 0b001, 0b0000000, .{ .i = .SLL } },
        .{ 0b010, 0b0000000, .{ .i = .SLT } },
        .{ 0b011, 0b0000000, .{ .i = .SLTU } },
        .{ 0b100, 0b0000000, .{ .i = .XOR } },
        .{ 0b101, 0b0000000, .{ .i = .SRL } },
        .{ 0b101, 0b0100000, .{ .i = .SRA } },
        .{ 0b110, 0b0000000, .{ .i = .OR } },
        .{ 0b111, 0b0000000, .{ .i = .AND } },
    };
    for (cases) |c| {
        try expectOp(c[2], decode(encodeRBase(c[0], c[1], 1, 2, 3)));
    }
}

test "R-type: RV32M all 8 instructions" {
    const cases = [_]struct { u3, Opcode }{
        .{ 0b000, .{ .m = .MUL } },
        .{ 0b001, .{ .m = .MULH } },
        .{ 0b010, .{ .m = .MULHSU } },
        .{ 0b011, .{ .m = .MULHU } },
        .{ 0b100, .{ .m = .DIV } },
        .{ 0b101, .{ .m = .DIVU } },
        .{ 0b110, .{ .m = .REM } },
        .{ 0b111, .{ .m = .REMU } },
    };
    for (cases) |c| {
        try expectOp(c[1], decode(encodeRBase(c[0], 0b0000001, 1, 2, 3)));
    }
}

test "R-type: Zba all 3 instructions" {
    try expectOp(.{ .zba = .SH1ADD }, decode(encodeRBase(0b010, 0b0010000, 1, 2, 3)));
    try expectOp(.{ .zba = .SH2ADD }, decode(encodeRBase(0b100, 0b0010000, 1, 2, 3)));
    try expectOp(.{ .zba = .SH3ADD }, decode(encodeRBase(0b110, 0b0010000, 1, 2, 3)));
}

test "R-type: Zbs 4 R-type instructions" {
    try expectOp(.{ .zbs = .BCLR }, decode(encodeRBase(0b001, 0b0100100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BEXT }, decode(encodeRBase(0b101, 0b0100100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BINV }, decode(encodeRBase(0b001, 0b0110100, 1, 2, 3)));
    try expectOp(.{ .zbs = .BSET }, decode(encodeRBase(0b001, 0b0010100, 1, 2, 3)));
}

test "R-type: invalid funct7 → null" {
    try expectNull(decode(encodeRBase(0b000, 0b1111111, 0, 0, 0)));
}

// --- Zbb R-type ---

test "R-type: Zbb 9 non-rs2-dependent R-type" {
    const cases = [_]struct { u3, u7, Opcode }{
        .{ 0b111, 0b0100000, .{ .zbb = .ANDN } },
        .{ 0b110, 0b0100000, .{ .zbb = .ORN } },
        .{ 0b100, 0b0100000, .{ .zbb = .XNOR } },
        .{ 0b100, 0b0000101, .{ .zbb = .MIN } },
        .{ 0b101, 0b0000101, .{ .zbb = .MINU } },
        .{ 0b110, 0b0000101, .{ .zbb = .MAX } },
        .{ 0b111, 0b0000101, .{ .zbb = .MAXU } },
        .{ 0b001, 0b0110000, .{ .zbb = .ROL } },
        .{ 0b101, 0b0110000, .{ .zbb = .ROR } },
    };
    for (cases) |c| {
        try expectOp(c[2], decode(encodeRBase(c[0], c[1], 1, 2, 3)));
    }
}

test "R-type: Zbb ZEXT_H (rs2=0)" {
    try expectOp(.{ .zbb = .ZEXT_H }, decode(encodeRBase(0b100, 0b0000100, 1, 2, 0)));
}

test "R-type: Zbb ZEXT_H rs2≠0 → null" {
    try expectNull(decode(encodeRBase(0b100, 0b0000100, 1, 2, 1)));
    try expectNull(decode(encodeRBase(0b100, 0b0000100, 1, 2, 31)));
}

// --- I-type ALU tests ---

test "I-type ALU: non-shift instructions" {
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 42)));
    try expectOp(.{ .i = .SLTI }, decode(encodeIAlu(0b010, 42)));
    try expectOp(.{ .i = .SLTIU }, decode(encodeIAlu(0b011, 42)));
    try expectOp(.{ .i = .XORI }, decode(encodeIAlu(0b100, 42)));
    try expectOp(.{ .i = .ORI }, decode(encodeIAlu(0b110, 42)));
    try expectOp(.{ .i = .ANDI }, decode(encodeIAlu(0b111, 42)));
}

test "I-type ALU: non-shift ignores funct7 bits" {
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b0000000_00000)));
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b1111111_11111)));
    try expectOp(.{ .i = .ADDI }, decode(encodeIAlu(0b000, 0b0100000_01010)));
}

test "I-type ALU: shifts use funct7" {
    try expectOp(.{ .i = .SLLI }, decode(encodeIAlu(0b001, 0b0000000_00101)));
    try expectOp(.{ .i = .SRLI }, decode(encodeIAlu(0b101, 0b0000000_00011)));
    try expectOp(.{ .i = .SRAI }, decode(encodeIAlu(0b101, 0b0100000_00011)));
}

test "I-type ALU: shift with invalid funct7 → null" {
    try expectNull(decode(encodeIAlu(0b001, 0b1111111_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0000001_00000)));
}

test "I-type ALU: Zbs 4 I-type instructions" {
    try expectOp(.{ .zbs = .BCLRI }, decode(encodeIAlu(0b001, 0b0100100_00101)));
    try expectOp(.{ .zbs = .BEXTI }, decode(encodeIAlu(0b101, 0b0100100_00011)));
    try expectOp(.{ .zbs = .BINVI }, decode(encodeIAlu(0b001, 0b0110100_00010)));
    try expectOp(.{ .zbs = .BSETI }, decode(encodeIAlu(0b001, 0b0010100_00111)));
}

test "I-type ALU: Zbb RORI (non-rs2-dependent)" {
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_00101)));
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_11111)));
}

test "I-type ALU: Zbb CLZ/CTZ/CPOP/SEXT_B/SEXT_H (rs2-dependent)" {
    try expectOp(.{ .zbb = .CLZ }, decode(encodeIAlu(0b001, 0b0110000_00000)));
    try expectOp(.{ .zbb = .CTZ }, decode(encodeIAlu(0b001, 0b0110000_00001)));
    try expectOp(.{ .zbb = .CPOP }, decode(encodeIAlu(0b001, 0b0110000_00010)));
    try expectOp(.{ .zbb = .SEXT_B }, decode(encodeIAlu(0b001, 0b0110000_00100)));
    try expectOp(.{ .zbb = .SEXT_H }, decode(encodeIAlu(0b001, 0b0110000_00101)));
}

test "I-type ALU: Zbb CLZ group invalid rs2 → null" {
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00011)));
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00110)));
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_11111)));
}

test "I-type ALU: Zbb ORC_B (rs2=7)" {
    try expectOp(.{ .zbb = .ORC_B }, decode(encodeIAlu(0b101, 0b0010100_00111)));
}

test "I-type ALU: Zbb ORC_B rs2≠7 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00110)));
}

test "I-type ALU: Zbb REV8 (rs2=24)" {
    try expectOp(.{ .zbb = .REV8 }, decode(encodeIAlu(0b101, 0b0110100_11000)));
}

test "I-type ALU: Zbb REV8 rs2≠24 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_00000)));
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_11001)));
}

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

test "FENCE: funct3≠0 → null" {
    try expectNull(decode(encodeI(0b0001111, 0b001, 0, 0, 0)));
    try expectNull(decode(encodeI(0b0001111, 0b111, 0, 0, 0)));
}

// --- Atomic ---

test "Atomic: all 11 instructions" {
    const cases = [_]struct { u5, Opcode }{
        .{ 0b00010, .{ .a = .LR_W } },
        .{ 0b00011, .{ .a = .SC_W } },
        .{ 0b00001, .{ .a = .AMOSWAP_W } },
        .{ 0b00000, .{ .a = .AMOADD_W } },
        .{ 0b00100, .{ .a = .AMOXOR_W } },
        .{ 0b01100, .{ .a = .AMOAND_W } },
        .{ 0b01000, .{ .a = .AMOOR_W } },
        .{ 0b10000, .{ .a = .AMOMIN_W } },
        .{ 0b10100, .{ .a = .AMOMAX_W } },
        .{ 0b11000, .{ .a = .AMOMINU_W } },
        .{ 0b11100, .{ .a = .AMOMAXU_W } },
    };
    for (cases) |c| {
        try expectOp(c[1], decode(encodeAtomic(c[0], 1, 2, 3)));
    }
}

test "Atomic: invalid funct5 → null" {
    try expectNull(decode(encodeAtomic(0b11111, 1, 2, 3)));
    try expectNull(decode(encodeAtomic(0b01010, 1, 2, 3)));
}

test "Atomic: funct3≠010 → null" {
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 0b000) << 12) |
        (@as(u32, 1) << 15) |
        (@as(u32, 2) << 20);
    try expectNull(decode(raw));
}

// --- System ---

test "System: ECALL and EBREAK" {
    try expectOp(.{ .i = .ECALL }, decode(encodeSystem(0b000, 0, 0, 0x000)));
    try expectOp(.{ .i = .EBREAK }, decode(encodeSystem(0b000, 0, 0, 0x001)));
}

test "System: invalid funct12 with funct3=0 → null" {
    try expectNull(decode(encodeSystem(0b000, 0, 0, 0x002)));
    try expectNull(decode(encodeSystem(0b000, 0, 0, 0xFFF)));
}

test "System: CSR all 6 instructions" {
    try expectOp(.{ .csr = .CSRRW }, decode(encodeSystem(0b001, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRS }, decode(encodeSystem(0b010, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRC }, decode(encodeSystem(0b011, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRWI }, decode(encodeSystem(0b101, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRSI }, decode(encodeSystem(0b110, 1, 2, 0x300)));
    try expectOp(.{ .csr = .CSRRCI }, decode(encodeSystem(0b111, 1, 2, 0x300)));
}

test "System: funct3=100 → null" {
    try expectNull(decode(encodeSystem(0b100, 1, 2, 0x300)));
}

// --- Misc ---

test "unknown opcode[6:0] → null" {
    try expectNull(decode(0b1111111));
    try expectNull(decode(0b0000000));
    try expectNull(decode(0b1010101));
}

test "tables are comptime-evaluable" {
    comptime {
        std.debug.assert(decode(encodeRBase(0b000, 0b0000000, 1, 2, 3)) != null);
        std.debug.assert(decode(encodeIAlu(0b000, 100)) != null);
        std.debug.assert(decode(encodeIAlu(0b101, 0b0100000_00011)) != null);
        std.debug.assert(decode(0b1111111) == null);
    }
}
