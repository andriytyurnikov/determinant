const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const state = @import("state.zig");
const Cpu = cpu_mod.TestCpu;

test "state: header layout is explicit little-endian" {
    var cpu = Cpu.init();
    cpu.pc = 0x11223344;
    cpu.regs[1] = 0xAABBCCDD;
    cpu.cycle_count = 0x0102030405060708;
    cpu.reservation = 0x100;
    cpu.csrs.mscratch = 0xCAFEBABE;
    const hdr = state.encodeHeader(&cpu);
    try std.testing.expectEqualSlices(u8, "DTRM", hdr[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0 }, hdr[4..8]); // version
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x01, 0x00 }, hdr[8..12]); // 64 KiB
    try std.testing.expectEqualSlices(u8, &.{ 0x44, 0x33, 0x22, 0x11 }, hdr[12..16]); // pc
    try std.testing.expectEqualSlices(u8, &.{ 0xDD, 0xCC, 0xBB, 0xAA }, hdr[20..24]); // regs[1]
    try std.testing.expectEqualSlices(u8, &.{ 8, 7, 6, 5, 4, 3, 2, 1 }, hdr[144..152]); // cycle_count
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 0x00, 0x01, 0, 0 }, hdr[152..160]); // reservation
    try std.testing.expectEqualSlices(u8, &.{ 0xBE, 0xBA, 0xFE, 0xCA }, hdr[160..164]); // mscratch
}

test "state: digest of the power-on state is a fixed value on every host" {
    const cpu = Cpu.init();
    // Computed independently: sha256(b"DTRM" + pack("<III", 1, 65536, 0)
    //   + pack("<32I", *[0]*32) + pack("<QIII", 0, 0, 0, 0) + bytes(65536))
    const expected = "992011129d32ce3eba88fffcd98da4d2289f139fa8df92857c474bc51bd2187e";
    var hex: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&hex, "{x}", .{&cpu.stateDigest()});
    try std.testing.expectEqualStrings(expected, &hex);
}

test "state: every part of the state changes the digest" {
    const base = Cpu.init();
    const d0 = base.stateDigest();

    var cpu = base;
    cpu.pc = 4;
    try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));

    for (0..32) |i| {
        cpu = base;
        cpu.regs[i] = 1;
        try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));
    }

    cpu = base;
    cpu.memory[Cpu.mem_size - 1] = 1;
    try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));

    cpu = base;
    cpu.cycle_count = 1 << 40;
    try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));

    // A reservation at address 0 differs from no reservation.
    cpu = base;
    cpu.reservation = 0;
    try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));

    cpu = base;
    cpu.csrs.mscratch = 1;
    try std.testing.expect(!std.mem.eql(u8, &d0, &cpu.stateDigest()));
}

test "state: digest depends on memory size" {
    const Small = cpu_mod.CpuType(4096, .{});
    const a = Small.init();
    const b = Cpu.init();
    try std.testing.expect(!std.mem.eql(u8, &a.stateDigest(), &b.stateDigest()));
}

// --- Snapshots ---

fn busyState(cpu: *Cpu) void {
    cpu.reset();
    cpu.pc = 0x1234;
    for (1..32) |i| cpu.regs[i] = @as(u32, @intCast(i)) *% 0x9E37_79B9;
    for (&cpu.memory, 0..) |*b, i| b.* = @truncate(i *% 31 +% 7);
    cpu.cycle_count = 0x0102_0304_0506_0708;
    cpu.reservation = 0x400;
    cpu.csrs.mscratch = 0xFEED_F00D;
}

test "snapshot: size and bytes are the digest's pre-image" {
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    busyState(cpu);
    const buf = try std.testing.allocator.alloc(u8, Cpu.snapshot_size);
    defer std.testing.allocator.free(buf);
    var w: std.Io.Writer = .fixed(buf);
    try cpu.writeSnapshot(&w);
    try std.testing.expectEqual(Cpu.snapshot_size, w.end);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(buf, &digest, .{});
    try std.testing.expectEqualSlices(u8, &cpu.stateDigest(), &digest);
}

test "snapshot: restore reproduces the state exactly and resumes identically" {
    const a = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(a);
    const b = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(b);
    busyState(a);
    // A tiny loop at pc: ADDI x5, x5, 1; JAL x0, -4
    std.mem.writeInt(u32, a.memory[0x1234..][0..4], 0x00128293, .little);
    std.mem.writeInt(u32, a.memory[0x1238..][0..4], 0xFFDFF06F, .little);
    _ = try a.runFor(7);

    const buf = try std.testing.allocator.alloc(u8, Cpu.snapshot_size);
    defer std.testing.allocator.free(buf);
    var w: std.Io.Writer = .fixed(buf);
    try a.writeSnapshot(&w);

    b.reset();
    b.stop_pc = 99;
    var r: std.Io.Reader = .fixed(buf);
    try b.restoreSnapshot(&r);
    try std.testing.expectEqualSlices(u8, &a.stateDigest(), &b.stateDigest());
    try std.testing.expectEqual(@as(u32, 0), b.stop_pc);

    _ = try a.runFor(100);
    _ = try b.runFor(100);
    try std.testing.expectEqualSlices(u8, &a.stateDigest(), &b.stateDigest());
}

test "snapshot: malformed headers are rejected before anything changes" {
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    busyState(cpu);
    const good = try std.testing.allocator.alloc(u8, Cpu.snapshot_size);
    defer std.testing.allocator.free(good);
    var w: std.Io.Writer = .fixed(good);
    try cpu.writeSnapshot(&w);
    const bad = try std.testing.allocator.alloc(u8, Cpu.snapshot_size);
    defer std.testing.allocator.free(bad);

    const Corruption = struct { offset: usize, value: u32 };
    const corruptions = [_]Corruption{
        .{ .offset = 0, .value = 0x4D52_5445 }, // magic "ETRM"
        .{ .offset = 4, .value = 2 }, // unknown version
        .{ .offset = 8, .value = 4096 }, // other memory size
        .{ .offset = 16, .value = 1 }, // regs[0] != 0
        .{ .offset = 152, .value = 2 }, // reservation flag not 0/1
        .{ .offset = 156, .value = 0x402 }, // unaligned reservation
        .{ .offset = 156, .value = Cpu.mem_size }, // reservation outside memory
    };
    busyState(cpu);
    cpu.pc = 0xAAAA; // differs from the snapshot: must survive a rejected restore
    const before = cpu.stateDigest();
    for (corruptions) |c| {
        @memcpy(bad, good);
        std.mem.writeInt(u32, bad[c.offset..][0..4], c.value, .little);
        var r: std.Io.Reader = .fixed(bad);
        try std.testing.expectError(error.InvalidSnapshot, cpu.restoreSnapshot(&r));
        try std.testing.expectEqualSlices(u8, &before, &cpu.stateDigest());
    }
    // No reservation, but a non-zero address
    @memcpy(bad, good);
    std.mem.writeInt(u32, bad[152..][0..4], 0, .little);
    var r: std.Io.Reader = .fixed(bad);
    try std.testing.expectError(error.InvalidSnapshot, cpu.restoreSnapshot(&r));
    // A truncated snapshot
    var short: std.Io.Reader = .fixed(good[0..100]);
    try std.testing.expectError(error.EndOfStream, cpu.restoreSnapshot(&short));
}
