//! Render a decoded Instruction as LLVM's RISC-V instruction printer does with aliases
//! disabled (-riscv-no-aliases): ABI register names, CSR names from a table harvested
//! from the same LLVM, decimal immediates, "mn op, op" (the oracle collapses LLVM's
//! tabs to spaces).
//!
//! Only the decoded fields (op, rd, rs1, rs2, imm, compressed_op) are used, except for
//! the fields the decoder does not decode at all (FENCE pred/succ, AMO aq/rl), which
//! are taken from `raw`. Compressed expansions are also checked for internal
//! consistency (implicit registers, base opcode); a violation renders as "!BAD ...",
//! which never matches LLVM's text.

const std = @import("std");
const det = @import("determinant");
const Instruction = det.Instruction;
const Opcode = det.Opcode;
const rv32i = det.instructions.rv32i;
const rv32c = rv32i.rv32c;
const Writer = std.Io.Writer;

pub const abi = [32][]const u8{
    "zero", "ra", "sp",  "gp",  "tp", "t0", "t1", "t2",
    "s0",   "s1", "a0",  "a1",  "a2", "a3", "a4", "a5",
    "a6",   "a7", "s2",  "s3",  "s4", "s5", "s6", "s7",
    "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

/// LLVM-printed CSR operand text, indexed by CSR number.
pub const CsrNames = [4096][]const u8;

fn reg(w: *Writer, r: u5) !void {
    try w.writeAll(abi[r]);
}

fn mnemonic(w: *Writer, op: Opcode) !void {
    for (op.name()) |ch| try w.writeByte(std.ascii.toLower(ch));
}

fn fenceSet(w: *Writer, bits: u4) !void {
    if (bits == 0) return w.writeByte('0');
    if (bits & 8 != 0) try w.writeByte('i');
    if (bits & 4 != 0) try w.writeByte('o');
    if (bits & 2 != 0) try w.writeByte('r');
    if (bits & 1 != 0) try w.writeByte('w');
}

/// rd, rs1, rs2
fn rrr(w: *Writer, i: Instruction) !void {
    try mnemonic(w, i.op);
    try w.writeByte(' ');
    try reg(w, i.rd);
    try w.writeAll(", ");
    try reg(w, i.rs1);
    try w.writeAll(", ");
    try reg(w, i.rs2);
}

/// rd, rs1, imm
fn rri(w: *Writer, i: Instruction) !void {
    try mnemonic(w, i.op);
    try w.writeByte(' ');
    try reg(w, i.rd);
    try w.writeAll(", ");
    try reg(w, i.rs1);
    try w.print(", {d}", .{i.imm});
}

/// rd, rs1
fn rr(w: *Writer, i: Instruction) !void {
    try mnemonic(w, i.op);
    try w.writeByte(' ');
    try reg(w, i.rd);
    try w.writeAll(", ");
    try reg(w, i.rs1);
}

/// mn r, imm(base)
fn mem(w: *Writer, mn: []const u8, r: u5, imm: i32, base: u5) !void {
    try w.writeAll(mn);
    try w.writeByte(' ');
    try reg(w, r);
    try w.print(", {d}(", .{imm});
    try reg(w, base);
    try w.writeByte(')');
}

fn upper20(imm: i32) u32 {
    return (@as(u32, @bitCast(imm)) >> 12) & 0xFFFFF;
}

pub fn render(w: *Writer, csr_names: *const CsrNames, i: Instruction) !void {
    if (i.compressed_op) |cop| return renderCompressed(w, i, cop);
    switch (i.op) {
        .i => |op| switch (op) {
            .ADD, .SUB, .SLL, .SLT, .SLTU, .XOR, .SRL, .SRA, .OR, .AND => try rrr(w, i),
            .ADDI, .SLTI, .SLTIU, .XORI, .ORI, .ANDI, .SLLI, .SRLI, .SRAI => try rri(w, i),
            .LB, .LH, .LW, .LBU, .LHU => {
                var buf: [8]u8 = undefined;
                try mem(w, std.ascii.lowerString(&buf, i.op.name()), i.rd, i.imm, i.rs1);
            },
            .SB, .SH, .SW => {
                var buf: [8]u8 = undefined;
                try mem(w, std.ascii.lowerString(&buf, i.op.name()), i.rs2, i.imm, i.rs1);
            },
            .BEQ, .BNE, .BLT, .BGE, .BLTU, .BGEU => {
                try mnemonic(w, i.op);
                try w.writeByte(' ');
                try reg(w, i.rs1);
                try w.writeAll(", ");
                try reg(w, i.rs2);
                try w.print(", {d}", .{i.imm});
            },
            .LUI, .AUIPC => {
                try mnemonic(w, i.op);
                try w.writeByte(' ');
                try reg(w, i.rd);
                try w.print(", {d}", .{upper20(i.imm)});
            },
            .JAL => {
                try w.writeAll("jal ");
                try reg(w, i.rd);
                try w.print(", {d}", .{i.imm});
            },
            .JALR => try mem(w, "jalr", i.rd, i.imm, i.rs1),
            .FENCE => {
                // FENCE decodes no fields; pred/succ come from raw, for display only.
                try w.writeAll("fence ");
                try fenceSet(w, @truncate(i.raw >> 24));
                try w.writeAll(", ");
                try fenceSet(w, @truncate(i.raw >> 20));
            },
            .FENCE_I => try w.writeAll("fence.i"),
            .ECALL => try w.writeAll("ecall"),
            .EBREAK => try w.writeAll("ebreak"),
        },
        .m, .zba => try rrr(w, i),
        .a => |op| {
            try mnemonic(w, i.op);
            // aq = bit 26, rl = bit 25 (not decoded; taken from raw)
            const aqrl: u2 = @truncate(i.raw >> 25);
            try w.writeAll(switch (aqrl) {
                0 => "",
                1 => ".rl",
                2 => ".aq",
                3 => ".aqrl",
            });
            try w.writeByte(' ');
            try reg(w, i.rd);
            try w.writeAll(", ");
            if (op != .LR_W) {
                try reg(w, i.rs2);
                try w.writeAll(", ");
            }
            try w.writeByte('(');
            try reg(w, i.rs1);
            try w.writeByte(')');
        },
        .csr => |op| {
            try mnemonic(w, i.op);
            try w.writeByte(' ');
            try reg(w, i.rd);
            try w.writeAll(", ");
            try w.writeAll(csr_names[i.csrAddr()]);
            try w.writeAll(", ");
            switch (op) {
                .CSRRW, .CSRRS, .CSRRC => try reg(w, i.rs1),
                .CSRRWI, .CSRRSI, .CSRRCI => try w.print("{d}", .{i.rs1}), // zimm is in the rs1 field
            }
        },
        .zbb => |op| switch (op) {
            .ANDN, .ORN, .XNOR, .MAX, .MAXU, .MIN, .MINU, .ROL, .ROR => try rrr(w, i),
            .ZEXT_H, .CLZ, .CTZ, .CPOP, .SEXT_B, .SEXT_H, .ORC_B, .REV8 => try rr(w, i),
            .RORI => try rri(w, i),
        },
        .zbs => |op| switch (op) {
            .BCLR, .BEXT, .BINV, .BSET => try rrr(w, i),
            .BCLRI, .BEXTI, .BINVI, .BSETI => try rri(w, i),
        },
    }
}

fn bad(w: *Writer, what: []const u8, i: Instruction) !void {
    try w.print("!BAD {s} op={s} rd={d} rs1={d} rs2={d} imm={d}", .{ what, i.op.name(), i.rd, i.rs1, i.rs2, i.imm });
}

fn renderCompressed(w: *Writer, i: Instruction, cop: rv32c.Opcode) !void {
    const base: rv32i.Opcode = switch (cop) {
        .C_ADDI4SPN, .C_ADDI, .C_LI, .C_ADDI16SP => .ADDI,
        .C_LW, .C_LWSP => .LW,
        .C_SW, .C_SWSP => .SW,
        .C_JAL, .C_J => .JAL,
        .C_LUI => .LUI,
        .C_SRLI => .SRLI,
        .C_SRAI => .SRAI,
        .C_ANDI => .ANDI,
        .C_SUB => .SUB,
        .C_XOR => .XOR,
        .C_OR => .OR,
        .C_AND => .AND,
        .C_BEQZ => .BEQ,
        .C_BNEZ => .BNE,
        .C_SLLI => .SLLI,
        .C_JR, .C_JALR => .JALR,
        .C_MV, .C_ADD => .ADD,
        .C_EBREAK => .EBREAK,
    };
    const base_ok = switch (i.op) {
        .i => |op| op == base,
        else => false,
    };
    if (!base_ok) return bad(w, "base-op", i);
    var mbuf: [16]u8 = undefined;
    const m = std.ascii.lowerString(&mbuf, cop.name()); // "c.addi" etc.
    switch (cop) {
        .C_ADDI4SPN => {
            if (i.rs1 != 2) return bad(w, "rs1!=sp", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.writeAll(", ");
            try reg(w, i.rs1);
            try w.print(", {d}", .{i.imm});
        },
        .C_LW, .C_LWSP => {
            if (cop == .C_LWSP and i.rs1 != 2) return bad(w, "rs1!=sp", i);
            try mem(w, m, i.rd, i.imm, i.rs1);
        },
        .C_SW, .C_SWSP => {
            if (cop == .C_SWSP and i.rs1 != 2) return bad(w, "rs1!=sp", i);
            try mem(w, m, i.rs2, i.imm, i.rs1);
        },
        .C_ADDI => {
            if (i.rd != i.rs1) return bad(w, "rd!=rs1", i);
            if (i.rd == 0) {
                // C.NOP (imm = 0) and the C.NOP HINTs (imm != 0)
                if (i.imm == 0) try w.writeAll("c.nop") else try w.print("c.nop {d}", .{i.imm});
            } else {
                try w.print("{s} ", .{m});
                try reg(w, i.rd);
                try w.print(", {d}", .{i.imm});
            }
        },
        .C_LI => {
            if (i.rs1 != 0) return bad(w, "rs1!=0", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.print(", {d}", .{i.imm});
        },
        .C_ADDI16SP => {
            if (i.rd != 2 or i.rs1 != 2) return bad(w, "rd/rs1!=sp", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.print(", {d}", .{i.imm});
        },
        .C_LUI => {
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.print(", {d}", .{upper20(i.imm)});
        },
        .C_SRLI, .C_SRAI, .C_ANDI, .C_SLLI => {
            if (i.rd != i.rs1) return bad(w, "rd!=rs1", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.print(", {d}", .{i.imm});
        },
        .C_SUB, .C_XOR, .C_OR, .C_AND, .C_ADD => {
            if (i.rd != i.rs1) return bad(w, "rd!=rs1", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.writeAll(", ");
            try reg(w, i.rs2);
        },
        .C_MV => {
            if (i.rs1 != 0) return bad(w, "rs1!=0", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rd);
            try w.writeAll(", ");
            try reg(w, i.rs2);
        },
        .C_JAL, .C_J => {
            if (i.rd != @as(u5, if (cop == .C_JAL) 1 else 0)) return bad(w, "link-reg", i);
            try w.print("{s} {d}", .{ m, i.imm });
        },
        .C_BEQZ, .C_BNEZ => {
            if (i.rs2 != 0) return bad(w, "rs2!=0", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rs1);
            try w.print(", {d}", .{i.imm});
        },
        .C_JR, .C_JALR => {
            if (i.rd != @as(u5, if (cop == .C_JALR) 1 else 0) or i.imm != 0) return bad(w, "link/imm", i);
            try w.print("{s} ", .{m});
            try reg(w, i.rs1);
        },
        .C_EBREAK => try w.writeAll("c.ebreak"),
    }
}

/// The fields of an encoding the decoder accepted that a stricter decoder might require
/// to be zero: lists the non-zero ones. Only used to group divergences in the report.
pub fn diagnose(w: *Writer, i: Instruction) !void {
    const raw = i.raw;
    const rd: u5 = @truncate(raw >> 7);
    const rs1: u5 = @truncate(raw >> 15);
    const rs2: u5 = @truncate(raw >> 20);
    if (i.compressed_op != null) return w.writeAll("compressed");
    switch (i.op) {
        .i => |op| switch (op) {
            .ECALL, .EBREAK => {
                if (rd != 0) try w.writeAll("rd!=0 ");
                if (rs1 != 0) try w.writeAll("rs1!=0 ");
            },
            .FENCE => {
                const fm: u4 = @truncate(raw >> 28);
                const pred: u4 = @truncate(raw >> 24);
                const succ: u4 = @truncate(raw >> 20);
                if (fm == 8) {
                    if (pred != 3 or succ != 3) try w.writeAll("fm=1000(non-TSO pred/succ) ");
                } else if (fm != 0) try w.writeAll("fm=reserved ");
                if (rd != 0) try w.writeAll("rd!=0 ");
                if (rs1 != 0) try w.writeAll("rs1!=0 ");
            },
            .FENCE_I => {
                if (raw >> 20 != 0) try w.writeAll("imm!=0 ");
                if (rd != 0) try w.writeAll("rd!=0 ");
                if (rs1 != 0) try w.writeAll("rs1!=0 ");
            },
            else => try w.writeAll("other "),
        },
        .a => |op| {
            if (op == .LR_W and rs2 != 0) try w.writeAll("rs2!=0 ") else try w.writeAll("other ");
        },
        else => try w.writeAll("other "),
    }
}
