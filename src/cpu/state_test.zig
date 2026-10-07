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
    const Small = cpu_mod.CpuType(4096, Cpu.decode);
    const a = Small.init();
    const b = Cpu.init();
    try std.testing.expect(!std.mem.eql(u8, &a.stateDigest(), &b.stateDigest()));
}
