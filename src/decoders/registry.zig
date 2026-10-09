//! Opcode registry — the specification of every 32-bit encoding the decoder accepts.
//!
//! Each entry lists the fields that identify one instruction; every other bit is an
//! operand. An encoding is legal exactly when one entry matches it (`lookup`), and the
//! decoder (`branch.zig`) is tested against this table: registry_test.zig checks every
//! entry with random operands and sweeps the identifying fields, and
//! `zig build verify-decoder` compares the two on all 2^30 32-bit encodings.
//! 16-bit (RV32C) encodings are outside the registry.
//!
//! Fields:
//!   op      — tagged union variant from instructions.Opcode
//!   opcode7 — bits [6:0]
//!   f3      — bits [14:12]; null if not used for identification
//!   f7      — bits [31:25]; null if not used for identification
//!   rs2_eq  — bits [24:20] must equal this value (Zbb unary ops, ZEXT.H, LR.W)
//!   f5      — bits [31:27], atomics only (bits [26:25] are the free aq/rl flags)
//!   f12     — bits [31:20], ECALL/EBREAK only
//!   rd_eq   — bits [11:7] must equal this value (ECALL/EBREAK)
//!   rs1_eq  — bits [19:15] must equal this value (ECALL/EBREAK)
//!
//! FENCE and FENCE.I constrain only opcode7 and f3: the spec requires implementations
//! to ignore their other fields.

const instructions = @import("../instructions.zig");
const bf = @import("bitfields.zig");
pub const Opcode = instructions.Opcode;
pub const Instruction = instructions.Instruction;

pub const Entry = struct {
    op: Opcode,
    opcode7: u7,
    f3: ?u3 = null,
    f7: ?u7 = null,
    rs2_eq: ?u5 = null,
    f5: ?u5 = null,
    f12: ?u12 = null,
    rd_eq: ?u5 = null,
    rs1_eq: ?u5 = null,

    /// Bits this entry constrains.
    pub fn mask(e: Entry) u32 {
        var m: u32 = 0x7F;
        if (e.f3 != null) m |= 0x7 << 12;
        if (e.f7 != null) m |= 0x7F << 25;
        if (e.rs2_eq != null) m |= 0x1F << 20;
        if (e.f5 != null) m |= 0x1F << 27;
        if (e.f12 != null) m |= 0xFFF << 20;
        if (e.rd_eq != null) m |= 0x1F << 7;
        if (e.rs1_eq != null) m |= 0x1F << 15;
        return m;
    }

    /// Values of the constrained bits: `raw` encodes this entry iff `raw & mask() == match()`.
    pub fn match(e: Entry) u32 {
        var v: u32 = e.opcode7;
        if (e.f3) |x| v |= @as(u32, x) << 12;
        if (e.f7) |x| v |= @as(u32, x) << 25;
        if (e.rs2_eq) |x| v |= @as(u32, x) << 20;
        if (e.f5) |x| v |= @as(u32, x) << 27;
        if (e.f12) |x| v |= @as(u32, x) << 20;
        if (e.rd_eq) |x| v |= @as(u32, x) << 7;
        if (e.rs1_eq) |x| v |= @as(u32, x) << 15;
        return v;
    }
};

/// Registry indices by opcode7, so lookup() scans only the entries that can match.
const by_opcode = blk: {
    @setEvalBranchQuota(20_000);
    var lists: [128][]const u8 = @splat(&.{});
    for (0..128) |op| {
        var idx: []const u8 = &.{};
        for (registry, 0..) |e, i| {
            if (e.opcode7 == op) idx = idx ++ [_]u8{i};
        }
        lists[op] = idx;
    }
    break :blk lists;
};

/// The entry a 32-bit encoding matches, or null if none does. A plain search over the
/// table: this is the reference the decoder is checked against, not a fast path.
/// Entries never overlap (registry_test.zig), so there is at most one match.
pub fn lookup(raw: u32) ?Entry {
    for (by_opcode[raw & 0x7F]) |i| {
        const e = registry[i];
        if (raw & e.mask() == e.match()) return e;
    }
    return null;
}

/// The Instruction the decoder must produce for `raw`, an encoding of entry `e`.
/// Operands come from the instruction's format, with these exceptions:
///   - ECALL, EBREAK, FENCE and FENCE.I carry no operands;
///   - I-ALU shift-type instructions (opcode 0010011, funct3 001/101: SLLI, SRLI,
///     SRAI, RORI, the Zbs immediate forms and the Zbb unary ops) take imm from the
///     rs2 field, not the full 12-bit immediate.
pub fn instruction(e: Entry, raw: u32) Instruction {
    const op = e.op;
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
            .imm = if (e.opcode7 == 0b0010011 and (bf.funct3(raw) == 0b001 or bf.funct3(raw) == 0b101))
                @intCast(bf.rs2(raw))
            else
                bf.immI(raw),
            .raw = raw,
        },
        .S => .{ .op = op, .rs1 = bf.rs1(raw), .rs2 = bf.rs2(raw), .imm = bf.immS(raw), .raw = raw },
        .B => .{ .op = op, .rs1 = bf.rs1(raw), .rs2 = bf.rs2(raw), .imm = bf.immB(raw), .raw = raw },
        .U => .{ .op = op, .rd = bf.rd(raw), .imm = bf.immU(raw), .raw = raw },
        .J => .{ .op = op, .rd = bf.rd(raw), .imm = bf.immJ(raw), .raw = raw },
    };
}

pub const registry = [_]Entry{
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
    .{ .op = .{ .a = .LR_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b00010, .rs2_eq = 0 },
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
    .{ .op = .{ .i = .ECALL }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x000, .rd_eq = 0, .rs1_eq = 0 },
    .{ .op = .{ .i = .EBREAK }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x001, .rd_eq = 0, .rs1_eq = 0 },
    .{ .op = .{ .csr = .CSRRW }, .opcode7 = 0b1110011, .f3 = 0b001 },
    .{ .op = .{ .csr = .CSRRS }, .opcode7 = 0b1110011, .f3 = 0b010 },
    .{ .op = .{ .csr = .CSRRC }, .opcode7 = 0b1110011, .f3 = 0b011 },
    .{ .op = .{ .csr = .CSRRWI }, .opcode7 = 0b1110011, .f3 = 0b101 },
    .{ .op = .{ .csr = .CSRRSI }, .opcode7 = 0b1110011, .f3 = 0b110 },
    .{ .op = .{ .csr = .CSRRCI }, .opcode7 = 0b1110011, .f3 = 0b111 },

    // ---- Fixed opcodes (6) ----
    .{ .op = .{ .i = .LUI }, .opcode7 = 0b0110111 },
    .{ .op = .{ .i = .AUIPC }, .opcode7 = 0b0010111 },
    .{ .op = .{ .i = .JAL }, .opcode7 = 0b1101111 },
    .{ .op = .{ .i = .JALR }, .opcode7 = 0b1100111, .f3 = 0b000 },
    .{ .op = .{ .i = .FENCE }, .opcode7 = 0b0001111, .f3 = 0b000 },
    .{ .op = .{ .i = .FENCE_I }, .opcode7 = 0b0001111, .f3 = 0b001 },
};

test {
    _ = @import("registry_test.zig");
}
