const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");
const Instruction = det.Instruction;

const alloc = std.testing.allocator;

fn expectDisassembly(inst: Instruction, expected: []const u8) !void {
    var aw: Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try main_mod.printInstruction(&aw.writer, inst);
    try std.testing.expectEqualStrings(expected, aw.written());
}

// --- RV32I ---

test "printInstruction: R-type ADD" {
    try expectDisassembly(.{
        .op = .{ .i = .ADD },
        .rd = 1,
        .rs1 = 2,
        .rs2 = 3,
        .raw = 0,
    }, "ADD x1, x2, x3");
}

test "printInstruction: I-ALU ADDI" {
    try expectDisassembly(.{
        .op = .{ .i = .ADDI },
        .rd = 1,
        .rs1 = 2,
        .imm = 42,
        .raw = 0,
    }, "ADDI x1, x2, 42");
}

test "printInstruction: I-ALU ADDI negative immediate" {
    try expectDisassembly(.{
        .op = .{ .i = .ADDI },
        .rd = 1,
        .rs1 = 2,
        .imm = -1,
        .raw = 0,
    }, "ADDI x1, x2, -1");
}

test "printInstruction: load LW" {
    try expectDisassembly(.{
        .op = .{ .i = .LW },
        .rd = 5,
        .rs1 = 10,
        .imm = 100,
        .raw = 0,
    }, "LW x5, 100(x10)");
}

test "printInstruction: JALR" {
    try expectDisassembly(.{
        .op = .{ .i = .JALR },
        .rd = 1,
        .rs1 = 5,
        .imm = 0,
        .raw = 0,
    }, "JALR x1, 0(x5)");
}

test "printInstruction: store SW" {
    try expectDisassembly(.{
        .op = .{ .i = .SW },
        .rs1 = 1,
        .rs2 = 3,
        .imm = 8,
        .raw = 0,
    }, "SW x3, 8(x1)");
}

test "printInstruction: branch BEQ" {
    try expectDisassembly(.{
        .op = .{ .i = .BEQ },
        .rs1 = 1,
        .rs2 = 2,
        .imm = 16,
        .raw = 0,
    }, "BEQ x1, x2, 16");
}

test "printInstruction: upper LUI" {
    try expectDisassembly(.{
        .op = .{ .i = .LUI },
        .rd = 1,
        .imm = 0x12345000,
        .raw = 0,
    }, "LUI x1, 0x12345");
}

test "printInstruction: upper AUIPC" {
    try expectDisassembly(.{
        .op = .{ .i = .AUIPC },
        .rd = 2,
        .imm = @bitCast(@as(u32, 0xFFFFF000)),
        .raw = 0,
    }, "AUIPC x2, 0xFFFFF");
}

test "printInstruction: JAL" {
    try expectDisassembly(.{
        .op = .{ .i = .JAL },
        .rd = 1,
        .imm = 100,
        .raw = 0,
    }, "JAL x1, 100");
}

test "printInstruction: ECALL" {
    try expectDisassembly(.{
        .op = .{ .i = .ECALL },
        .raw = 0,
    }, "ECALL");
}

test "printInstruction: EBREAK" {
    try expectDisassembly(.{
        .op = .{ .i = .EBREAK },
        .raw = 0,
    }, "EBREAK");
}

test "printInstruction: FENCE" {
    try expectDisassembly(.{
        .op = .{ .i = .FENCE },
        .raw = 0,
    }, "FENCE");
}

test "printInstruction: FENCE_I" {
    try expectDisassembly(.{
        .op = .{ .i = .FENCE_I },
        .raw = 0,
    }, "FENCE.I");
}

// --- RV32M ---

test "printInstruction: MUL" {
    try expectDisassembly(.{
        .op = .{ .m = .MUL },
        .rd = 3,
        .rs1 = 1,
        .rs2 = 2,
        .raw = 0,
    }, "MUL x3, x1, x2");
}

// --- RV32A ---

test "printInstruction: LR.W" {
    try expectDisassembly(.{
        .op = .{ .a = .LR_W },
        .rd = 1,
        .rs1 = 2,
        .raw = 0,
    }, "LR.W x1, (x2)");
}

test "printInstruction: SC.W" {
    try expectDisassembly(.{
        .op = .{ .a = .SC_W },
        .rd = 1,
        .rs1 = 2,
        .rs2 = 3,
        .raw = 0,
    }, "SC.W x1, x3, (x2)");
}

test "printInstruction: AMOSWAP.W" {
    try expectDisassembly(.{
        .op = .{ .a = .AMOSWAP_W },
        .rd = 1,
        .rs1 = 2,
        .rs2 = 3,
        .raw = 0,
    }, "AMOSWAP.W x1, x3, (x2)");
}

// --- Zicsr ---

test "printInstruction: CSRRW register" {
    try expectDisassembly(.{
        .op = .{ .csr = .CSRRW },
        .rd = 1,
        .rs1 = 2,
        .imm = -1024,
        .raw = 0,
    }, "CSRRW x1, 0xC00, x2");
}

test "printInstruction: CSRRWI immediate" {
    try expectDisassembly(.{
        .op = .{ .csr = .CSRRWI },
        .rd = 1,
        .rs1 = 5,
        .imm = 0x340,
        .raw = 0,
    }, "CSRRWI x1, 0x340, 5");
}

// --- Zba ---

test "printInstruction: SH1ADD" {
    try expectDisassembly(.{
        .op = .{ .zba = .SH1ADD },
        .rd = 3,
        .rs1 = 1,
        .rs2 = 2,
        .raw = 0,
    }, "SH1ADD x3, x1, x2");
}

// --- Zbb ---

test "printInstruction: Zbb unary CLZ" {
    try expectDisassembly(.{
        .op = .{ .zbb = .CLZ },
        .rd = 2,
        .rs1 = 1,
        .raw = 0,
    }, "CLZ x2, x1");
}

test "printInstruction: Zbb RORI" {
    try expectDisassembly(.{
        .op = .{ .zbb = .RORI },
        .rd = 2,
        .rs1 = 1,
        .imm = 5,
        .raw = 0,
    }, "RORI x2, x1, 5");
}

test "printInstruction: Zbb binary ANDN" {
    try expectDisassembly(.{
        .op = .{ .zbb = .ANDN },
        .rd = 3,
        .rs1 = 1,
        .rs2 = 2,
        .raw = 0,
    }, "ANDN x3, x1, x2");
}

// --- Zbs ---

test "printInstruction: Zbs R-type BSET" {
    try expectDisassembly(.{
        .op = .{ .zbs = .BSET },
        .rd = 3,
        .rs1 = 1,
        .rs2 = 2,
        .raw = 0,
    }, "BSET x3, x1, x2");
}

test "printInstruction: Zbs I-type BSETI" {
    try expectDisassembly(.{
        .op = .{ .zbs = .BSETI },
        .rd = 3,
        .rs1 = 1,
        .imm = 5,
        .raw = 0,
    }, "BSETI x3, x1, 5");
}

// --- Compressed ---

test "printInstruction: compressed C.ADDI uses compressed name" {
    try expectDisassembly(.{
        .op = .{ .i = .ADDI },
        .rd = 1,
        .rs1 = 1,
        .imm = 5,
        .raw = 0,
        .compressed_op = .C_ADDI,
    }, "C.ADDI x1, x1, 5");
}
