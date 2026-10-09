//! Determinism: identical starting states reach identical full states (compared by
//! stateDigest, which covers pc, every register, all memory, cycle_count, the
//! reservation and the CSRs), on every host, with or without the decode cache.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const StepResult = cpu_mod.StepResult;

/// compute (5 + 10) * 3 via shifts and adds, store the result at 256, ECALL
const program = [_]struct { u32, u32 }{
    .{ 0, 0x00500093 }, // ADDI x1, x0, 5
    .{ 4, 0x00A00113 }, // ADDI x2, x0, 10
    .{ 8, 0x002081B3 }, // ADD x3, x1, x2 (x3 = 15)
    .{ 12, 0x00119213 }, // SLLI x4, x3, 1 (x4 = 30)
    .{ 16, 0x003202B3 }, // ADD x5, x4, x3 (x5 = 45)
    .{ 20, 0x10502023 }, // SW x5, 256(x0)
    .{ 24, 0x00000073 }, // ECALL
};

fn loadTestProgram(memory: []u8) void {
    for (program) |entry| {
        std.mem.writeInt(u32, memory[entry[0]..][0..4], entry[1], .little);
    }
}

fn hex(digest: [32]u8) [64]u8 {
    var out: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x}", .{&digest}) catch unreachable;
    return out;
}

test "determinism: the test program reaches a fixed final state on every host" {
    var cpu = Cpu.init();
    loadTestProgram(&cpu.memory);
    try std.testing.expectEqual(StepResult.ecall, try cpu.run(100));
    try std.testing.expectEqual(@as(u32, 45), cpu.readReg(5));
    try std.testing.expectEqual(@as(u32, 45), std.mem.readInt(u32, cpu.memory[256..][0..4], .little));
    // Computed independently from the state encoding: the program words, 45 at
    // address 256, x1..x5 = 5, 10, 15, 30, 45, pc = 28, cycle_count = 7.
    try std.testing.expectEqualStrings("a8786798aa412e14adce33b71b69633259951cbdc7e95451dd68db015dd95e6b", &hex(cpu.stateDigest()));
}

test "determinism: two VMs with the same program reach the same full state" {
    var cpu1 = Cpu.init();
    var cpu2 = Cpu.init();
    loadTestProgram(&cpu1.memory);
    loadTestProgram(&cpu2.memory);
    try std.testing.expectEqual(try cpu1.run(100), try cpu2.run(100));
    try std.testing.expectEqualSlices(u8, &cpu1.stateDigest(), &cpu2.stateDigest());
}

test "determinism: stepping two VMs in turn equals running each alone" {
    // No state is shared between VMs: interleaving them changes nothing.
    var alone = Cpu.init();
    loadTestProgram(&alone.memory);
    _ = try alone.run(100);

    var a = Cpu.init();
    var b = Cpu.init();
    loadTestProgram(&a.memory);
    loadTestProgram(&b.memory);
    b.writeReg(1, 99); // b diverges from a
    for (0..program.len) |_| {
        _ = try a.step();
        _ = try b.step();
    }
    try std.testing.expectEqualSlices(u8, &alone.stateDigest(), &a.stateDigest());
}

test "determinism: the decode cache never changes the final state" {
    const Uncached = cpu_mod.CpuType(Cpu.mem_size, .{ .decode_cache_entries = 0 });
    var cached = Cpu.init();
    var uncached = Uncached.init();
    loadTestProgram(&cached.memory);
    loadTestProgram(&uncached.memory);
    _ = try cached.run(100);
    _ = try uncached.run(100);
    try std.testing.expectEqualSlices(u8, &cached.stateDigest(), &uncached.stateDigest());
}
