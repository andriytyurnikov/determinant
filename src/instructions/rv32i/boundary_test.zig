const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("../test_helpers.zig");

const encodeR = h.encodeR;
const encodeI = h.encodeI;
const encodeB = h.encodeB;
const encodeS = h.encodeS;
const encodeU = h.encodeU;
const loadInst = h.loadInst;

// === Boundary value tests (wrapping arithmetic, shift masking, sign extension) ===

test "step: table (boundary)" {
    try h.expectSteps(&.{
        // ADDI x2, x1, 1
        .{ .name = "ADDI wrapping 0xFFFFFFFF + 1 = 0", .inst = encodeI(0b0010011, 0b000, 2, 1, 1), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 2, 0 }} },
        // ADDI x2, x1, 1
        .{ .name = "ADDI wrapping 0x7FFFFFFF + 1 = 0x80000000", .inst = encodeI(0b0010011, 0b000, 2, 1, 1), .regs = &.{.{ 1, 0x7FFFFFFF }}, .want = &.{.{ 2, 0x80000000 }} },
        // ADDI x2, x1, -2048 (imm=0x800 sign-extends to 0xFFFFF800)
        .{ .name = "ADDI minimum immediate -2048", .inst = encodeI(0b0010011, 0b000, 2, 1, 0x800), .regs = &.{.{ 1, 0 }}, .want = &.{.{ 2, 0xFFFFF800 }} },
        // ADD x3, x1, x2
        .{ .name = "ADD wrapping 0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFE", .inst = encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2), .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 0xFFFFFFFF } }, .want = &.{.{ 3, 0xFFFFFFFE }} },
        // SLL x3, x1, x2
        .{ .name = "SLL shift masking rs2 >= 32", .inst = encodeR(0b0110011, 0b001, 0b0000000, 3, 1, 2), .regs = &.{ .{ 1, 0xDEADBEEF }, .{ 2, 32 } }, .want = &.{.{ 3, 0xDEADBEEF }} },
        // SRL x3, x1, x2
        .{ .name = "SRL shift masking rs2 = 33", .inst = encodeR(0b0110011, 0b101, 0b0000000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 33 } }, .want = &.{.{ 3, 0x40000000 }} },
        // SRA x3, x1, x2
        .{ .name = "SRA shift masking rs2 = 33", .inst = encodeR(0b0110011, 0b101, 0b0100000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 33 } }, .want = &.{.{ 3, 0xC0000000 }} },
        // SLTIU x2, x1, -1 (imm=0xFFF → sign-extended to 0xFFFFFFFF, interpreted as unsigned)
        .{ .name = "SLTIU with sign-extended immediate (unsigned comparison)", .inst = encodeI(0b0010011, 0b011, 2, 1, 0xFFF), .regs = &.{.{ 1, 0xFFFFFFFE }}, .want = &.{.{ 2, 1 }} },
        // SLTIU x2, x1, -1 (imm=0xFFF → 0xFFFFFFFF unsigned)
        .{ .name = "SLTIU small value vs large unsigned immediate", .inst = encodeI(0b0010011, 0b011, 2, 1, 0xFFF), .regs = &.{.{ 1, 5 }}, .want = &.{.{ 2, 1 }} },
        // BLT x1, x2, +8
        .{ .name = "BLT SIGNED_MIN vs SIGNED_MAX", .inst = encodeB(0b100, 1, 2, 8), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x7FFFFFFF } }, .want_pc = 8 },
        // BGE x1, x2, +8
        .{ .name = "BGE SIGNED_MIN vs SIGNED_MAX not taken", .inst = encodeB(0b101, 1, 2, 8), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x7FFFFFFF } }, .want_pc = 4 },
        // BGE x1, x2, +8: SIGNED_MAX >= SIGNED_MIN, taken
        .{ .name = "BGE SIGNED_MAX vs SIGNED_MIN taken", .inst = encodeB(0b101, 1, 2, 8), .regs = &.{ .{ 1, 0x7FFFFFFF }, .{ 2, 0x80000000 } }, .want_pc = 8 },
        // BGE x1, x2, +8
        .{ .name = "BGE equal values", .inst = encodeB(0b101, 1, 2, 8), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 0x80000000 } }, .want_pc = 8 },
        // BEQ x1, x2, +0 → branch taken, PC unchanged (stays at 0)
        .{ .name = "BEQ self-loop (offset=0)", .inst = encodeB(0b000, 1, 2, 0), .regs = &.{ .{ 1, 42 }, .{ 2, 42 } }, .want_pc = 0 },
        // JALR x2, 4(x1) → target = (0xFFFFFFFF +% 4) & 0xFFFFFFFE = 3 & 0xFFFFFFFE = 2
        .{ .name = "JALR wrapping target address", .inst = encodeI(0b1100111, 0b000, 2, 1, 4), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 2, 4 }}, .want_pc = 2 },
        // Store a known value at address 96
        .{ .name = "LW with negative offset", .inst = encodeI(0b0000011, 0b010, 2, 1, 0xFFC), .regs = &.{.{ 1, 100 }}, .mem = &.{.{ 96, 0xDEADBEEF }}, .want = &.{.{ 2, 0xDEADBEEF }} },
        // JALR x2, 2(x1) → target = (0xFFFFFFFF +% 2) & 0xFFFFFFFE = 1 & 0xFFFFFFFE = 0
        .{ .name = "JALR wraps past u32::MAX to zero", .inst = encodeI(0b1100111, 0b000, 2, 1, 2), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 2, 4 }}, .want_pc = 0 },
        // JALR x2, -1(x1) → imm=0xFFF sign-extended to 0xFFFFFFFF
        .{ .name = "JALR large base + sign-extended negative imm wraps", .inst = encodeI(0b1100111, 0b000, 2, 1, 0xFFF), .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 2, 4 }}, .want_pc = 0x7FFFFFFE },
        // AUIPC x1, 0xFFFFF → result = 0x1000 +% 0xFFFFF000 = 0
        .{ .name = "AUIPC wraps past u32::MAX", .inst = encodeU(0b0010111, 1, 0xFFFFF), .pc = 0x1000, .want = &.{.{ 1, 0 }}, .want_pc = 0x1004 },
    });
}

test "step: LB sign-extension boundary 0x7F positive" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x7F; // max positive i8
    cpu.writeReg(1, 200);
    // LB x2, 0(x1)
    loadInst(&cpu, encodeI(0b0000011, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(0x0000007F, cpu.readReg(2)); // positive, no sign extension
}

test "step: LH sign-extension boundary 0x7FFF positive" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x7FFF, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1)
    loadInst(&cpu, encodeI(0b0000011, 0b001, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(0x00007FFF, cpu.readReg(2)); // positive, no sign extension
}

// === PC/address wrapping arithmetic tests ===

test "step: LBU with address wrapping into valid memory" {
    var cpu = Cpu.init();
    cpu.memory[8] = 0xAB;
    cpu.writeReg(1, 0xFFFFFFFF);
    // LBU x2, 9(x1) → addr = 0xFFFFFFFF +% 9 = 8
    loadInst(&cpu, encodeI(0b0000011, 0b100, 2, 1, 9));
    _ = try cpu.step();
    try std.testing.expectEqual(0xAB, cpu.readReg(2));
}

test "step: SB with address wrapping into valid memory" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0x42);
    // SB x2, 9(x1) → addr = 0xFFFFFFFF +% 9 = 8
    loadInst(&cpu, encodeS(0b000, 1, 2, 9));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u8, 0x42), cpu.memory[8]);
}
