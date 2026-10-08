const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const decoders = @import("../decoders.zig");
const instructions = @import("../instructions.zig");
const h = @import("../instructions/test_helpers.zig");
const Cpu = cpu_mod.TestCpu;

/// Store an instruction word into any CpuType's memory (the shared helpers take TestCpu).
fn storeWord(cpu: anytype, addr: u32, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[addr..][0..4], word, .little);
}

const addi_x1_1: u32 = 0x00100093; // ADDI x1, x0, 1
const addi_x1_2: u32 = 0x00200093; // ADDI x1, x0, 2

test "decode cache: code rewritten by a guest store runs the new instruction" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, addi_x1_1);
    h.storeWordAt(&cpu, 4, h.encodeS(0b010, 0, 2, 0)); // SW x2, 0(x0)
    h.storeWordAt(&cpu, 8, h.encodeJ(0, -8)); // JAL x0, -8 → back to 0
    cpu.writeReg(2, addi_x1_2); // the replacement instruction
    _ = try cpu.step(); // ADDI x1, x0, 1 (now cached)
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(1));
    _ = try cpu.step(); // SW overwrites address 0
    _ = try cpu.step(); // JAL back to 0
    _ = try cpu.step(); // must execute the new ADDI x1, x0, 2
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(1));
}

test "decode cache: code rewritten by the host runs the new instruction" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, addi_x1_1);
    _ = try cpu.step();
    cpu.pc = 0;
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, addi_x1_2, .little);
    try cpu.loadProgram(&bytes, 0);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(1));
}

test "decode cache: instructions sharing a slot both run correctly" {
    var cpu = Cpu.init();
    const far = 2 * Cpu.decode_cache_entries; // same slot as address 0
    h.storeWordAt(&cpu, 0, 0x00108093); // ADDI x1, x1, 1
    h.storeWordAt(&cpu, 4, h.encodeJ(0, @intCast(far - 4))); // JAL x0, → far
    h.storeWordAt(&cpu, far, 0x00110113); // ADDI x2, x2, 1
    h.storeWordAt(&cpu, far + 4, h.encodeJ(0, -@as(i21, @intCast(far + 4)))); // JAL x0, → 0
    for (0..40) |_| _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(2));
}

var decode_calls: usize = 0;
fn countingDecode(raw: u32) decoders.DecodeError!instructions.Instruction {
    decode_calls += 1;
    return decoders.decode(raw);
}

/// A 3-instruction loop run for `n` iterations; returns the number of decode() calls.
fn loopDecodeCalls(comptime CpuT: type, n: u32) !usize {
    var cpu = CpuT.init();
    storeWord(&cpu, 0, 0x00108093); // ADDI x1, x1, 1
    storeWord(&cpu, 4, 0x00110113); // ADDI x2, x2, 1
    storeWord(&cpu, 8, h.encodeJ(0, -8)); // JAL x0, -8
    decode_calls = 0;
    for (0..3 * n) |_| _ = try cpu.step();
    try std.testing.expectEqual(n, cpu.readReg(1));
    return decode_calls;
}

test "decode cache: a loop decodes each instruction once" {
    const Cached = cpu_mod.CpuType(4096, .{ .decode = &countingDecode });
    try std.testing.expectEqual(@as(usize, 3), try loopDecodeCalls(Cached, 100));
}

test "decode cache: 0 entries disables it" {
    const Uncached = cpu_mod.CpuType(4096, .{ .decode = &countingDecode, .decode_cache_entries = 0 });
    try std.testing.expectEqual(@as(usize, 300), try loopDecodeCalls(Uncached, 100));
}

test "decode cache: a decode error is not cached" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, 0xFFFFFFFF); // illegal
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
    h.storeWordAt(&cpu, 0, addi_x1_1);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(1));
}

test "decode cache: an illegal instruction faults again when the host retries it" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, addi_x1_1);
    _ = try cpu.step(); // caches ADDI x1, x0, 1 in the slot of address 0
    cpu.pc = 0;
    h.storeWordAt(&cpu, 0, 0xFFFFFFFF); // the host overwrites it with an illegal word
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
    // The fault changed nothing, so a retry must fault again. A slot that recorded the
    // illegal bits before the decode failed would hit and run the stale ADDI.
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "decode cache: reset() of a VM in zero-filled memory leaves no stale hits" {
    // A VM in freshly mapped pages or in static storage starts zeroed (Debug builds
    // fill new allocations with 0xAA instead, so zero it here). A zeroed slot claims
    // raw = 0, which is what fetch() returns for the illegal all-zero halfword, so
    // reset() must empty every slot.
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    @memset(std.mem.asBytes(cpu), 0);
    cpu.reset();
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "decode cache: the cache size never changes the final state" {
    // A loop that rewrites one of its own instructions on every iteration: the
    // immediate of the ADDI at address 4 goes up by one each time round.
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 1, 1, 1), //   0: ADDI x1, x1, 1
        h.encodeI(0b0010011, 0b000, 5, 0, 0), //   4: ADDI x5, x0, <n>   (rewritten)
        h.encodeI(0b0000011, 0b010, 3, 0, 4), //   8: LW   x3, 4(x0)
        h.encodeU(0b0110111, 6, 0x00100), //      12: LUI  x6, 0x100     (imm + 1)
        h.encodeR(0b0110011, 0b000, 0, 3, 3, 6), // 16: ADD  x3, x3, x6
        h.encodeS(0b010, 0, 3, 4), //             20: SW   x3, 4(x0)
        h.encodeI(0b0010011, 0b010, 4, 1, 100), // 24: SLTI x4, x1, 100
        h.encodeB(0b001, 4, 0, -28), //           28: BNE  x4, x0, 0
        0x00100073, //                            32: EBREAK
    };
    var digests: [4][32]u8 = undefined;
    inline for (.{ 0, 1, 2, 4096 }, 0..) |entries, k| {
        const C = cpu_mod.CpuType(4096, .{ .decode_cache_entries = entries });
        var cpu = C.init();
        for (program, 0..) |word, i| storeWord(&cpu, @intCast(4 * i), word);
        try std.testing.expectEqual(cpu_mod.StepResult.ebreak, try cpu.run(10_000));
        try std.testing.expectEqual(@as(u32, 100), cpu.readReg(1));
        try std.testing.expectEqual(@as(u32, 99), cpu.readReg(5)); // the last rewritten ADDI ran
        digests[k] = cpu.stateDigest();
    }
    for (digests[1..]) |d| try std.testing.expectEqualSlices(u8, &digests[0], &d);
}

test "decode cache: not part of the state digest" {
    var a = Cpu.init();
    var b = Cpu.init();
    h.storeWordAt(&a, 0, addi_x1_1);
    h.storeWordAt(&b, 0, addi_x1_1);
    _ = try a.step(); // fills a cache slot in `a` only
    a.pc = 0;
    a.cycle_count = 0;
    a.regs = b.regs;
    try std.testing.expectEqualSlices(u8, &b.stateDigest(), &a.stateDigest());
}
