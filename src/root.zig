const std = @import("std");

pub const cpu = @import("cpu.zig");
pub const instruction = @import("instruction.zig");
pub const decoder = @import("decoder.zig");

// Convenience aliases
pub const Cpu = cpu.Cpu;
pub const Instruction = instruction.Instruction;
pub const Opcode = instruction.Opcode;
pub const Format = instruction.Format;
pub const decode = decoder.decode;
pub const DecodeError = decoder.DecodeError;

test {
    std.testing.refAllDecls(@This());
}
