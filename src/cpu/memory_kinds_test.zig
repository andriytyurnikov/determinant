//! The two kinds of memory: inside the VM (CpuType) and a host buffer (RuntimeCpuType).
//! Every bounds check must give the same result on both, at every size.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const RuntimeCpu = cpu_mod.RuntimeCpu;

const alloc = std.testing.allocator;

/// Every access at the end of memory, on a reset VM: the last byte, halfword and word
/// are inside, the next address is not.
fn expectBoundaries(vm: anytype) !void {
    const size = vm.memSize();
    try vm.writeByte(size - 1, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), try vm.readByte(size - 1));
    try std.testing.expectError(error.AddressOutOfBounds, vm.readByte(size));
    try std.testing.expectError(error.AddressOutOfBounds, vm.writeByte(size, 0));

    try vm.writeHalfword(size - 2, 0xBEEF);
    try std.testing.expectEqual(@as(u16, 0xBEEF), try vm.readHalfword(size - 2));
    try std.testing.expectError(error.AddressOutOfBounds, vm.readHalfword(size));
    try std.testing.expectError(error.AddressOutOfBounds, vm.writeHalfword(size, 0));

    try vm.writeWord(size - 4, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try vm.readWord(size - 4));
    try std.testing.expectError(error.AddressOutOfBounds, vm.readWord(size));
    try std.testing.expectError(error.AddressOutOfBounds, vm.writeWord(size, 0));

    // fetch: a 32-bit instruction in the last word, a 16-bit one in the last halfword
    try vm.loadProgram(&.{ 0x13, 0x00, 0x00, 0x00 }, size - 4); // NOP
    vm.pc = size - 4;
    try std.testing.expectEqual(@as(u32, 0x00000013), try vm.fetch());
    try vm.loadProgram(&.{ 0x01, 0x00 }, size - 2); // C.NOP
    vm.pc = size - 2;
    try std.testing.expectEqual(@as(u32, 0x0001), try vm.fetch());
    try vm.loadProgram(&.{ 0x13, 0x00 }, size - 2); // the low half of a 32-bit instruction
    try std.testing.expectError(error.PCOutOfBounds, vm.fetch());
    vm.pc = size;
    try std.testing.expectError(error.PCOutOfBounds, vm.fetch());

    // loadProgram: up to the last byte, and not one further
    try std.testing.expectError(error.AddressOutOfBounds, vm.loadProgram(&.{ 1, 2 }, size - 1));
    try vm.loadProgram(&.{7}, size - 1);
    try std.testing.expectEqual(@as(u8, 7), try vm.readByte(size - 1));

    // through execution: LW, LR.W, SC.W and an AMO on the last word, then one word on
    // (x1 = the last word's address, x2 = 4)
    const program = [_]u32{
        0x0000A183, // LW x3, 0(x1)
        0x1000A22F, // LR.W x4, (x1)
        0x1830A2AF, // SC.W x5, x3, (x1)
        0x0020A32F, // AMOADD.W x6, x2, (x1)
        0x002080B3, // ADD x1, x1, x2
        0x0000A383, // LW x7, 0(x1): out of bounds
    };
    if (size < 4 * program.len + 4) return; // the program does not fit with its data word
    vm.reset();
    for (program, 0..) |word, i| try vm.writeWord(@intCast(4 * i), word);
    vm.writeReg(1, size - 4);
    vm.writeReg(2, 4);
    try vm.writeWord(size - 4, 40);
    for (0..5) |_| _ = try vm.step();
    try std.testing.expectEqual(@as(u32, 40), vm.readReg(3));
    try std.testing.expectEqual(@as(u32, 0), vm.readReg(5)); // SC.W succeeded
    try std.testing.expectEqual(@as(u32, 40), vm.readReg(6));
    try std.testing.expectEqual(@as(u32, 44), try vm.readWord(size - 4));
    try std.testing.expectError(error.AddressOutOfBounds, vm.step());
}

test "both kinds of memory: the bounds at every size" {
    const sizes = [_]u32{ 4, 12, 28, 4096, 4100, 64 * 1024 };
    inline for (sizes) |size| {
        const Fixed = cpu_mod.CpuType(size, .{});
        const fixed = try alloc.create(Fixed);
        defer alloc.destroy(fixed);
        fixed.reset();
        try expectBoundaries(fixed);

        const memory = try alloc.alloc(u8, size);
        defer alloc.free(memory);
        var runtime = try RuntimeCpu.init(memory);
        try std.testing.expectEqual(size, runtime.memSize());
        try expectBoundaries(&runtime);
    }
}

test "both kinds of memory: the same snapshot and digest for the same state" {
    const size = 4100;
    const Fixed = cpu_mod.CpuType(size, .{});
    const fixed = try alloc.create(Fixed);
    defer alloc.destroy(fixed);
    fixed.reset();
    const memory = try alloc.alloc(u8, size);
    defer alloc.free(memory);
    const runtime = try alloc.create(RuntimeCpu);
    defer alloc.destroy(runtime);
    try runtime.initInPlace(memory);

    for ([_]u32{ 0x02A00093, 0x00102023, 0x00100073 }, 0..) |word, i| { // ADDI x1, x0, 42; SW x1, 0(x0); EBREAK
        try fixed.writeWord(@intCast(4 * i), word);
        try runtime.writeWord(@intCast(4 * i), word);
    }
    try std.testing.expectEqual(try fixed.run(100), try runtime.run(100));
    try std.testing.expectEqual(fixed.stateDigest(), runtime.stateDigest());

    // A snapshot of one kind restores into the other, and says how much memory it needs.
    var snap: std.Io.Writer.Allocating = .init(alloc);
    defer snap.deinit();
    try runtime.writeSnapshot(&snap.writer);
    try std.testing.expectEqual(runtime.snapshotSize(), snap.written().len);
    try std.testing.expectEqual(Fixed.snapshot_size, fixed.snapshotSize());
    try std.testing.expectEqual(@as(u32, size), try cpu_mod.snapshotMemorySize(snap.written()));
    fixed.reset();
    var r: std.Io.Reader = .fixed(snap.written());
    try fixed.restoreSnapshot(&r);
    try std.testing.expectEqual(runtime.stateDigest(), fixed.stateDigest());

    // Not into a VM with another size.
    const other = try alloc.alloc(u8, size + 4);
    defer alloc.free(other);
    var bigger = try RuntimeCpu.init(other);
    r = .fixed(snap.written());
    try std.testing.expectError(error.InvalidSnapshot, bigger.restoreSnapshot(&r));
}

test "snapshotMemorySize: only from the start of a valid header" {
    var snap: std.Io.Writer.Allocating = .init(alloc);
    defer snap.deinit();
    var vm = cpu_mod.CpuType(4096, .{}).init();
    try vm.writeSnapshot(&snap.writer);
    const header = snap.written()[0..12];
    try std.testing.expectEqual(@as(u32, 4096), try cpu_mod.snapshotMemorySize(header));

    try std.testing.expectError(error.InvalidSnapshot, cpu_mod.snapshotMemorySize(header[0..11]));
    var bad = header.*;
    bad[0] = 'X'; // magic
    try std.testing.expectError(error.InvalidSnapshot, cpu_mod.snapshotMemorySize(&bad));
    bad = header.*;
    bad[4] = 2; // version
    try std.testing.expectError(error.InvalidSnapshot, cpu_mod.snapshotMemorySize(&bad));
    for ([_]u32{ 0, 2, 4098 }) |size| {
        bad = header.*;
        std.mem.writeInt(u32, bad[8..12], size, .little);
        try std.testing.expectError(error.InvalidSnapshot, cpu_mod.snapshotMemorySize(&bad));
    }
}

test "RuntimeCpuType.init: the memory size must be valid" {
    var buf: [16]u8 = undefined;
    for ([_]usize{ 0, 1, 2, 3, 5, 6, 7, 10, 15 }) |len| {
        try std.testing.expectError(error.InvalidMemorySize, RuntimeCpu.init(buf[0..len]));
    }
    for ([_]usize{ 4, 8, 12, 16 }) |len| {
        const vm = try RuntimeCpu.init(buf[0..len]);
        try std.testing.expectEqual(@as(u32, @intCast(len)), vm.memSize());
    }

    try std.testing.expect(cpu_mod.validMemorySize(0xFFFF_FFFC));
    try std.testing.expect(!cpu_mod.validMemorySize(0xFFFF_FFFD));
    try std.testing.expect(!cpu_mod.validMemorySize(0xFFFF_FFFE));
    try std.testing.expect(!cpu_mod.validMemorySize(0xFFFF_FFFF));
    if (@bitSizeOf(usize) > 32) {
        try std.testing.expect(!cpu_mod.validMemorySize(0x1_0000_0000));
        try std.testing.expect(!cpu_mod.validMemorySize(0x1_0000_0004));
    }
}

test "RuntimeCpuType: init zeroes the memory, reset keeps it, an invalid size changes nothing" {
    var buf: [64]u8 = @splat(0xEE);
    const vm = try alloc.create(RuntimeCpu);
    defer alloc.destroy(vm);
    try vm.initInPlace(&buf);
    try std.testing.expect(std.mem.allEqual(u8, &buf, 0));
    try vm.writeByte(5, 9);
    vm.writeReg(1, 5);

    var small: [6]u8 = undefined;
    try std.testing.expectError(error.InvalidMemorySize, vm.initInPlace(&small));
    try std.testing.expectEqual(@as([*]u8, &buf), vm.memory.ptr);
    try std.testing.expectEqual(@as(u32, 5), vm.readReg(1));
    try std.testing.expectEqual(@as(u8, 9), try vm.readByte(5));

    vm.reset();
    try std.testing.expectEqual(@as([*]u8, &buf), vm.memory.ptr);
    try std.testing.expectEqual(@as(u32, 64), vm.memSize());
    try std.testing.expectEqual(@as(u8, 0), buf[5]);
}

test "RuntimeCpuType: a copy of the struct shares the memory" {
    var buf: [16]u8 = undefined;
    var a = try RuntimeCpu.init(&buf);
    var b = a;
    try b.writeByte(3, 0x5A);
    b.writeReg(1, 1);
    try std.testing.expectEqual(@as(u8, 0x5A), try a.readByte(3));
    try std.testing.expectEqual(@as(u32, 0), a.readReg(1));
}
