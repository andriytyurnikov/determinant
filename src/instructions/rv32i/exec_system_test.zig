const cpu_mod = @import("../../cpu.zig");
const StepResult = cpu_mod.StepResult;
const h = @import("../test_helpers.zig");

// === Execute tests: system instructions ===

test "step: table (exec_system)" {
    try h.expectSteps(&.{
        .{ .name = "ECALL", .inst = 0x00000073, .result = StepResult.ecall, .want_pc = 4 },
        .{ .name = "EBREAK", .inst = 0x00100073, .result = StepResult.ebreak, .want_pc = 4 },
        // FENCE iorw, iorw = 0x0FF0000F
        .{ .name = "FENCE is no-op", .inst = 0x0FF0000F, .result = StepResult.@"continue", .want_pc = 4, .want_cycles = @as(u64, 1) },
        // FENCE.I = 0x0000100F (opcode=0x0F, funct3=001)
        .{ .name = "FENCE.I is no-op", .inst = 0x0000100F, .result = StepResult.@"continue", .want_pc = 4, .want_cycles = @as(u64, 1) },
        // ECALL with rd = 5
        .{ .name = "ECALL with rd ≠ 0 is a reserved encoding and traps", .inst = 0x00000073 | (5 << 7), .err = error.IllegalInstruction, .want_pc = 0, .want_cycles = @as(u64, 0) },
        // EBREAK with rs1 = 5
        .{ .name = "EBREAK with rs1 ≠ 0 is a reserved encoding and traps", .inst = 0x00100073 | (5 << 15), .err = error.IllegalInstruction, .want_pc = 0, .want_cycles = @as(u64, 0) },
    });
}
