//! Public API for the Determinant RISC-V VM library.

const std = @import("std");

pub const cpu = @import("cpu.zig");
pub const instructions = @import("instructions.zig");
pub const decoders = @import("decoders.zig");

// Convenience aliases
pub const CpuType = cpu.CpuType;
pub const CpuOptions = cpu.Options;
pub const Cpu = cpu.Cpu;
pub const default_memory_size = cpu.default_memory_size;
pub const DecodeFn = cpu.DecodeFn;
pub const StepResult = cpu.StepResult;
pub const StepError = cpu.StepError;
pub const Fault = cpu.Fault;
pub const Instruction = instructions.Instruction;
pub const Opcode = instructions.Opcode;
pub const Format = instructions.Format;
/// Decode a 32-bit word or a zero-extended 16-bit RV32C halfword into an Instruction.
pub const decode = decoders.decode;
pub const DecodeError = decoders.DecodeError;

test {
    std.testing.refAllDecls(@This());
}

test "integration: load, fetch, decode" {
    var machine = cpu.TestCpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    const program = [_]u8{ 0x93, 0x00, 0xA0, 0x02 };
    try machine.loadProgram(&program, 0);
    const raw = try machine.fetch();
    const inst = try decode(raw);
    try std.testing.expectEqual(instructions.Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 42), inst.imm);
}
