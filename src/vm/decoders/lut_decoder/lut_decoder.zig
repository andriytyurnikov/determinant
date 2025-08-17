//! Comptime decoder lookup table.
//!
//! The opcode registry (95 entries) lives in `registry.zig`.
//! This module derives lookup tables from that registry at comptime:
//!   Level 1: opcode[6:0] → decode strategy  (128 entries, 1 byte each)
//!   Level 2: strategy-specific tables indexed by funct3, funct7, or funct5
//!
//! Trade-off vs branch-based decoder:
//!   Reference decoder: switch(opcode) → chain of if(extension) → switch(funct3/funct7)
//!   LUT decoder: array[opcode] → array[funct3][funct7]  (2-3 loads, zero branches)
//!   Cost: ~6 KiB read-only data.

const instructions = @import("../../instructions.zig");
const bf = @import("../bitfields.zig");
const reg = @import("../registry.zig");
const expand_mod = @import("../expand.zig");
const Opcode = instructions.Opcode;
const Instruction = instructions.Instruction;
const Entry = reg.Entry;
const Strategy = reg.Strategy;

pub const DecodeError = bf.DecodeError;

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

    for (reg.registry) |e| {
        const strat = reg.strategyFor(e.opcode7);
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
    for (reg.registry) |e| {
        if (reg.strategyFor(e.opcode7) == .r_type and e.rs2_eq != null) n += 1;
    }
    return n;
}

fn buildRTypeRs2() [countRTypeRs2()]Rs2Ref {
    var arr: [countRTypeRs2()]Rs2Ref = undefined;
    var i: usize = 0;
    for (reg.registry) |e| {
        if (reg.strategyFor(e.opcode7) == .r_type and e.rs2_eq != null) {
            arr[i] = .{ .f3 = e.f3.?, .f7 = e.f7.?, .rs2 = e.rs2_eq.?, .op = e.op };
            i += 1;
        }
    }
    return arr;
}

fn countShiftRs2() usize {
    var n: usize = 0;
    for (reg.registry) |e| {
        if (reg.strategyFor(e.opcode7) == .i_alu and e.rs2_eq != null) {
            const f3 = e.f3.?;
            if (f3 == 0b001 or f3 == 0b101) n += 1;
        }
    }
    return n;
}

fn buildShiftRs2() [countShiftRs2()]ShiftRs2Ref {
    var arr: [countShiftRs2()]ShiftRs2Ref = undefined;
    var i: usize = 0;
    for (reg.registry) |e| {
        if (reg.strategyFor(e.opcode7) == .i_alu and e.rs2_eq != null) {
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

fn refineRs2R(f3: u3, f7: u7, rs2: u5) ?Opcode {
    for (r_rs2_refs) |e| {
        if (e.f3 == f3 and e.f7 == f7 and e.rs2 == rs2) return e.op;
    }
    return null;
}

fn refineRs2Shift(idx: u1, f7: u7, rs2: u5) ?Opcode {
    for (shift_rs2_refs) |e| {
        if (e.idx == idx and e.f7 == f7 and e.rs2 == rs2) return e.op;
    }
    return null;
}

// ===========================================================================
// Decoder entry point
// ===========================================================================

/// Decode a 32-bit instruction word into an Opcode using comptime lookup tables.
/// Returns null for unrecognized encodings.
pub fn decodeOpcode(raw: u32) ?Opcode {
    const opcode_bits = bf.opcode7(raw);
    const f3 = bf.funct3(raw);
    const f7 = bf.funct7(raw);
    const rs2 = bf.rs2(raw);

    return switch (level1[opcode_bits]) {
        .illegal => null,
        .r_type => r_table[f3][f7] orelse refineRs2R(f3, f7, rs2),
        .i_alu => switch (f3) {
            0b001 => shift_table[0][f7] orelse refineRs2Shift(0, f7, rs2),
            0b101 => shift_table[1][f7] orelse refineRs2Shift(1, f7, rs2),
            else => i_alu_base[f3],
        },
        .load => load_table[f3],
        .store => store_table[f3],
        .branch => branch_table[f3],
        // Note: LR.W spec says rs2 "should be zero" (software convention, not hardware
        // requirement). We accept non-zero rs2 for forward-compatibility with future extensions.
        .atomic => if (f3 == 0b010) atomic_table[bf.funct5(raw)] else null,
        .system => if (f3 == 0b000) switch (@as(u12, @truncate(raw >> 20))) {
            0x000 => @as(?Opcode, .{ .i = .ECALL }),
            0x001 => @as(?Opcode, .{ .i = .EBREAK }),
            else => null,
        } else system_table[f3],
        .lui => .{ .i = .LUI },
        .auipc => .{ .i = .AUIPC },
        .jal => .{ .i = .JAL },
        .jalr => if (f3 == 0b000) .{ .i = .JALR } else null,
        .fence => switch (f3) {
            0b000 => .{ .i = .FENCE },
            0b001 => .{ .i = .FENCE_I },
            else => null,
        },
    };
}

/// Decode a 32-bit instruction word into a full Instruction using the LUT.
/// Handles both 16-bit compressed (RV32C) and 32-bit instructions.
pub fn decode(raw: u32) DecodeError!Instruction {
    if (instructions.isCompressed(raw)) {
        return expand_mod.expandCompressed(raw);
    }
    const op = decodeOpcode(raw) orelse return error.IllegalInstruction;
    return buildInstruction(op, raw);
}

/// Build a full Instruction from a decoded Opcode and raw instruction word.
/// Extracts operand fields based on the instruction's format.
fn buildInstruction(op: Opcode, raw: u32) Instruction {
    // ECALL, EBREAK, FENCE, FENCE.I use I-format encoding but carry no operand fields.
    switch (op) {
        .i => |i_op| switch (i_op) {
            .ECALL, .EBREAK, .FENCE, .FENCE_I => return .{ .op = op, .raw = raw },
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
                const f3_bits: u3 = @truncate(raw >> 12);
                if (opcode_bits == 0b0010011 and (f3_bits == 0b001 or f3_bits == 0b101))
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
    _ = @import("lut_decoder_test.zig");
    _ = @import("../lut_conformance_test.zig");
}
