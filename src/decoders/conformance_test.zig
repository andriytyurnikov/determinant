const std = @import("std");
const t = @import("lut/test_helpers.zig");
const Opcode = t.Opcode;
const encodeRBase = t.encodeRBase;
const encodeI = t.encodeI;
const encodeIAlu = t.encodeIAlu;
const encodeLoad = t.encodeLoad;
const encodeStore = t.encodeStore;
const encodeBranch = t.encodeBranch;
const encodeBranchFull = t.encodeBranchFull;
const encodeU = t.encodeU;
const encodeJ = t.encodeJ;
const encodeJFull = t.encodeJFull;
const encodeJalr = t.encodeJalr;
const encodeFence = t.encodeFence;
const encodeAtomic = t.encodeAtomic;
const encodeAtomicFull = t.encodeAtomicFull;
const encodeSystem = t.encodeSystem;

const decoder = @import("branch.zig");
const decodeInstruction = t.lut.decode;

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
    try assertConformance(0x00000000); // zero instruction
    try assertConformance(0xFFFFFFFF); // all-ones instruction
    try assertConformance(0b1111111); // unknown opcode
    try assertConformance(encodeRBase(0b000, 0b1111111, 0, 0, 0)); // invalid R-type funct7
    try assertConformance(encodeLoad(0b011, 1, 2, 0)); // invalid load funct3
    try assertConformance(encodeStore(0b111, 1, 2, 0)); // invalid store funct3
    try assertConformance(encodeBranch(0b010, 1, 2)); // invalid branch funct3
    try assertConformance(encodeI(0b1100111, 0b001, 1, 2, 0)); // JALR bad funct3
    try assertConformance(encodeI(0b0001111, 0b001, 0, 0, 0)); // FENCE_I (valid, funct3=001)
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
    try assertConformance(encodeBranchFull(0b100, 1, 2, 4094)); // BLT max positive
    try assertConformance(encodeBranchFull(0b101, 1, 2, -4096)); // BGE min negative
    // JAL: positive and negative offsets exercise immJ bit reassembly
    try assertConformance(encodeJFull(5, 1048574)); // JAL near-max positive
    try assertConformance(encodeJFull(5, -2)); // JAL -2
    try assertConformance(encodeJFull(5, 2048)); // JAL +2048
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
    // C.ADDI4SPN x8, sp, 4 = 0x0040
    try assertConformance(0x0040);
    // C.SW x8, 0(x8) = 0xC000
    try assertConformance(0xC000);
    // C.JAL offset=0 = 0x2001
    try assertConformance(0x2001);
    // C.ADDI16SP sp, 16 = 0x6141
    try assertConformance(0x6141);
    // C.LUI x3, 1 = 0x6185
    try assertConformance(0x6185);
    // C.SRLI x8, 1 = 0x8005
    try assertConformance(0x8005);
    // C.SRAI x8, 1 = 0x8405
    try assertConformance(0x8405);
    // C.ANDI x8, 3 = 0x880D
    try assertConformance(0x880D);
    // C.SUB x8, x9 = 0x8C05
    try assertConformance(0x8C05);
    // C.XOR x8, x9 = 0x8C25
    try assertConformance(0x8C25);
    // C.OR x8, x9 = 0x8C45
    try assertConformance(0x8C45);
    // C.AND x8, x9 = 0x8C65
    try assertConformance(0x8C65);
    // C.BNEZ x8, 0 = 0xE001
    try assertConformance(0xE001);
    // C.MV x3, x4 = 0x8192
    try assertConformance(0x8192);
    // C.EBREAK = 0x9002
    try assertConformance(0x9002);
    // C.JALR x1 = 0x9082
    try assertConformance(0x9082);
}
