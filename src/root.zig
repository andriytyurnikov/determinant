const std = @import("std");
const vm = @import("vm.zig");

pub const cpu = vm.cpu;
pub const instructions = vm.instructions;
pub const decoders = vm.decoders;
/// Reference decoder (branch-based) — kept for conformance testing and documentation.
pub const branch_decoder = vm.decoders.branch_decoder;

// Convenience aliases
pub const CpuType = cpu.CpuType;
pub const Cpu = cpu.Cpu;
pub const StepResult = cpu.StepResult;
pub const Instruction = instructions.Instruction;
pub const Opcode = instructions.Opcode;
pub const Format = instructions.Format;
/// Decode via primary (LUT-based) decoder — used by cpu.zig for execution. Prefer for performance.
pub const decode = vm.decoders.lut_decoder.decode;
/// Decode via reference (branch-based) decoder — for conformance testing and readability.
pub const decodeBranch = branch_decoder.decode;
pub const DecodeError = vm.decoders.DecodeError;

test {
    std.testing.refAllDecls(@This());
}

test "integration: load, fetch, decode" {
    var machine = cpu.Cpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    const program = [_]u8{ 0x93, 0x00, 0xA0, 0x02 };
    try machine.loadProgram(&program, 0);
    const raw = try machine.fetch();
    const inst = try decodeBranch(raw);
    try std.testing.expectEqual(instructions.Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 42), inst.imm);
}

test "regression: demo program second instruction encodes ADDI x2, x0, 10" {
    // Bytes from main.zig line 19 — ADDI x2, x0, 10 = 0x00A00113.
    // Previously had 0x0A/0xA0 transposed, encoding ADDI x2, x20, 0 instead.
    const demo_bytes = [_]u8{ 0x13, 0x01, 0xA0, 0x00 };
    const raw = std.mem.readInt(u32, &demo_bytes, .little);
    const inst = try decodeBranch(raw);

    try std.testing.expectEqual(instructions.Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 2), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 10), inst.imm);
}
