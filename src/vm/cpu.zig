//! Namespace hub for the CPU subsystem — re-exports CpuType, Cpu, StepResult, DecodeFn.

const core = @import("cpu/cpu.zig");

pub const CpuType = core.CpuType;
pub const Cpu = core.Cpu;
pub const StepResult = core.StepResult;
pub const DecodeFn = core.DecodeFn;
pub const default_memory_size = core.default_memory_size;

test {
    _ = core;
}
