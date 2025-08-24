//! Namespace hub for the VM subsystem — re-exports cpu, instructions, decoders.

pub const cpu = @import("vm/cpu.zig");
pub const instructions = @import("vm/instructions.zig");
pub const decoders = @import("vm/decoders.zig");

test {
    _ = cpu;
    _ = instructions;
    _ = decoders;
}
