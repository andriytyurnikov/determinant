//! Comptime decoder lookup table.
//!
//! Two-level comptime LUT for RISC-V instruction decoding:
//!   Level 1: opcode[6:0] → decode strategy  (128 entries, 1 byte each)
//!   Level 2: strategy-specific table indexed by funct3/funct7
//!
//! Covers all 94 opcodes in the instructions.Opcode tagged union.
//!
//! Trade-off vs branch-based decoder:
//!   Current decoder: switch(opcode) → chain of if(extension) → switch(funct3/funct7)
//!   LUT decoder: array[opcode] → array[funct3][funct7]  (2-3 loads, zero branches)
//!   Cost: ~4 KiB read-only data.

const instructions = @import("instructions.zig");
const bf = @import("bitfields.zig");
const Opcode = instructions.Opcode;
const Instruction = instructions.Instruction;
const Format = instructions.Format;

pub const DecodeError = error{IllegalInstruction};

/// What kind of sub-decode to perform after the level-1 lookup.
const Strategy = enum(u8) {
    illegal,
    r_type, // → r_table[funct3][funct7]
    i_alu, // → i_alu_table[funct3], shifts check funct7
    load, // → load_table[funct3]
    store, // → store_table[funct3]
    branch, // → branch_table[funct3]
    atomic, // funct3==010 guard, then atomic_table[funct5]
    system, // funct3==0: funct12; else: system_table[funct3]
    lui, // fixed .{ .i = .LUI }
    auipc, // fixed .{ .i = .AUIPC }
    jal, // fixed .{ .i = .JAL }
    jalr, // funct3==0 guard, fixed .{ .i = .JALR }
    fence, // funct3==0 guard, fixed .{ .i = .FENCE }
};

// ---------------------------------------------------------------------------
// Level 1: opcode[6:0] → Strategy.  128 entries, 1 byte each.
// ---------------------------------------------------------------------------

const level1: [128]Strategy = blk: {
    var table: [128]Strategy = [1]Strategy{.illegal} ** 128;
    table[0b0110011] = .r_type;
    table[0b0010011] = .i_alu;
    table[0b0000011] = .load;
    table[0b0100011] = .store;
    table[0b1100011] = .branch;
    table[0b0101111] = .atomic;
    table[0b1110011] = .system;
    table[0b0110111] = .lui;
    table[0b0010111] = .auipc;
    table[0b1101111] = .jal;
    table[0b1100111] = .jalr;
    table[0b0001111] = .fence;
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2a: R-type.  [funct3][funct7] → ?Opcode.
// 8 × 128 = 1024 entries.
// ---------------------------------------------------------------------------

const r_table: [8][128]?Opcode = blk: {
    var table: [8][128]?Opcode = [1][128]?Opcode{[1]?Opcode{null} ** 128} ** 8;
    const entries = [_]struct { u3, u7, Opcode }{
        // RV32I (10)
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
        // RV32M (8) — funct7=0b0000001
        .{ 0b000, 0b0000001, .{ .m = .MUL } },
        .{ 0b001, 0b0000001, .{ .m = .MULH } },
        .{ 0b010, 0b0000001, .{ .m = .MULHSU } },
        .{ 0b011, 0b0000001, .{ .m = .MULHU } },
        .{ 0b100, 0b0000001, .{ .m = .DIV } },
        .{ 0b101, 0b0000001, .{ .m = .DIVU } },
        .{ 0b110, 0b0000001, .{ .m = .REM } },
        .{ 0b111, 0b0000001, .{ .m = .REMU } },
        // Zba (3) — funct7=0b0010000
        .{ 0b010, 0b0010000, .{ .zba = .SH1ADD } },
        .{ 0b100, 0b0010000, .{ .zba = .SH2ADD } },
        .{ 0b110, 0b0010000, .{ .zba = .SH3ADD } },
        // Zba (3) are above
        // Zbb R-type (9 non-rs2-dependent) — ZEXT_H needs rs2 refinement, handled separately
        .{ 0b111, 0b0100000, .{ .zbb = .ANDN } },
        .{ 0b110, 0b0100000, .{ .zbb = .ORN } },
        .{ 0b100, 0b0100000, .{ .zbb = .XNOR } },
        .{ 0b100, 0b0000101, .{ .zbb = .MIN } },
        .{ 0b101, 0b0000101, .{ .zbb = .MINU } },
        .{ 0b110, 0b0000101, .{ .zbb = .MAX } },
        .{ 0b111, 0b0000101, .{ .zbb = .MAXU } },
        .{ 0b001, 0b0110000, .{ .zbb = .ROL } },
        .{ 0b101, 0b0110000, .{ .zbb = .ROR } },
        // Zbs R-type (4)
        .{ 0b001, 0b0100100, .{ .zbs = .BCLR } },
        .{ 0b101, 0b0100100, .{ .zbs = .BEXT } },
        .{ 0b001, 0b0110100, .{ .zbs = .BINV } },
        .{ 0b001, 0b0010100, .{ .zbs = .BSET } },
    };
    for (entries) |e| {
        table[e[0]][e[1]] = e[2];
    }
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2b: I-type ALU.
// Non-shift: funct3 alone → opcode (8 entries).
// Shift: funct3 selects left/right, funct7 disambiguates variant.
// ---------------------------------------------------------------------------

const i_alu_base: [8]?Opcode = blk: {
    var table: [8]?Opcode = [1]?Opcode{null} ** 8;
    table[0b000] = .{ .i = .ADDI };
    table[0b010] = .{ .i = .SLTI };
    table[0b011] = .{ .i = .SLTIU };
    table[0b100] = .{ .i = .XORI };
    table[0b110] = .{ .i = .ORI };
    table[0b111] = .{ .i = .ANDI };
    // funct3=001, 101 → handled by shift_table
    break :blk table;
};

/// Shift sub-table: [left=0 / right=1][funct7] → ?Opcode.
/// funct3=001 (left):  SLLI @ funct7=0x00
/// funct3=101 (right): SRLI @ funct7=0x00, SRAI @ funct7=0x20
const shift_table: [2][128]?Opcode = blk: {
    var table: [2][128]?Opcode = [1][128]?Opcode{[1]?Opcode{null} ** 128} ** 2;
    // RV32I shifts
    table[0][0b0000000] = .{ .i = .SLLI }; // funct3=001
    table[1][0b0000000] = .{ .i = .SRLI }; // funct3=101
    table[1][0b0100000] = .{ .i = .SRAI }; // funct3=101
    // Zbb I-type shift (non-rs2-dependent)
    table[1][0b0110000] = .{ .zbb = .RORI }; // funct3=101
    // Zbs I-type shifts
    table[0][0b0100100] = .{ .zbs = .BCLRI }; // funct3=001
    table[1][0b0100100] = .{ .zbs = .BEXTI }; // funct3=101
    table[0][0b0110100] = .{ .zbs = .BINVI }; // funct3=001
    table[0][0b0010100] = .{ .zbs = .BSETI }; // funct3=001
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2c: Load.  [funct3] → ?Opcode.  5 of 8 entries populated.
// ---------------------------------------------------------------------------

const load_table: [8]?Opcode = blk: {
    var table: [8]?Opcode = [1]?Opcode{null} ** 8;
    table[0b000] = .{ .i = .LB };
    table[0b001] = .{ .i = .LH };
    table[0b010] = .{ .i = .LW };
    table[0b100] = .{ .i = .LBU };
    table[0b101] = .{ .i = .LHU };
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2d: Store.  [funct3] → ?Opcode.  3 of 8 entries populated.
// ---------------------------------------------------------------------------

const store_table: [8]?Opcode = blk: {
    var table: [8]?Opcode = [1]?Opcode{null} ** 8;
    table[0b000] = .{ .i = .SB };
    table[0b001] = .{ .i = .SH };
    table[0b010] = .{ .i = .SW };
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2e: Branch.  [funct3] → ?Opcode.  6 of 8 entries populated.
// ---------------------------------------------------------------------------

const branch_table: [8]?Opcode = blk: {
    var table: [8]?Opcode = [1]?Opcode{null} ** 8;
    table[0b000] = .{ .i = .BEQ };
    table[0b001] = .{ .i = .BNE };
    table[0b100] = .{ .i = .BLT };
    table[0b101] = .{ .i = .BGE };
    table[0b110] = .{ .i = .BLTU };
    table[0b111] = .{ .i = .BGEU };
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2f: Atomic.  [funct5] → ?Opcode.  11 of 32 entries populated.
// funct3 must be 0b010 (word); checked in decode().
// ---------------------------------------------------------------------------

const atomic_table: [32]?Opcode = blk: {
    var table: [32]?Opcode = [1]?Opcode{null} ** 32;
    table[0b00010] = .{ .a = .LR_W };
    table[0b00011] = .{ .a = .SC_W };
    table[0b00001] = .{ .a = .AMOSWAP_W };
    table[0b00000] = .{ .a = .AMOADD_W };
    table[0b00100] = .{ .a = .AMOXOR_W };
    table[0b01100] = .{ .a = .AMOAND_W };
    table[0b01000] = .{ .a = .AMOOR_W };
    table[0b10000] = .{ .a = .AMOMIN_W };
    table[0b10100] = .{ .a = .AMOMAX_W };
    table[0b11000] = .{ .a = .AMOMINU_W };
    table[0b11100] = .{ .a = .AMOMAXU_W };
    break :blk table;
};

// ---------------------------------------------------------------------------
// Level 2g: System/CSR.  [funct3] → ?Opcode.  6 of 8 entries populated.
// funct3==0 handled inline (ECALL/EBREAK by funct12).
// ---------------------------------------------------------------------------

const system_table: [8]?Opcode = blk: {
    var table: [8]?Opcode = [1]?Opcode{null} ** 8;
    table[0b001] = .{ .csr = .CSRRW };
    table[0b010] = .{ .csr = .CSRRS };
    table[0b011] = .{ .csr = .CSRRC };
    table[0b101] = .{ .csr = .CSRRWI };
    table[0b110] = .{ .csr = .CSRRSI };
    table[0b111] = .{ .csr = .CSRRCI };
    break :blk table;
};

// ---------------------------------------------------------------------------
// Zbb rs2-dependent refinement.
// Called only when the primary table returns null for specific coordinates.
// ---------------------------------------------------------------------------

/// Refine R-type decode for Zbb rs2-dependent opcodes.
/// Only one coordinate: f3=0b100, f7=0b0000100 → ZEXT_H if rs2=0.
fn refineRs2R(f3: u3, f7: u7, r2: u5) ?Opcode {
    if (f3 == 0b100 and f7 == 0b0000100) {
        return if (r2 == 0) .{ .zbb = .ZEXT_H } else null;
    }
    return null;
}

/// Refine I-type shift decode for Zbb rs2-dependent opcodes.
/// idx=0 → funct3=001, idx=1 → funct3=101.
fn refineRs2Shift(idx: u1, f7: u7, r2: u5) ?Opcode {
    if (idx == 0 and f7 == 0b0110000) return switch (r2) {
        0 => .{ .zbb = .CLZ },
        1 => .{ .zbb = .CTZ },
        2 => .{ .zbb = .CPOP },
        4 => .{ .zbb = .SEXT_B },
        5 => .{ .zbb = .SEXT_H },
        else => null,
    };
    if (idx == 1 and f7 == 0b0010100)
        return if (r2 == 7) .{ .zbb = .ORC_B } else null;
    if (idx == 1 and f7 == 0b0110100)
        return if (r2 == 24) .{ .zbb = .REV8 } else null;
    return null;
}

// ---------------------------------------------------------------------------
// Decoder entry point
// ---------------------------------------------------------------------------

/// Decode a 32-bit instruction word into an Opcode using comptime lookup tables.
/// Returns null for unrecognized encodings.
pub fn decode(raw: u32) ?Opcode {
    const opcode_bits: u7 = @truncate(raw);
    const f3: u3 = @truncate(raw >> 12);
    const f7: u7 = @truncate(raw >> 25);
    const r2: u5 = @truncate(raw >> 20);

    return switch (level1[opcode_bits]) {
        .illegal => null,
        .r_type => r_table[f3][f7] orelse refineRs2R(f3, f7, r2),
        .i_alu => switch (f3) {
            0b001 => shift_table[0][f7] orelse refineRs2Shift(0, f7, r2),
            0b101 => shift_table[1][f7] orelse refineRs2Shift(1, f7, r2),
            else => i_alu_base[f3],
        },
        .load => load_table[f3],
        .store => store_table[f3],
        .branch => branch_table[f3],
        .atomic => if (f3 == 0b010) atomic_table[@as(u5, @truncate(raw >> 27))] else null,
        .system => if (f3 == 0) switch (@as(u12, @truncate(raw >> 20))) {
            0x000 => @as(?Opcode, .{ .i = .ECALL }),
            0x001 => @as(?Opcode, .{ .i = .EBREAK }),
            else => null,
        } else system_table[f3],
        .lui => .{ .i = .LUI },
        .auipc => .{ .i = .AUIPC },
        .jal => .{ .i = .JAL },
        .jalr => if (f3 == 0) .{ .i = .JALR } else null,
        .fence => if (f3 == 0) .{ .i = .FENCE } else null,
    };
}

/// Decode a 32-bit instruction word into a full Instruction using the LUT.
/// Handles both 16-bit compressed (RV32C) and 32-bit instructions.
pub fn decodeInstruction(raw: u32) DecodeError!Instruction {
    if (instructions.isCompressed(raw)) {
        const rv32c = instructions.rv32i.rv32c;
        const exp = try rv32c.expand(@truncate(raw));
        return .{ .op = .{ .i = exp.op }, .rd = exp.rd, .rs1 = exp.rs1, .rs2 = exp.rs2, .imm = exp.imm, .raw = raw };
    }
    const op = decode(raw) orelse return error.IllegalInstruction;
    return buildInstruction(op, raw);
}

/// Build a full Instruction from a decoded Opcode and raw instruction word.
/// Extracts operand fields based on the instruction's format.
fn buildInstruction(op: Opcode, raw: u32) Instruction {
    // ECALL, EBREAK, FENCE use I-format encoding but carry no operand fields.
    switch (op) {
        .i => |i_op| switch (i_op) {
            .ECALL, .EBREAK, .FENCE => return .{ .op = op, .raw = raw },
            else => {},
        },
        else => {},
    }
    return switch (op.format()) {
        .R => .{ .op = op, .rd = bf.rd(raw), .rs1 = bf.rs1(raw), .rs2 = bf.rs2(raw), .raw = raw },
        .I => .{
            .op = op,
            .rd = bf.rd(raw),
            .rs1 = bf.rs1(raw),
            .imm = blk: {
                // I-ALU shifts (opcode=0b0010011, funct3=001 or 101) use rs2 field as shamt
                const opcode_bits: u7 = @truncate(raw);
                const f3: u3 = @truncate(raw >> 12);
                if (opcode_bits == 0b0010011 and (f3 == 0b001 or f3 == 0b101))
                    break :blk @as(i32, @intCast(bf.rs2(raw)));
                break :blk bf.immI(raw);
            },
            .raw = raw,
        },
        .S => .{ .op = op, .rs1 = bf.rs1(raw), .rs2 = bf.rs2(raw), .imm = bf.immS(raw), .raw = raw },
        .B => .{ .op = op, .rs1 = bf.rs1(raw), .rs2 = bf.rs2(raw), .imm = bf.immB(raw), .raw = raw },
        .U => .{ .op = op, .rd = bf.rd(raw), .imm = bf.immU(raw), .raw = raw },
        .J => .{ .op = op, .rd = bf.rd(raw), .imm = bf.immJ(raw), .raw = raw },
    };
}

test {
    _ = @import("comptime_lut_test.zig");
}
