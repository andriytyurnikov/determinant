//! Disassembly: printInstruction (one row per form), listings and --disassemble.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const main_mod = @import("../main.zig");
const disasm = main_mod.disasm;
const h = @import("test_helpers.zig");
const Instruction = det.Instruction;

const Case = struct { inst: Instruction, pc: ?u32 = null, want: []const u8 };

const cases = [_]Case{
    // RV32I
    .{ .inst = .{ .op = .{ .i = .ADD }, .rd = 1, .rs1 = 2, .rs2 = 3, .raw = 0 }, .want = "ADD ra, sp, gp" },
    .{ .inst = .{ .op = .{ .i = .ADDI }, .rd = 1, .rs1 = 2, .imm = 42, .raw = 0 }, .want = "ADDI ra, sp, 42" },
    .{ .inst = .{ .op = .{ .i = .ADDI }, .rd = 1, .rs1 = 2, .imm = -1, .raw = 0 }, .want = "ADDI ra, sp, -1" },
    .{ .inst = .{ .op = .{ .i = .SLLI }, .rd = 10, .rs1 = 10, .imm = 3, .raw = 0 }, .want = "SLLI a0, a0, 3" },
    .{ .inst = .{ .op = .{ .i = .LW }, .rd = 5, .rs1 = 10, .imm = 100, .raw = 0 }, .want = "LW t0, 100(a0)" },
    .{ .inst = .{ .op = .{ .i = .JALR }, .rd = 1, .rs1 = 5, .imm = 0, .raw = 0 }, .want = "JALR ra, 0(t0)" },
    .{ .inst = .{ .op = .{ .i = .SW }, .rs1 = 1, .rs2 = 3, .imm = 8, .raw = 0 }, .want = "SW gp, 8(ra)" },
    .{ .inst = .{ .op = .{ .i = .SB }, .rs1 = 2, .rs2 = 31, .imm = -4, .raw = 0 }, .want = "SB t6, -4(sp)" },
    .{ .inst = .{ .op = .{ .i = .LUI }, .rd = 1, .imm = 0x12345000, .raw = 0 }, .want = "LUI ra, 0x12345" },
    .{ .inst = .{ .op = .{ .i = .AUIPC }, .rd = 2, .imm = @bitCast(@as(u32, 0xFFFFF000)), .raw = 0 }, .want = "AUIPC sp, 0xFFFFF" },
    .{ .inst = .{ .op = .{ .i = .ECALL }, .raw = 0 }, .want = "ECALL" },
    .{ .inst = .{ .op = .{ .i = .EBREAK }, .raw = 0 }, .want = "EBREAK" },
    .{ .inst = .{ .op = .{ .i = .FENCE }, .raw = 0 }, .want = "FENCE" },
    .{ .inst = .{ .op = .{ .i = .FENCE_I }, .raw = 0 }, .want = "FENCE.I" },
    // Branch and jump targets: absolute with the address, a signed offset without it
    .{ .inst = .{ .op = .{ .i = .BEQ }, .rs1 = 1, .rs2 = 2, .imm = 16, .raw = 0 }, .want = "BEQ ra, sp, +16" },
    .{ .inst = .{ .op = .{ .i = .BNE }, .rs1 = 10, .rs2 = 0, .imm = -8, .raw = 0 }, .want = "BNE a0, zero, -8" },
    .{ .inst = .{ .op = .{ .i = .BEQ }, .rs1 = 1, .rs2 = 2, .imm = 16, .raw = 0 }, .pc = 0x40, .want = "BEQ ra, sp, 0x00000050" },
    .{ .inst = .{ .op = .{ .i = .BGEU }, .rs1 = 1, .rs2 = 2, .imm = -0x48, .raw = 0 }, .pc = 0x40, .want = "BGEU ra, sp, 0xFFFFFFF8" }, // wraps
    .{ .inst = .{ .op = .{ .i = .JAL }, .rd = 1, .imm = 100, .raw = 0 }, .want = "JAL ra, +100" },
    .{ .inst = .{ .op = .{ .i = .JAL }, .rd = 0, .imm = 0, .raw = 0 }, .pc = 0x1000, .want = "JAL zero, 0x00001000" },
    // RV32M
    .{ .inst = .{ .op = .{ .m = .MUL }, .rd = 3, .rs1 = 1, .rs2 = 2, .raw = 0 }, .want = "MUL gp, ra, sp" },
    // RV32A
    .{ .inst = .{ .op = .{ .a = .LR_W }, .rd = 1, .rs1 = 2, .raw = 0 }, .want = "LR.W ra, (sp)" },
    .{ .inst = .{ .op = .{ .a = .SC_W }, .rd = 1, .rs1 = 2, .rs2 = 3, .raw = 0 }, .want = "SC.W ra, gp, (sp)" },
    .{ .inst = .{ .op = .{ .a = .AMOSWAP_W }, .rd = 1, .rs1 = 2, .rs2 = 3, .raw = 0 }, .want = "AMOSWAP.W ra, gp, (sp)" },
    // Zicsr: the CSRs SEMANTICS.md lists by name, any other by number
    .{ .inst = .{ .op = .{ .csr = .CSRRW }, .rd = 1, .rs1 = 2, .imm = -1024, .raw = 0 }, .want = "CSRRW ra, cycle, sp" },
    .{ .inst = .{ .op = .{ .csr = .CSRRS }, .rd = 10, .rs1 = 0, .imm = -894, .raw = 0 }, .want = "CSRRS a0, instreth, zero" }, // 0xC82
    .{ .inst = .{ .op = .{ .csr = .CSRRWI }, .rd = 1, .rs1 = 5, .imm = 0x340, .raw = 0 }, .want = "CSRRWI ra, mscratch, 5" },
    .{ .inst = .{ .op = .{ .csr = .CSRRC }, .rd = 1, .rs1 = 2, .imm = 0x300, .raw = 0 }, .want = "CSRRC ra, 0x300, sp" },
    .{ .inst = .{ .op = .{ .csr = .CSRRSI }, .rd = 1, .rs1 = 1, .imm = 0x7, .raw = 0 }, .want = "CSRRSI ra, 0x007, 1" },
    // Zba, Zbb, Zbs
    .{ .inst = .{ .op = .{ .zba = .SH1ADD }, .rd = 3, .rs1 = 1, .rs2 = 2, .raw = 0 }, .want = "SH1ADD gp, ra, sp" },
    .{ .inst = .{ .op = .{ .zbb = .CLZ }, .rd = 2, .rs1 = 1, .raw = 0 }, .want = "CLZ sp, ra" },
    .{ .inst = .{ .op = .{ .zbb = .RORI }, .rd = 2, .rs1 = 1, .imm = 5, .raw = 0 }, .want = "RORI sp, ra, 5" },
    .{ .inst = .{ .op = .{ .zbb = .ANDN }, .rd = 3, .rs1 = 1, .rs2 = 2, .raw = 0 }, .want = "ANDN gp, ra, sp" },
    .{ .inst = .{ .op = .{ .zbs = .BSET }, .rd = 3, .rs1 = 1, .rs2 = 2, .raw = 0 }, .want = "BSET gp, ra, sp" },
    .{ .inst = .{ .op = .{ .zbs = .BSETI }, .rd = 3, .rs1 = 1, .imm = 5, .raw = 0 }, .want = "BSETI gp, ra, 5" },
    // RV32C: the compressed name, the expanded operands
    .{ .inst = .{ .op = .{ .i = .ADDI }, .rd = 1, .rs1 = 1, .imm = 5, .raw = 0, .compressed_op = .C_ADDI }, .want = "C.ADDI ra, ra, 5" },
    .{ .inst = .{ .op = .{ .i = .SW }, .rs1 = 2, .rs2 = 1, .imm = 44, .raw = 0, .compressed_op = .C_SWSP }, .want = "C.SWSP ra, 44(sp)" },
};

test "printInstruction: table" {
    for (cases) |c| {
        var aw: Io.Writer.Allocating = .init(h.alloc);
        defer aw.deinit();
        try disasm.printInstruction(&aw.writer, c.inst, c.pc);
        try std.testing.expectEqualStrings(c.want, aw.written());
    }
}

test "reg_names: the RISC-V ABI names" {
    const want = "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6";
    var names = std.mem.splitScalar(u8, want, ' ');
    for (disasm.reg_names) |name| try std.testing.expectEqualStrings(names.next().?, name);
}

test "printListing: 16- and 32-bit instructions, what does not decode, and a cut-off end" {
    const memory = h.le(&.{0x06400093}) // ADDI ra, zero, 100
        ++ [_]u8{ 0x05, 0x05 } // C.ADDI a0, 1
        ++ h.le(&.{0xFFFFFFFF}) // does not decode
        ++ [_]u8{ 0x00, 0x00 } // the all-zero halfword: illegal
        ++ [_]u8{ 0x13, 0x00 }; // the first half of a 32-bit instruction
    var aw: Io.Writer.Allocating = .init(h.alloc);
    defer aw.deinit();
    try disasm.printListing(&aw.writer, &memory, 0, memory.len);
    try std.testing.expectEqualStrings(
        \\00000000  06400093  ADDI ra, zero, 100
        \\00000004  0505      C.ADDI a0, a0, 1
        \\00000006  FFFFFFFF  ???
        \\0000000A  0000      ???
        \\
    , aw.written());
}

test "--disassemble: a flat binary from its load address, on stdout" {
    try h.needMemory(0x110);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("prog.bin", &(h.le(&.{0x00000463}) ++ h.ebreak)); // BEQ zero, zero, +8
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ "--disassemble", prog, "--load-addr", "0x100" }));
    try std.testing.expectEqualStrings(
        \\00000100  00000463  BEQ zero, zero, 0x00000108
        \\00000104  00100073  EBREAK
        \\
    , fx.stdout());
    try std.testing.expectEqualStrings("", fx.stderr());
}

test "--disassemble: an ELF file's executable segments only" {
    try h.needMemory(0x50);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const code = comptime h.le(&.{ 0x02A00093, 0x00100073 }); // ADDI ra, zero, 42; EBREAK
    const exec = try fx.file("exec.elf", &h.tinyElf(&code, 0x40, 5)); // PF_R | PF_X
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ exec, "--disassemble" }));
    try std.testing.expectEqualStrings(
        \\00000040  02A00093  ADDI ra, zero, 42
        \\00000044  00100073  EBREAK
        \\
    , fx.stdout());

    const data = try fx.file("data.elf", &h.tinyElf(&code, 0x40, 6)); // PF_R | PF_W
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ data, "--disassemble" }));
    try std.testing.expectEqualStrings("", fx.stdout());
}

test "--disassemble --demo: the demo program" {
    try h.needMemory(main_mod.load.demo_program.len);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ "--demo", "--disassemble" }));
    try std.testing.expectStringStartsWith(fx.stdout(), "00000000  06400093  ADDI ra, zero, 100\n");
    try std.testing.expect(std.mem.endsWith(u8, fx.stdout(), "00000010  00000073  ECALL\n"));
}
