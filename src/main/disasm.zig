//! Disassembly for the CLI's listings, traces and fault reports: ABI register names,
//! CSR names, and absolute branch and jump targets when the instruction's address is
//! known (docs/design/cli.md).

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

/// ABI names of x0..x31.
pub const reg_names = [32][]const u8{
    "zero", "ra", "sp",  "gp",  "tp", "t0", "t1", "t2",
    "s0",   "s1", "a0",  "a1",  "a2", "a3", "a4", "a5",
    "a6",   "a7", "s2",  "s3",  "s4", "s5", "s6", "s7",
    "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

/// The standard name of a CSR that SEMANTICS.md lists (time and timeh trap, but a
/// program may still name them), or null.
pub fn csrName(addr: u12) ?[]const u8 {
    return switch (addr) {
        0x340 => "mscratch",
        0xC00 => "cycle",
        0xC01 => "time",
        0xC02 => "instret",
        0xC80 => "cycleh",
        0xC81 => "timeh",
        0xC82 => "instreth",
        else => null,
    };
}

const Reg = struct {
    n: u5,

    pub fn format(self: Reg, w: *Io.Writer) Io.Writer.Error!void {
        return w.writeAll(reg_names[self.n]);
    }
};

fn reg(n: u5) Reg {
    return .{ .n = n };
}

/// A branch or jump target: absolute when the instruction's address is known,
/// otherwise the offset with an explicit sign, so that it cannot be read as an address.
const Target = struct {
    pc: ?u32,
    offset: i32,

    pub fn format(self: Target, w: *Io.Writer) Io.Writer.Error!void {
        if (self.pc) |pc| return w.print("0x{X:0>8}", .{pc +% @as(u32, @bitCast(self.offset))});
        if (self.offset < 0) return w.print("{d}", .{self.offset});
        return w.print("+{d}", .{self.offset});
    }
};

const Csr = struct {
    addr: u12,

    pub fn format(self: Csr, w: *Io.Writer) Io.Writer.Error!void {
        if (csrName(self.addr)) |name| return w.writeAll(name);
        return w.print("0x{X:0>3}", .{self.addr});
    }
};

/// Print `inst` in assembly syntax. `pc` is its address, if known.
pub fn printInstruction(w: *Io.Writer, inst: det.Instruction, pc: ?u32) Io.Writer.Error!void {
    const op_name = if (inst.compressed_op) |c_op| c_op.name() else inst.op.name();
    const rd = reg(inst.rd);
    const rs1 = reg(inst.rs1);
    const rs2 = reg(inst.rs2);
    const target: Target = .{ .pc = pc, .offset = inst.imm };
    switch (inst.op) {
        .i => |i_op| switch (i_op) {
            .ADD, .SUB, .SLL, .SLT, .SLTU, .XOR, .SRL, .SRA, .OR, .AND => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, rs1, rs2 }),
            .LB, .LH, .LW, .LBU, .LHU, .JALR => try w.print("{s} {f}, {d}({f})", .{ op_name, rd, inst.imm, rs1 }),
            .FENCE, .FENCE_I, .ECALL, .EBREAK => try w.print("{s}", .{op_name}),
            .SB, .SH, .SW => try w.print("{s} {f}, {d}({f})", .{ op_name, rs2, inst.imm, rs1 }),
            .BEQ, .BNE, .BLT, .BGE, .BLTU, .BGEU => try w.print("{s} {f}, {f}, {f}", .{ op_name, rs1, rs2, target }),
            .LUI, .AUIPC => try w.print("{s} {f}, 0x{X}", .{ op_name, rd, inst.immUnsigned() >> 12 }),
            .JAL => try w.print("{s} {f}, {f}", .{ op_name, rd, target }),
            .ADDI, .SLTI, .SLTIU, .XORI, .ORI, .ANDI, .SLLI, .SRLI, .SRAI => try w.print("{s} {f}, {f}, {d}", .{ op_name, rd, rs1, inst.imm }),
        },
        .m => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, rs1, rs2 }),
        .a => |a_op| switch (a_op) {
            .LR_W => try w.print("{s} {f}, ({f})", .{ op_name, rd, rs1 }),
            else => try w.print("{s} {f}, {f}, ({f})", .{ op_name, rd, rs2, rs1 }),
        },
        .csr => |csr_op| {
            const csr: Csr = .{ .addr = inst.csrAddr() };
            switch (csr_op) {
                .CSRRW, .CSRRS, .CSRRC => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, csr, rs1 }),
                .CSRRWI, .CSRRSI, .CSRRCI => try w.print("{s} {f}, {f}, {d}", .{ op_name, rd, csr, inst.rs1 }),
            }
        },
        .zba => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, rs1, rs2 }),
        .zbb => |bb_op| switch (bb_op) {
            .CLZ, .CTZ, .CPOP, .SEXT_B, .SEXT_H, .ZEXT_H, .ORC_B, .REV8 => try w.print("{s} {f}, {f}", .{ op_name, rd, rs1 }),
            .RORI => try w.print("{s} {f}, {f}, {d}", .{ op_name, rd, rs1, inst.imm }),
            .ANDN, .ORN, .XNOR, .MAX, .MAXU, .MIN, .MINU, .ROL, .ROR => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, rs1, rs2 }),
        },
        .zbs => |bs_op| switch (bs_op) {
            .BCLR, .BEXT, .BINV, .BSET => try w.print("{s} {f}, {f}, {f}", .{ op_name, rd, rs1, rs2 }),
            .BCLRI, .BEXTI, .BINVI, .BSETI => try w.print("{s} {f}, {f}, {d}", .{ op_name, rd, rs1, inst.imm }),
        },
    }
}

/// The instruction bits as fetched: 4 hex digits for a 16-bit instruction, 8 for a
/// 32-bit one.
pub const Bits = struct {
    raw: u32,
    /// Pad a 16-bit instruction to the width of a 32-bit one, so that columns line up.
    pad: bool = true,

    pub fn format(self: Bits, w: *Io.Writer) Io.Writer.Error!void {
        if (!det.instructions.isCompressed(self.raw)) return w.print("{X:0>8}", .{self.raw});
        try w.print("{X:0>4}", .{self.raw});
        if (self.pad) try w.writeAll("    ");
    }
};

/// One listing line: address, bits and the instruction (or "???" if it does not decode).
pub fn printLine(w: *Io.Writer, pc: u32, raw: u32) Io.Writer.Error!void {
    try w.print("{X:0>8}  {f}  ", .{ pc, Bits{ .raw = raw } });
    if (det.decode(raw)) |inst| {
        try printInstruction(w, inst, pc);
    } else |_| {
        try w.writeAll("???");
    }
}

/// List the instructions in `memory[start..end]`, one per line. A trailing halfword
/// that cannot hold the 32-bit instruction it starts, or a trailing byte, is not listed.
pub fn printListing(w: *Io.Writer, memory: []const u8, start: u32, end: u32) Io.Writer.Error!void {
    var addr: usize = start;
    while (end - addr >= 2) {
        const half = std.mem.readInt(u16, memory[addr..][0..2], .little);
        const raw: u32 = if (det.instructions.isCompressed(half)) half else blk: {
            if (end - addr < 4) break;
            break :blk std.mem.readInt(u32, memory[addr..][0..4], .little);
        };
        try printLine(w, @intCast(addr), raw);
        try w.writeAll("\n");
        addr += if (det.instructions.isCompressed(raw)) 2 else 4;
    }
}
