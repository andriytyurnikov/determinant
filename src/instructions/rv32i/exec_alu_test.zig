const cpu_mod = @import("../../cpu.zig");
const StepResult = cpu_mod.StepResult;
const h = @import("../test_helpers.zig");

// === Execute tests (I-extension ALU step tests) ===

test "step: table (exec_alu)" {
    try h.expectSteps(&.{
        // ADDI x1, x0, 42 = 0x02A00093
        .{ .name = "ADDI", .inst = 0x02A00093, .result = StepResult.@"continue", .want = &.{.{ 1, 42 }}, .want_pc = 4, .want_cycles = @as(u64, 1) },
        // ADDI x2, x1, -1 = 0xFFF08113
        .{ .name = "ADDI negative", .inst = 0xFFF08113, .regs = &.{.{ 1, 100 }}, .want = &.{.{ 2, 99 }} },
        // ADD x3, x1, x2 = 0x002081B3
        .{ .name = "ADD", .inst = 0x002081B3, .regs = &.{ .{ 1, 5 }, .{ 2, 10 } }, .want = &.{.{ 3, 15 }} },
        // SUB x3, x1, x2 = 0x402081B3
        .{ .name = "SUB", .inst = 0x402081B3, .regs = &.{ .{ 1, 20 }, .{ 2, 7 } }, .want = &.{.{ 3, 13 }} },
        // SUB x3, x1, x2
        .{ .name = "SUB wrapping", .inst = 0x402081B3, .regs = &.{ .{ 1, 0 }, .{ 2, 1 } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        // SLL x3, x1, x2 = 0x002091B3
        .{ .name = "SLL", .inst = 0x002091B3, .regs = &.{ .{ 1, 1 }, .{ 2, 4 } }, .want = &.{.{ 3, 16 }} },
        // -1 (0xFFFFFFFF) < 1 signed
        .{ .name = "SLT signed", .inst = 0x0020A1B3, .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want = &.{.{ 3, 1 }} },
        // 0xFFFFFFFF > 1 unsigned
        .{ .name = "SLTU unsigned", .inst = 0x0020B1B3, .regs = &.{ .{ 1, 0xFFFFFFFF }, .{ 2, 1 } }, .want = &.{.{ 3, 0 }} },
        // XOR x3, x1, x2 = 0x0020C1B3
        .{ .name = "XOR", .inst = 0x0020C1B3, .regs = &.{ .{ 1, 0xFF00FF00 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0xF00FF00F }} },
        // SRL x3, x1, x2 = 0x0020D1B3
        .{ .name = "SRL", .inst = 0x0020D1B3, .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 4 } }, .want = &.{.{ 3, 0x08000000 }} },
        // SRA x3, x1, x2 = 0x4020D1B3
        .{ .name = "SRA", .inst = 0x4020D1B3, .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 4 } }, .want = &.{.{ 3, 0xF8000000 }} },
        // OR x3, x1, x2 = 0x0020E1B3
        .{ .name = "OR", .inst = 0x0020E1B3, .regs = &.{ .{ 1, 0xF0F0F0F0 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0xFFFFFFFF }} },
        // AND x3, x1, x2 = 0x0020F1B3
        .{ .name = "AND", .inst = 0x0020F1B3, .regs = &.{ .{ 1, 0xFF00FF00 }, .{ 2, 0x0F0F0F0F } }, .want = &.{.{ 3, 0x0F000F00 }} },
        // SLTI x2, x1, 10 = 0x00A0A113
        .{ .name = "SLTI", .inst = 0x00A0A113, .regs = &.{.{ 1, 5 }}, .want = &.{.{ 2, 1 }} },
        // SLTIU x2, x1, 10 = 0x00A0B113
        .{ .name = "SLTIU", .inst = 0x00A0B113, .regs = &.{.{ 1, 5 }}, .want = &.{.{ 2, 1 }} },
        // XORI x2, x1, 0x0F = 0x00F0C113
        .{ .name = "XORI", .inst = 0x00F0C113, .regs = &.{.{ 1, 0xFF }}, .want = &.{.{ 2, 0xF0 }} },
        // ORI x2, x1, 0x0F = 0x00F0E113
        .{ .name = "ORI", .inst = 0x00F0E113, .regs = &.{.{ 1, 0xF0 }}, .want = &.{.{ 2, 0xFF }} },
        // ANDI x2, x1, 0x0F = 0x00F0F113
        .{ .name = "ANDI", .inst = 0x00F0F113, .regs = &.{.{ 1, 0xFF }}, .want = &.{.{ 2, 0x0F }} },
        // SLLI x2, x1, 31 = 0x01F09113
        .{ .name = "SLLI", .inst = 0x01F09113, .regs = &.{.{ 1, 1 }}, .want = &.{.{ 2, 0x80000000 }} },
        // SRLI x2, x1, 31 = 0x01F0D113
        .{ .name = "SRLI", .inst = 0x01F0D113, .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 2, 1 }} },
        // SRAI x2, x1, 31 = 0x41F0D113
        .{ .name = "SRAI", .inst = 0x41F0D113, .regs = &.{.{ 1, 0x80000000 }}, .want = &.{.{ 2, 0xFFFFFFFF }} },
        // SLLI x2, x1, 0 = 0x00009113
        .{ .name = "shift by 0", .inst = 0x00009113, .regs = &.{.{ 1, 42 }}, .want = &.{.{ 2, 42 }} },
        // ADDI x0, x0, 42 — should not change x0
        .{ .name = "x0 writes ignored", .inst = 0x02A00013, .want_raw = &.{.{ 0, 0 }} },
        // SLTI x2, x1, 1
        .{ .name = "SLTI is a signed compare", .inst = h.encodeI(0b0010011, 0b010, 2, 1, 1), .regs = &.{.{ 1, 0xFFFFFFFF }}, .want = &.{.{ 2, 1 }} },
        // SRL x3, x1, x2
        .{ .name = "SRL by 31", .inst = h.encodeR(0b0110011, 0b101, 0b0000000, 3, 1, 2), .regs = &.{ .{ 1, 0x80000000 }, .{ 2, 31 } }, .want = &.{.{ 3, 1 }} },
        // ANDI x2, x1, -241
        .{ .name = "ANDI sign-extends its immediate", .inst = h.encodeI(0b0010011, 0b111, 2, 1, 0xF0F), .regs = &.{.{ 1, 0x12345678 }}, .want = &.{.{ 2, 0x12345608 }} },
        // SLTU x3, x1, x2
        .{ .name = "SLTU with equal operands yields 0", .inst = h.encodeR(0b0110011, 0b011, 0b0000000, 3, 1, 2), .regs = &.{ .{ 1, 7 }, .{ 2, 7 } }, .want = &.{.{ 3, 0 }} },
    });
}
