const std = @import("std");

pub const cpu = @import("cpu.zig");
pub const instruction = @import("instruction.zig");
pub const decoder = @import("decoder.zig");
pub const syscall = @import("syscall.zig");

// Convenience aliases — syscall
pub const SyscallResult = syscall.SyscallResult;
pub const handleSyscall = syscall.handleSyscall;
pub const runWithSyscalls = syscall.runWithSyscalls;

// Convenience aliases
pub const Cpu = cpu.Cpu;
pub const StepResult = cpu.StepResult;
pub const Instruction = instruction.Instruction;
pub const Opcode = instruction.Opcode;
pub const Format = instruction.Format;
pub const decode = decoder.decode;
pub const DecodeError = decoder.DecodeError;

test {
    std.testing.refAllDecls(@This());
}

test "integration: load, fetch, decode" {
    var vm = cpu.Cpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    const program = [_]u8{ 0x93, 0x00, 0xA0, 0x02 };
    try vm.loadProgram(&program, 0);
    const raw = try vm.fetch();
    const inst = try decoder.decode(raw);
    try std.testing.expectEqual(instruction.Opcode.ADDI, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(i32, 42), inst.imm);
}
