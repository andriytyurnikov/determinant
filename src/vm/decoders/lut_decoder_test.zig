const std = @import("std");
const lut = @import("lut_decoder.zig");
const instructions = @import("../instructions.zig");
const Opcode = instructions.Opcode;
const decode = lut.decode;

// --- Instruction encoding helpers ---

fn encodeR(comptime opcode_bits: u7, f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

fn encodeRBase(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
}

fn encodeIAlu(f3: u3, imm12: u12) u32 {
    return @as(u32, 0b0010011) |
        (@as(u32, f3) << 12) |
        (@as(u32, imm12) << 20);
}

fn encodeI(comptime opcode_bits: u7, f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, imm12) << 20);
}

fn encodeLoad(f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b0000011, f3, rd_v, rs1_v, imm12);
}

fn encodeStore(f3: u3, rs1_v: u5, rs2_v: u5, imm: u12) u32 {
    const imm_4_0: u5 = @truncate(imm);
    const imm_11_5: u7 = @truncate(imm >> 5);
    return @as(u32, 0b0100011) |
        (@as(u32, imm_4_0) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, imm_11_5) << 25);
}

fn encodeBranch(f3: u3, rs1_v: u5, rs2_v: u5) u32 {
    // Encode a minimal branch (imm=0 is fine for opcode identification)
    return @as(u32, 0b1100011) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20);
}

fn encodeBranchFull(f3: u3, rs1_v: u5, rs2_v: u5, imm: i13) u32 {
    const uimm: u13 = @bitCast(imm);
    const imm_12: u32 = (@as(u32, uimm) >> 12) & 1;
    const imm_11: u32 = (@as(u32, uimm) >> 11) & 1;
    const imm_10_5: u32 = (@as(u32, uimm) >> 5) & 0x3F;
    const imm_4_1: u32 = (@as(u32, uimm) >> 1) & 0xF;
    return @as(u32, 0b1100011) |
        (imm_11 << 7) |
        (imm_4_1 << 8) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (imm_10_5 << 25) |
        (imm_12 << 31);
}

fn encodeU(comptime opcode_bits: u7, rd_v: u5, imm20: u20) u32 {
    return @as(u32, opcode_bits) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, imm20) << 12);
}

fn encodeJ(rd_v: u5) u32 {
    // JAL with imm=0 (fine for opcode identification)
    return @as(u32, 0b1101111) |
        (@as(u32, rd_v) << 7);
}

fn encodeJFull(rd_v: u5, imm: i21) u32 {
    const uimm: u21 = @bitCast(imm);
    const imm_20: u32 = (@as(u32, uimm) >> 20) & 1;
    const imm_19_12: u32 = (@as(u32, uimm) >> 12) & 0xFF;
    const imm_11: u32 = (@as(u32, uimm) >> 11) & 1;
    const imm_10_1: u32 = (@as(u32, uimm) >> 1) & 0x3FF;
    return @as(u32, 0b1101111) |
        (@as(u32, rd_v) << 7) |
        (imm_19_12 << 12) |
        (imm_11 << 20) |
        (imm_10_1 << 21) |
        (imm_20 << 31);
}

fn encodeJalr(rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b1100111, 0b000, rd_v, rs1_v, imm12);
}

fn encodeFence() u32 {
    return @as(u32, 0b0001111);
}

fn encodeAtomic(f5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    // funct3=010 (word), aq=0, rl=0
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f5) << 27);
}

fn encodeAtomicFull(f5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5, aq: u1, rl: u1) u32 {
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, rl) << 25) |
        (@as(u32, aq) << 26) |
        (@as(u32, f5) << 27);
}

fn encodeSystem(f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return encodeI(0b1110011, f3, rd_v, rs1_v, imm12);
}

// --- Helpers ---

fn expectOp(expected: Opcode, actual: ?Opcode) !void {
    try std.testing.expect(actual != null);
    try std.testing.expectEqual(expected, actual.?);
}

fn expectNull(actual: ?Opcode) !void {
    try std.testing.expect(actual == null);
}

// --- Tests ---

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

test "I-type ALU: Zbs 4 I-type instructions" {
    // BCLRI: funct3=001, funct7=0b0100100
    try expectOp(.{ .zbs = .BCLRI }, decode(encodeIAlu(0b001, 0b0100100_00101)));
    // BEXTI: funct3=101, funct7=0b0100100
    try expectOp(.{ .zbs = .BEXTI }, decode(encodeIAlu(0b101, 0b0100100_00011)));
    // BINVI: funct3=001, funct7=0b0110100
    try expectOp(.{ .zbs = .BINVI }, decode(encodeIAlu(0b001, 0b0110100_00010)));
    // BSETI: funct3=001, funct7=0b0010100
    try expectOp(.{ .zbs = .BSETI }, decode(encodeIAlu(0b001, 0b0010100_00111)));
}

test "R-type: invalid funct7 → null" {
    try expectNull(decode(encodeRBase(0b000, 0b1111111, 0, 0, 0)));
}

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

test "unknown opcode[6:0] → null" {
    try expectNull(decode(0b1111111));
    try expectNull(decode(0b0000000));
    try expectNull(decode(0b1010101));
}

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
    // Encode JALR opcode with non-zero funct3
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
    // Encode atomic opcode but with funct3=000 instead of 010
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 0b000) << 12) | // wrong funct3
        (@as(u32, 1) << 15) |
        (@as(u32, 2) << 20);
    try expectNull(decode(raw));
}

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

// --- Zbb tests ---

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

test "I-type ALU: Zbb RORI (non-rs2-dependent)" {
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_00101)));
    try expectOp(.{ .zbb = .RORI }, decode(encodeIAlu(0b101, 0b0110000_11111)));
}

test "I-type ALU: Zbb CLZ/CTZ/CPOP/SEXT_B/SEXT_H (rs2-dependent)" {
    // funct3=001, funct7=0b0110000, rs2 selects the opcode
    try expectOp(.{ .zbb = .CLZ }, decode(encodeIAlu(0b001, 0b0110000_00000)));
    try expectOp(.{ .zbb = .CTZ }, decode(encodeIAlu(0b001, 0b0110000_00001)));
    try expectOp(.{ .zbb = .CPOP }, decode(encodeIAlu(0b001, 0b0110000_00010)));
    try expectOp(.{ .zbb = .SEXT_B }, decode(encodeIAlu(0b001, 0b0110000_00100)));
    try expectOp(.{ .zbb = .SEXT_H }, decode(encodeIAlu(0b001, 0b0110000_00101)));
}

test "I-type ALU: Zbb CLZ group invalid rs2 → null" {
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00011))); // rs2=3
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_00110))); // rs2=6
    try expectNull(decode(encodeIAlu(0b001, 0b0110000_11111))); // rs2=31
}

test "I-type ALU: Zbb ORC_B (rs2=7)" {
    try expectOp(.{ .zbb = .ORC_B }, decode(encodeIAlu(0b101, 0b0010100_00111)));
}

test "I-type ALU: Zbb ORC_B rs2≠7 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00000))); // rs2=0
    try expectNull(decode(encodeIAlu(0b101, 0b0010100_00110))); // rs2=6
}

test "I-type ALU: Zbb REV8 (rs2=24)" {
    try expectOp(.{ .zbb = .REV8 }, decode(encodeIAlu(0b101, 0b0110100_11000)));
}

test "I-type ALU: Zbb REV8 rs2≠24 → null" {
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_00000))); // rs2=0
    try expectNull(decode(encodeIAlu(0b101, 0b0110100_11001))); // rs2=25
}

test "tables are comptime-evaluable" {
    comptime {
        std.debug.assert(decode(encodeRBase(0b000, 0b0000000, 1, 2, 3)) != null);
        std.debug.assert(decode(encodeIAlu(0b000, 100)) != null);
        std.debug.assert(decode(encodeIAlu(0b101, 0b0100000_00011)) != null);
        std.debug.assert(decode(0b1111111) == null);
    }
}

// --- Conformance: LUT decodeInstruction matches decoder.decode ---

const decoder = @import("branch_decoder.zig");
const decodeInstruction = lut.decodeInstruction;

fn assertConformance(raw: u32) !void {
    const ref = decoder.decode(raw) catch |e| {
        // Reference decoder rejects it — LUT must also reject it
        try std.testing.expectError(e, decodeInstruction(raw));
        return;
    };
    const got = decodeInstruction(raw) catch |e| {
        std.debug.print("LUT rejected 0x{X:0>8} with {}, but reference decoded as {s}\n", .{ raw, e, ref.op.name() });
        return error.TestUnexpectedResult;
    };
    // Compare all fields
    try std.testing.expectEqual(ref.op, got.op);
    try std.testing.expectEqual(ref.rd, got.rd);
    try std.testing.expectEqual(ref.rs1, got.rs1);
    try std.testing.expectEqual(ref.rs2, got.rs2);
    try std.testing.expectEqual(ref.imm, got.imm);
}

test "conformance: R-type (RV32I + RV32M + Zba + Zbb + Zbs)" {
    // RV32I R-type
    const i_cases = [_]struct { u3, u7 }{
        .{ 0b000, 0b0000000 }, .{ 0b000, 0b0100000 }, .{ 0b001, 0b0000000 },
        .{ 0b010, 0b0000000 }, .{ 0b011, 0b0000000 }, .{ 0b100, 0b0000000 },
        .{ 0b101, 0b0000000 }, .{ 0b101, 0b0100000 }, .{ 0b110, 0b0000000 },
        .{ 0b111, 0b0000000 },
    };
    for (i_cases) |c| try assertConformance(encodeRBase(c[0], c[1], 3, 5, 7));
    // RV32M
    for (0..8) |f3| try assertConformance(encodeRBase(@truncate(f3), 0b0000001, 1, 2, 3));
    // Zba
    try assertConformance(encodeRBase(0b010, 0b0010000, 1, 2, 3));
    try assertConformance(encodeRBase(0b100, 0b0010000, 1, 2, 3));
    try assertConformance(encodeRBase(0b110, 0b0010000, 1, 2, 3));
    // Zbb R-type
    try assertConformance(encodeRBase(0b111, 0b0100000, 1, 2, 3)); // ANDN
    try assertConformance(encodeRBase(0b110, 0b0100000, 1, 2, 3)); // ORN
    try assertConformance(encodeRBase(0b100, 0b0100000, 1, 2, 3)); // XNOR
    try assertConformance(encodeRBase(0b100, 0b0000101, 1, 2, 3)); // MIN
    try assertConformance(encodeRBase(0b101, 0b0000101, 1, 2, 3)); // MINU
    try assertConformance(encodeRBase(0b110, 0b0000101, 1, 2, 3)); // MAX
    try assertConformance(encodeRBase(0b111, 0b0000101, 1, 2, 3)); // MAXU
    try assertConformance(encodeRBase(0b001, 0b0110000, 1, 2, 3)); // ROL
    try assertConformance(encodeRBase(0b101, 0b0110000, 1, 2, 3)); // ROR
    try assertConformance(encodeRBase(0b100, 0b0000100, 1, 2, 0)); // ZEXT_H
    // Zbs R-type
    try assertConformance(encodeRBase(0b001, 0b0100100, 1, 2, 3));
    try assertConformance(encodeRBase(0b101, 0b0100100, 1, 2, 3));
    try assertConformance(encodeRBase(0b001, 0b0110100, 1, 2, 3));
    try assertConformance(encodeRBase(0b001, 0b0010100, 1, 2, 3));
}

test "conformance: I-type ALU (RV32I + Zbb + Zbs)" {
    // RV32I non-shifts (with non-zero rd/rs1 via encodeI)
    try assertConformance(encodeI(0b0010011, 0b000, 5, 10, 42)); // ADDI
    try assertConformance(encodeI(0b0010011, 0b010, 5, 10, 42)); // SLTI
    try assertConformance(encodeI(0b0010011, 0b011, 5, 10, 42)); // SLTIU
    try assertConformance(encodeI(0b0010011, 0b100, 5, 10, 42)); // XORI
    try assertConformance(encodeI(0b0010011, 0b110, 5, 10, 42)); // ORI
    try assertConformance(encodeI(0b0010011, 0b111, 5, 10, 42)); // ANDI
    // RV32I shifts (with non-zero rd/rs1)
    try assertConformance(encodeI(0b0010011, 0b001, 3, 7, 0b0000000_00101)); // SLLI
    try assertConformance(encodeI(0b0010011, 0b101, 3, 7, 0b0000000_00011)); // SRLI
    try assertConformance(encodeI(0b0010011, 0b101, 3, 7, 0b0100000_00011)); // SRAI
    // Zbb shifts (with non-zero rd/rs1)
    try assertConformance(encodeI(0b0010011, 0b101, 4, 8, 0b0110000_00101)); // RORI
    try assertConformance(encodeI(0b0010011, 0b001, 4, 8, 0b0110000_00000)); // CLZ
    try assertConformance(encodeI(0b0010011, 0b001, 4, 8, 0b0110000_00001)); // CTZ
    try assertConformance(encodeI(0b0010011, 0b001, 4, 8, 0b0110000_00010)); // CPOP
    try assertConformance(encodeI(0b0010011, 0b001, 4, 8, 0b0110000_00100)); // SEXT_B
    try assertConformance(encodeI(0b0010011, 0b001, 4, 8, 0b0110000_00101)); // SEXT_H
    try assertConformance(encodeI(0b0010011, 0b101, 4, 8, 0b0010100_00111)); // ORC_B
    try assertConformance(encodeI(0b0010011, 0b101, 4, 8, 0b0110100_11000)); // REV8
    // Zbs shifts (with non-zero rd/rs1)
    try assertConformance(encodeI(0b0010011, 0b001, 6, 12, 0b0100100_00101)); // BCLRI
    try assertConformance(encodeI(0b0010011, 0b101, 6, 12, 0b0100100_00011)); // BEXTI
    try assertConformance(encodeI(0b0010011, 0b001, 6, 12, 0b0110100_00010)); // BINVI
    try assertConformance(encodeI(0b0010011, 0b001, 6, 12, 0b0010100_00111)); // BSETI
}

test "conformance: Load/Store/Branch" {
    // Loads
    try assertConformance(encodeLoad(0b000, 1, 2, 100)); // LB
    try assertConformance(encodeLoad(0b001, 1, 2, 100)); // LH
    try assertConformance(encodeLoad(0b010, 1, 2, 100)); // LW
    try assertConformance(encodeLoad(0b100, 1, 2, 100)); // LBU
    try assertConformance(encodeLoad(0b101, 1, 2, 100)); // LHU
    // Stores
    try assertConformance(encodeStore(0b000, 1, 2, 50)); // SB
    try assertConformance(encodeStore(0b001, 1, 2, 50)); // SH
    try assertConformance(encodeStore(0b010, 1, 2, 50)); // SW
    // Branches
    try assertConformance(encodeBranch(0b000, 1, 2)); // BEQ
    try assertConformance(encodeBranch(0b001, 1, 2)); // BNE
    try assertConformance(encodeBranch(0b100, 1, 2)); // BLT
    try assertConformance(encodeBranch(0b101, 1, 2)); // BGE
    try assertConformance(encodeBranch(0b110, 1, 2)); // BLTU
    try assertConformance(encodeBranch(0b111, 1, 2)); // BGEU
}

test "conformance: LUI/AUIPC/JAL/JALR/FENCE" {
    try assertConformance(encodeU(0b0110111, 5, 0xABCDE)); // LUI
    try assertConformance(encodeU(0b0010111, 5, 0xABCDE)); // AUIPC
    try assertConformance(encodeJ(5)); // JAL
    try assertConformance(encodeJalr(5, 10, 200)); // JALR
    try assertConformance(encodeFence()); // FENCE
}

test "conformance: Atomics" {
    const funct5s = [_]u5{ 0b00010, 0b00011, 0b00001, 0b00000, 0b00100, 0b01100, 0b01000, 0b10000, 0b10100, 0b11000, 0b11100 };
    for (funct5s) |f5| try assertConformance(encodeAtomic(f5, 1, 2, 3));
}

test "conformance: System/CSR" {
    try assertConformance(encodeSystem(0b000, 0, 0, 0x000)); // ECALL
    try assertConformance(encodeSystem(0b000, 0, 0, 0x001)); // EBREAK
    try assertConformance(encodeSystem(0b001, 1, 2, 0x300)); // CSRRW
    try assertConformance(encodeSystem(0b010, 1, 2, 0x300)); // CSRRS
    try assertConformance(encodeSystem(0b011, 1, 2, 0x300)); // CSRRC
    try assertConformance(encodeSystem(0b101, 1, 2, 0x300)); // CSRRWI
    try assertConformance(encodeSystem(0b110, 1, 2, 0x300)); // CSRRSI
    try assertConformance(encodeSystem(0b111, 1, 2, 0x300)); // CSRRCI
}

test "conformance: invalid encodings" {
    try assertConformance(0b1111111); // unknown opcode
    try assertConformance(encodeRBase(0b000, 0b1111111, 0, 0, 0)); // invalid R-type funct7
    try assertConformance(encodeLoad(0b011, 1, 2, 0)); // invalid load funct3
    try assertConformance(encodeStore(0b111, 1, 2, 0)); // invalid store funct3
    try assertConformance(encodeBranch(0b010, 1, 2)); // invalid branch funct3
    try assertConformance(encodeI(0b1100111, 0b001, 1, 2, 0)); // JALR bad funct3
    try assertConformance(encodeI(0b0001111, 0b001, 0, 0, 0)); // FENCE bad funct3
    try assertConformance(encodeSystem(0b000, 0, 0, 0x002)); // invalid funct12
    // Zbb rs2-dependent invalid cases
    try assertConformance(encodeRBase(0b100, 0b0000100, 1, 2, 1)); // ZEXT_H with rs2=1
    try assertConformance(encodeIAlu(0b001, 0b0110000_00011)); // CLZ group rs2=3
    try assertConformance(encodeIAlu(0b101, 0b0010100_00000)); // ORC_B with rs2=0
    try assertConformance(encodeIAlu(0b101, 0b0110100_00000)); // REV8 with rs2=0
}

test "conformance: non-zero immediates (scattered-bit formats)" {
    // Branch: positive and negative offsets exercise immB bit reassembly
    try assertConformance(encodeBranchFull(0b000, 1, 2, 256)); // BEQ +256
    try assertConformance(encodeBranchFull(0b001, 3, 4, -4)); // BNE -4
    try assertConformance(encodeBranchFull(0b100, 1, 2, 4094)); // BLT max positive (imm[12]=0, all others set)
    try assertConformance(encodeBranchFull(0b101, 1, 2, -4096)); // BGE min negative (imm[12]=1, all others 0)
    // JAL: positive and negative offsets exercise immJ bit reassembly
    try assertConformance(encodeJFull(5, 1048574)); // JAL near-max positive (exercises bit 20=0)
    try assertConformance(encodeJFull(5, -2)); // JAL -2 (sign bit set)
    try assertConformance(encodeJFull(5, 2048)); // JAL +2048 (exercises bit 11)
    try assertConformance(encodeJFull(5, -1048576)); // JAL min negative
}

test "conformance: sign-extended immediates" {
    // Store with negative immediate (sign extension from bit 11)
    try assertConformance(encodeStore(0b010, 1, 2, 0xFFF)); // SW imm=-1
    try assertConformance(encodeStore(0b000, 1, 2, 0x800)); // SB imm=-2048
    // Load with negative immediate
    try assertConformance(encodeLoad(0b010, 1, 2, 0x800)); // LW imm=-2048
    try assertConformance(encodeLoad(0b000, 1, 2, 0xFFF)); // LB imm=-1
    // CSR with bit 11 set (sign extension matters)
    try assertConformance(encodeSystem(0b001, 1, 2, 0xC00)); // CSRRW cycle counter addr
    try assertConformance(encodeSystem(0b010, 1, 2, 0xFFF)); // CSRRS max addr
}

test "conformance: atomics with aq/rl bits" {
    // aq=1, rl=0
    try assertConformance(encodeAtomicFull(0b00010, 1, 2, 0, 1, 0)); // LR.W.AQ
    try assertConformance(encodeAtomicFull(0b00011, 1, 2, 3, 1, 0)); // SC.W.AQ
    // aq=0, rl=1
    try assertConformance(encodeAtomicFull(0b00001, 1, 2, 3, 0, 1)); // AMOSWAP.W.RL
    // aq=1, rl=1
    try assertConformance(encodeAtomicFull(0b00000, 1, 2, 3, 1, 1)); // AMOADD.W.AQRL
}

test "conformance: compressed instructions (RV32C)" {
    // C.NOP = 0x0001 (bits[1:0]=01 → compressed)
    try assertConformance(0x0001);
    // C.ADDI x1, 1 = 0x0085
    try assertConformance(0x0085);
    // C.LI x1, 5 = 0x4095
    try assertConformance(0x4095);
    // C.LW x8, 0(x8) = 0x4000
    try assertConformance(0x4000);
    // C.J offset=0 = 0xA001
    try assertConformance(0xA001);
    // C.BEQZ x8, 0 = 0xC001
    try assertConformance(0xC001);
    // C.SLLI x1, 1 = 0x0086
    try assertConformance(0x0086);
    // C.LWSP x1, 0(x2) = 0x4082
    try assertConformance(0x4082);
    // C.JR x1 = 0x8082
    try assertConformance(0x8082);
    // C.ADD x1, x2 = 0x908A
    try assertConformance(0x908A);
    // C.SWSP x1, 0(x2) = 0xC006
    try assertConformance(0xC006);
}
