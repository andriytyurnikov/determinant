const std = @import("std");
const vm = @import("vm.zig");

pub const cpu = vm.cpu;
pub const instructions = vm.instructions;
pub const decoder = vm.decoders.branch_decoder;
pub const rv32i = instructions.rv32i;
pub const rv32m = instructions.rv32m;
pub const rv32a = instructions.rv32a;
pub const zicsr = instructions.zicsr;
pub const zba = instructions.zba;
pub const zbb = instructions.zbb;
pub const zbs = instructions.zbs;

// Convenience aliases
pub const Cpu = cpu.Cpu;
pub const StepResult = cpu.StepResult;
pub const Instruction = instructions.Instruction;
pub const Opcode = instructions.Opcode;
pub const Format = instructions.Format;
pub const decode = decoder.decode;
pub const DecodeError = decoder.DecodeError;

test {
    std.testing.refAllDecls(@This());
}

test "integration: load, fetch, decode" {
    var machine = cpu.Cpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    const program = [_]u8{ 0x93, 0x00, 0xA0, 0x02 };
    try machine.loadProgram(&program, 0);
    const raw = try machine.fetch();
    const inst = try decoder.decode(raw);
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
    const inst = try decoder.decode(raw);

    try std.testing.expectEqual(instructions.Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 2), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 10), inst.imm);
}
