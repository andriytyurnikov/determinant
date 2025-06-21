//! Comptime decoder lookup table.
//!
//! All 94 supported opcodes are declared in a single `registry` array.
//! Comptime generation derives the lookup tables from this registry:
//!   Level 1: opcode[6:0] → decode strategy  (128 entries, 1 byte each)
//!   Level 2: strategy-specific tables indexed by funct3, funct7, or funct5
//!
//! Trade-off vs branch-based decoder:
//!   Reference decoder: switch(opcode) → chain of if(extension) → switch(funct3/funct7)
//!   LUT decoder: array[opcode] → array[funct3][funct7]  (2-3 loads, zero branches)
//!   Cost: ~4 KiB read-only data.

const instructions = @import("instructions.zig");
const bf = @import("bitfields.zig");
const Opcode = instructions.Opcode;
const Instruction = instructions.Instruction;
const Format = instructions.Format;

pub const DecodeError = error{IllegalInstruction};

// ===========================================================================
// Opcode registry — single source of truth for all 94 supported opcodes.
//
// Each entry specifies the instruction's encoding fields. The comptime
// generator derives all lookup tables from this list.
//
// Fields:
//   op      — tagged union variant from instructions.Opcode
//   opcode7 — bits [6:0], selects the decode strategy
//   f3      — bits [14:12]; null if not used for identification
//   f7      — bits [31:25]; null if not used for identification
//   rs2_eq  — bits [24:20] must equal this value (Zbb special cases)
//   f5      — bits [31:27], atomics only
//   f12     — bits [31:20], ECALL/EBREAK only
// ===========================================================================

const Entry = struct {
    op: Opcode,
    opcode7: u7,
    f3: ?u3 = null,
    f7: ?u7 = null,
    rs2_eq: ?u5 = null,
    f5: ?u5 = null,
    f12: ?u12 = null,
};

const registry = [_]Entry{
    // ---- RV32I R-type (10) ---- opcode 0b0110011
    .{ .op = .{ .i = .ADD }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SUB }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0100000 },
    .{ .op = .{ .i = .SLL }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SLT }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SLTU }, .opcode7 = 0b0110011, .f3 = 0b011, .f7 = 0b0000000 },
    .{ .op = .{ .i = .XOR }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRL }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRA }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100000 },
    .{ .op = .{ .i = .OR }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000000 },
    .{ .op = .{ .i = .AND }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000000 },

    // ---- RV32M (8) ---- opcode 0b0110011, funct7 = 0b0000001
    .{ .op = .{ .m = .MUL }, .opcode7 = 0b0110011, .f3 = 0b000, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULH }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULHSU }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0000001 },
    .{ .op = .{ .m = .MULHU }, .opcode7 = 0b0110011, .f3 = 0b011, .f7 = 0b0000001 },
    .{ .op = .{ .m = .DIV }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000001 },
    .{ .op = .{ .m = .DIVU }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000001 },
    .{ .op = .{ .m = .REM }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000001 },
    .{ .op = .{ .m = .REMU }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000001 },

    // ---- Zba R-type (3) ---- opcode 0b0110011, funct7 = 0b0010000
    .{ .op = .{ .zba = .SH1ADD }, .opcode7 = 0b0110011, .f3 = 0b010, .f7 = 0b0010000 },
    .{ .op = .{ .zba = .SH2ADD }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0010000 },
    .{ .op = .{ .zba = .SH3ADD }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0010000 },

    // ---- Zbb R-type (10) ---- opcode 0b0110011
    .{ .op = .{ .zbb = .ANDN }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .ORN }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .XNOR }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0100000 },
    .{ .op = .{ .zbb = .MIN }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MINU }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MAX }, .opcode7 = 0b0110011, .f3 = 0b110, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .MAXU }, .opcode7 = 0b0110011, .f3 = 0b111, .f7 = 0b0000101 },
    .{ .op = .{ .zbb = .ROL }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .ROR }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .ZEXT_H }, .opcode7 = 0b0110011, .f3 = 0b100, .f7 = 0b0000100, .rs2_eq = 0 },

    // ---- Zbs R-type (4) ---- opcode 0b0110011
    .{ .op = .{ .zbs = .BCLR }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BEXT }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BINV }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0110100 },
    .{ .op = .{ .zbs = .BSET }, .opcode7 = 0b0110011, .f3 = 0b001, .f7 = 0b0010100 },

    // ---- RV32I I-ALU non-shift (6) ---- opcode 0b0010011
    .{ .op = .{ .i = .ADDI }, .opcode7 = 0b0010011, .f3 = 0b000 },
    .{ .op = .{ .i = .SLTI }, .opcode7 = 0b0010011, .f3 = 0b010 },
    .{ .op = .{ .i = .SLTIU }, .opcode7 = 0b0010011, .f3 = 0b011 },
    .{ .op = .{ .i = .XORI }, .opcode7 = 0b0010011, .f3 = 0b100 },
    .{ .op = .{ .i = .ORI }, .opcode7 = 0b0010011, .f3 = 0b110 },
    .{ .op = .{ .i = .ANDI }, .opcode7 = 0b0010011, .f3 = 0b111 },

    // ---- RV32I I-ALU shift (3) ---- opcode 0b0010011
    .{ .op = .{ .i = .SLLI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRLI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0000000 },
    .{ .op = .{ .i = .SRAI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0100000 },

    // ---- Zbb I-ALU (8) ---- opcode 0b0010011
    .{ .op = .{ .zbb = .RORI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110000 },
    .{ .op = .{ .zbb = .CLZ }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 0 },
    .{ .op = .{ .zbb = .CTZ }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 1 },
    .{ .op = .{ .zbb = .CPOP }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 2 },
    .{ .op = .{ .zbb = .SEXT_B }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 4 },
    .{ .op = .{ .zbb = .SEXT_H }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110000, .rs2_eq = 5 },
    .{ .op = .{ .zbb = .ORC_B }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0010100, .rs2_eq = 7 },
    .{ .op = .{ .zbb = .REV8 }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110100, .rs2_eq = 24 },

    // ---- Zbs I-ALU shift (4) ---- opcode 0b0010011
    .{ .op = .{ .zbs = .BCLRI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BEXTI }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0100100 },
    .{ .op = .{ .zbs = .BINVI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0110100 },
    .{ .op = .{ .zbs = .BSETI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0010100 },

    // ---- Load (5) ---- opcode 0b0000011
    .{ .op = .{ .i = .LB }, .opcode7 = 0b0000011, .f3 = 0b000 },
    .{ .op = .{ .i = .LH }, .opcode7 = 0b0000011, .f3 = 0b001 },
    .{ .op = .{ .i = .LW }, .opcode7 = 0b0000011, .f3 = 0b010 },
    .{ .op = .{ .i = .LBU }, .opcode7 = 0b0000011, .f3 = 0b100 },
    .{ .op = .{ .i = .LHU }, .opcode7 = 0b0000011, .f3 = 0b101 },

    // ---- Store (3) ---- opcode 0b0100011
    .{ .op = .{ .i = .SB }, .opcode7 = 0b0100011, .f3 = 0b000 },
    .{ .op = .{ .i = .SH }, .opcode7 = 0b0100011, .f3 = 0b001 },
    .{ .op = .{ .i = .SW }, .opcode7 = 0b0100011, .f3 = 0b010 },

    // ---- Branch (6) ---- opcode 0b1100011
    .{ .op = .{ .i = .BEQ }, .opcode7 = 0b1100011, .f3 = 0b000 },
    .{ .op = .{ .i = .BNE }, .opcode7 = 0b1100011, .f3 = 0b001 },
    .{ .op = .{ .i = .BLT }, .opcode7 = 0b1100011, .f3 = 0b100 },
    .{ .op = .{ .i = .BGE }, .opcode7 = 0b1100011, .f3 = 0b101 },
    .{ .op = .{ .i = .BLTU }, .opcode7 = 0b1100011, .f3 = 0b110 },
    .{ .op = .{ .i = .BGEU }, .opcode7 = 0b1100011, .f3 = 0b111 },

    // ---- Atomic (11) ---- opcode 0b0101111, funct3 = 0b010
    .{ .op = .{ .a = .LR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00010 },
    .{ .op = .{ .a = .SC_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00011 },
    .{ .op = .{ .a = .AMOSWAP_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00001 },
    .{ .op = .{ .a = .AMOADD_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00000 },
    .{ .op = .{ .a = .AMOXOR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00100 },
    .{ .op = .{ .a = .AMOAND_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b01100 },
    .{ .op = .{ .a = .AMOOR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b01000 },
    .{ .op = .{ .a = .AMOMIN_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10000 },
    .{ .op = .{ .a = .AMOMAX_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10100 },
    .{ .op = .{ .a = .AMOMINU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11000 },
    .{ .op = .{ .a = .AMOMAXU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11100 },

    // ---- System (8) ---- opcode 0b1110011
    .{ .op = .{ .i = .ECALL }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x000 },
    .{ .op = .{ .i = .EBREAK }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x001 },
    .{ .op = .{ .csr = .CSRRW }, .opcode7 = 0b1110011, .f3 = 0b001 },
    .{ .op = .{ .csr = .CSRRS }, .opcode7 = 0b1110011, .f3 = 0b010 },
    .{ .op = .{ .csr = .CSRRC }, .opcode7 = 0b1110011, .f3 = 0b011 },
    .{ .op = .{ .csr = .CSRRWI }, .opcode7 = 0b1110011, .f3 = 0b101 },
    .{ .op = .{ .csr = .CSRRSI }, .opcode7 = 0b1110011, .f3 = 0b110 },
    .{ .op = .{ .csr = .CSRRCI }, .opcode7 = 0b1110011, .f3 = 0b111 },

    // ---- Fixed opcodes (5) ----
    .{ .op = .{ .i = .LUI }, .opcode7 = 0b0110111 },
    .{ .op = .{ .i = .AUIPC }, .opcode7 = 0b0010111 },
    .{ .op = .{ .i = .JAL }, .opcode7 = 0b1101111 },
    .{ .op = .{ .i = .JALR }, .opcode7 = 0b1100111, .f3 = 0b000 },
    .{ .op = .{ .i = .FENCE }, .opcode7 = 0b0001111, .f3 = 0b000 },
};

// ===========================================================================
// Decode strategies — what sub-table to consult after level-1 lookup.
// ===========================================================================

const Strategy = enum(u8) {
    illegal,
    r_type, // → r_table[funct3][funct7]
    i_alu, // → i_alu_base[funct3] or shift_table[idx][funct7]
    load, // → load_table[funct3]
    store, // → store_table[funct3]
    branch, // → branch_table[funct3]
    atomic, // → atomic_table[funct5], funct3==010 guard
    system, // → system_table[funct3], or ECALL/EBREAK by funct12
    lui, // fixed .{ .i = .LUI }
    auipc, // fixed .{ .i = .AUIPC }
    jal, // fixed .{ .i = .JAL }
    jalr, // funct3==0 guard, fixed .{ .i = .JALR }
    fence, // funct3==0 guard, fixed .{ .i = .FENCE }
};

fn strategyFor(opcode7: u7) Strategy {
    return switch (opcode7) {
        0b0110011 => .r_type,
        0b0010011 => .i_alu,
        0b0000011 => .load,
        0b0100011 => .store,
        0b1100011 => .branch,
        0b0101111 => .atomic,
        0b1110011 => .system,
        0b0110111 => .lui,
        0b0010111 => .auipc,
        0b1101111 => .jal,
        0b1100111 => .jalr,
        0b0001111 => .fence,
        else => .illegal,
    };
}

// ===========================================================================
// Generated tables — all derived from the registry at comptime.
// ===========================================================================

const Tables = struct {
    level1: [128]Strategy,
    r_table: [8][128]?Opcode,
    i_alu_base: [8]?Opcode,
    shift_table: [2][128]?Opcode,
    load_table: [8]?Opcode,
    store_table: [8]?Opcode,
    branch_table: [8]?Opcode,
    atomic_table: [32]?Opcode,
    system_table: [8]?Opcode,
};

fn generateTables() Tables {
    @setEvalBranchQuota(10000);
    var t = Tables{
        .level1 = [1]Strategy{.illegal} ** 128,
        .r_table = [1][128]?Opcode{[1]?Opcode{null} ** 128} ** 8,
        .i_alu_base = [1]?Opcode{null} ** 8,
        .shift_table = [1][128]?Opcode{[1]?Opcode{null} ** 128} ** 2,
        .load_table = [1]?Opcode{null} ** 8,
        .store_table = [1]?Opcode{null} ** 8,
        .branch_table = [1]?Opcode{null} ** 8,
        .atomic_table = [1]?Opcode{null} ** 32,
        .system_table = [1]?Opcode{null} ** 8,
    };

    for (registry) |e| {
        const strat = strategyFor(e.opcode7);
        if (strat == .illegal) @compileError("registry entry has unknown opcode7");
        t.level1[e.opcode7] = strat;

        switch (strat) {
            .r_type => {
                if (e.rs2_eq != null) continue; // → rs2 refinement
                const f3 = e.f3 orelse @compileError("R-type entry missing f3");
                const f7 = e.f7 orelse @compileError("R-type entry missing f7");
                if (t.r_table[f3][f7] != null) @compileError("R-type table collision");
                t.r_table[f3][f7] = e.op;
            },
            .i_alu => {
                const f3 = e.f3 orelse @compileError("I-ALU entry missing f3");
                if (f3 == 0b001 or f3 == 0b101) {
                    if (e.rs2_eq != null) continue; // → rs2 refinement
                    const f7 = e.f7 orelse @compileError("I-ALU shift entry missing f7");
                    const idx: u1 = if (f3 == 0b001) 0 else 1;
                    if (t.shift_table[idx][f7] != null) @compileError("shift table collision");
                    t.shift_table[idx][f7] = e.op;
                } else {
                    if (t.i_alu_base[f3] != null) @compileError("I-ALU base collision");
                    t.i_alu_base[f3] = e.op;
                }
            },
            .load => {
                const f3 = e.f3 orelse @compileError("load entry missing f3");
                if (t.load_table[f3] != null) @compileError("load table collision");
                t.load_table[f3] = e.op;
            },
            .store => {
                const f3 = e.f3 orelse @compileError("store entry missing f3");
                if (t.store_table[f3] != null) @compileError("store table collision");
                t.store_table[f3] = e.op;
            },
            .branch => {
                const f3 = e.f3 orelse @compileError("branch entry missing f3");
                if (t.branch_table[f3] != null) @compileError("branch table collision");
                t.branch_table[f3] = e.op;
            },
            .atomic => {
                const f5 = e.f5 orelse @compileError("atomic entry missing f5");
                if (t.atomic_table[f5] != null) @compileError("atomic table collision");
                t.atomic_table[f5] = e.op;
            },
            .system => {
                const f3 = e.f3 orelse @compileError("system entry missing f3");
                if (f3 == 0b000) {
                    if (e.f12 == null) @compileError("ECALL/EBREAK entry missing f12");
                    continue; // handled inline in decode()
                }
                if (t.system_table[f3] != null) @compileError("system table collision");
                t.system_table[f3] = e.op;
            },
            .lui, .auipc, .jal, .jalr, .fence => {}, // handled inline in decode()
            .illegal => unreachable,
        }
    }

    return t;
}

const gen = generateTables();
const level1 = gen.level1;
const r_table = gen.r_table;
const i_alu_base = gen.i_alu_base;
const shift_table = gen.shift_table;
const load_table = gen.load_table;
const store_table = gen.store_table;
const branch_table = gen.branch_table;
const atomic_table = gen.atomic_table;
const system_table = gen.system_table;

// ===========================================================================
// Rs2-dependent refinement — generated from registry entries with rs2_eq set.
// ===========================================================================

const Rs2Ref = struct { f3: u3, f7: u7, rs2: u5, op: Opcode };
const ShiftRs2Ref = struct { idx: u1, f7: u7, rs2: u5, op: Opcode };

fn countRTypeRs2() usize {
    var n: usize = 0;
    for (registry) |e| {
        if (strategyFor(e.opcode7) == .r_type and e.rs2_eq != null) n += 1;
    }
    return n;
}

fn buildRTypeRs2() [countRTypeRs2()]Rs2Ref {
    var arr: [countRTypeRs2()]Rs2Ref = undefined;
    var i: usize = 0;
    for (registry) |e| {
        if (strategyFor(e.opcode7) == .r_type and e.rs2_eq != null) {
            arr[i] = .{ .f3 = e.f3.?, .f7 = e.f7.?, .rs2 = e.rs2_eq.?, .op = e.op };
            i += 1;
        }
    }
    return arr;
}

fn countShiftRs2() usize {
    var n: usize = 0;
    for (registry) |e| {
        if (strategyFor(e.opcode7) == .i_alu and e.rs2_eq != null) {
            const f3 = e.f3.?;
            if (f3 == 0b001 or f3 == 0b101) n += 1;
        }
    }
    return n;
}

fn buildShiftRs2() [countShiftRs2()]ShiftRs2Ref {
    var arr: [countShiftRs2()]ShiftRs2Ref = undefined;
    var i: usize = 0;
    for (registry) |e| {
        if (strategyFor(e.opcode7) == .i_alu and e.rs2_eq != null) {
            const f3 = e.f3.?;
            if (f3 == 0b001 or f3 == 0b101) {
                arr[i] = .{
                    .idx = if (f3 == 0b001) 0 else 1,
                    .f7 = e.f7.?,
                    .rs2 = e.rs2_eq.?,
                    .op = e.op,
                };
                i += 1;
            }
        }
    }
    return arr;
}

const r_rs2_refs = buildRTypeRs2();
const shift_rs2_refs = buildShiftRs2();

fn refineRs2R(f3: u3, f7: u7, r2: u5) ?Opcode {
    for (r_rs2_refs) |e| {
        if (e.f3 == f3 and e.f7 == f7 and e.rs2 == r2) return e.op;
    }
    return null;
}

fn refineRs2Shift(idx: u1, f7: u7, r2: u5) ?Opcode {
    for (shift_rs2_refs) |e| {
        if (e.idx == idx and e.f7 == f7 and e.rs2 == r2) return e.op;
    }
    return null;
}

// ===========================================================================
// Decoder entry point
// ===========================================================================

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
