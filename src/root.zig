//! Public API for the Determinant RISC-V VM library.

const std = @import("std");

pub const cpu = @import("cpu.zig");
pub const instructions = @import("instructions.zig");
pub const decoders = @import("decoders.zig");
/// Reference decoder (branch-based) — kept for conformance testing and documentation.
pub const branch_decoder = decoders.branch;

// Convenience aliases
pub const CpuType = cpu.CpuType;
pub const Cpu = cpu.Cpu;
pub const default_memory_size = cpu.default_memory_size;
pub const DecodeFn = cpu.DecodeFn;
pub const StepResult = cpu.StepResult;
pub const Instruction = instructions.Instruction;
pub const Opcode = instructions.Opcode;
pub const Format = instructions.Format;
/// Decode via primary (LUT-based) decoder — used by cpu.zig for execution. Prefer for performance.
pub const decode = decoders.lut.decode;
/// Decode via reference (branch-based) decoder — for conformance testing and readability.
pub const decodeBranch = branch_decoder.decode;
pub const DecodeError = decoders.DecodeError;

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

test "integration: load, fetch, LUT decode" {
    var machine = cpu.Cpu.init();
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

test "integration: LUT and branch decoders agree on demo instruction" {
    const raw: u32 = 0x02A00093; // ADDI x1, x0, 42
    const lut_inst = try decode(raw);
    const branch_inst = try decodeBranch(raw);
    try std.testing.expectEqual(lut_inst.op, branch_inst.op);
    try std.testing.expectEqual(lut_inst.rd, branch_inst.rd);
    try std.testing.expectEqual(lut_inst.rs1, branch_inst.rs1);
    try std.testing.expectEqual(lut_inst.imm, branch_inst.imm);
}
