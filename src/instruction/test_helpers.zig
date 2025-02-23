const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;

pub fn loadInst(cpu: *Cpu, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[cpu.pc..][0..4], word, .little);
}

pub fn storeWordAt(cpu: *Cpu, addr: u32, val: u32) void {
    const a: usize = addr;
    std.mem.writeInt(u32, cpu.memory[a..][0..4], val, .little);
}

pub fn readWordAt(cpu: *const Cpu, addr: u32) u32 {
    const a: usize = addr;
    return std.mem.readInt(u32, cpu.memory[a..][0..4], .little);
}
