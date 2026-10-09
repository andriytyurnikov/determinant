const std = @import("std");
const loader = @import("loader.zig");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.TestCpu;

/// A minimal ELF32 RISC-V executable built field by field (little-endian): a code
/// segment at 0x1000 holding `code`, and a .bss-like segment at 0x2000 with 4 bytes of
/// data and 12 more zero-filled.
const Image = struct {
    bytes: [52 + 2 * 32 + 16 + 4]u8 = @splat(0),

    fn build(text: []const u8, entry: u32) Image {
        std.debug.assert(text.len == 16);
        var img: Image = .{};
        const b = &img.bytes;
        b[0..4].* = "\x7fELF".*;
        b[4] = 1; // ELFCLASS32
        b[5] = 1; // ELFDATA2LSB
        b[6] = 1; // EV_CURRENT
        put16(b, 16, 2); // ET_EXEC
        put16(b, 18, 243); // EM_RISCV
        put32(b, 20, 1); // e_version
        put32(b, 24, entry);
        put32(b, 28, 52); // e_phoff
        put16(b, 40, 52); // e_ehsize
        put16(b, 42, 32); // e_phentsize
        put16(b, 44, 2); // e_phnum
        // PT_LOAD: code, file offset 116 -> 0x1000
        put32(b, 52, 1);
        put32(b, 56, 116);
        put32(b, 60, 0x1000);
        put32(b, 68, 16);
        put32(b, 72, 16);
        put32(b, 76, 5); // PF_R | PF_X
        // PT_LOAD: data, file offset 132 -> 0x2000, 4 bytes in the file, 16 in memory
        put32(b, 84, 1);
        put32(b, 88, 132);
        put32(b, 92, 0x2000);
        put32(b, 100, 4);
        put32(b, 104, 16);
        put32(b, 108, 6); // PF_R | PF_W
        @memcpy(b[116..132], text);
        b[132..136].* = .{ 0xAA, 0xBB, 0xCC, 0xDD };
        return img;
    }

    fn put16(b: []u8, offset: usize, v: u16) void {
        std.mem.writeInt(u16, b[offset..][0..2], v, .little);
    }

    fn put32(b: []u8, offset: usize, v: u32) void {
        std.mem.writeInt(u32, b[offset..][0..4], v, .little);
    }
};

const code = [_]u8{
    0x93, 0x00, 0xA0, 0x02, // ADDI x1, x0, 42
    0x13, 0x00, 0x00, 0x00, // NOP
    0x13, 0x00, 0x00, 0x00, // NOP
    0x73, 0x00, 0x10, 0x00, // EBREAK
};

test "loadElf: copies segments, zero-fills .bss and returns the entry point" {
    var cpu = Cpu.init();
    @memset(cpu.memory[0x2000..0x2010], 0xEE); // dirty memory the .bss must clear
    const img = Image.build(&code, 0x1000);
    const entry = try loader.loadElf(&cpu, &img.bytes);
    try std.testing.expectEqual(@as(u32, 0x1000), entry);
    try std.testing.expectEqualSlices(u8, &code, cpu.memory[0x1000..0x1010]);
    try std.testing.expectEqualSlices(u8, &.{ 0xAA, 0xBB, 0xCC, 0xDD }, cpu.memory[0x2000..0x2004]);
    for (cpu.memory[0x2004..0x2010]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);

    cpu.pc = entry;
    try std.testing.expectEqual(cpu_mod.StepResult.ebreak, try cpu.run(100));
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
}

test "loadElf: rejects what is not a RISC-V ELF32 LE executable, changing nothing" {
    const Bad = struct { offset: usize, value: u8 };
    const bad_bytes = [_]Bad{
        .{ .offset = 0, .value = 0x7E }, // magic
        .{ .offset = 4, .value = 2 }, // ELFCLASS64
        .{ .offset = 5, .value = 2 }, // big-endian
        .{ .offset = 16, .value = 3 }, // ET_DYN
        .{ .offset = 18, .value = 62 }, // EM_X86_64
        .{ .offset = 24, .value = 0x01 }, // odd entry point (0x1001)
        .{ .offset = 42, .value = 16 }, // e_phentsize smaller than a program header
        .{ .offset = 56, .value = 0xFF }, // code segment's file offset beyond the image
        .{ .offset = 100, .value = 0x20 }, // data segment p_filesz (32) runs past the end of the file
        .{ .offset = 104, .value = 2 }, // data segment p_memsz (2) < p_filesz (4)
    };
    const good = Image.build(&code, 0x1000);
    var cpu = Cpu.init();
    const before = cpu.stateDigest();
    for (bad_bytes) |b| {
        var img = good;
        img.bytes[b.offset] = b.value;
        try std.testing.expectError(error.InvalidElf, loader.loadElf(&cpu, &img.bytes));
        try std.testing.expectEqualSlices(u8, &before, &cpu.stateDigest());
    }
    try std.testing.expectError(error.InvalidElf, loader.loadElf(&cpu, good.bytes[0..40])); // truncated
    try std.testing.expectError(error.InvalidElf, loader.loadElf(&cpu, &code)); // flat binary
}

test "loadElf: a segment beyond memory is AddressOutOfBounds, changing nothing" {
    var img = Image.build(&code, 0x1000);
    Image.put32(&img.bytes, 92, Cpu.mem_size - 8); // data segment: 16 bytes at the last 8
    var cpu = Cpu.init();
    const before = cpu.stateDigest();
    try std.testing.expectError(error.AddressOutOfBounds, loader.loadElf(&cpu, &img.bytes));
    try std.testing.expectEqualSlices(u8, &before, &cpu.stateDigest());
}

test "loadElf: a segment may end at the top of memory, and the file right after the program headers" {
    var img = Image.build(&code, 0x1000);
    // Both segments become .bss only (no file bytes), so the file can end with the
    // program header table; the second one ends exactly at the top of memory.
    for ([_]usize{ 52, 84 }) |ph| {
        Image.put32(&img.bytes, ph + 4, 0); // p_offset
        Image.put32(&img.bytes, ph + 16, 0); // p_filesz
    }
    Image.put32(&img.bytes, 84 + 8, Cpu.mem_size - 16); // second p_vaddr; p_memsz is 16
    var cpu = Cpu.init();
    @memset(cpu.memory[Cpu.mem_size - 16 ..], 0xEE);
    try std.testing.expectEqual(@as(u32, 0x1000), try loader.loadElf(&cpu, img.bytes[0..116]));
    for (cpu.memory[Cpu.mem_size - 16 ..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "loadElf: zero-filling .bss drops an LR reservation" {
    var cpu = Cpu.init();
    cpu.reservation = 0x2008; // in the .bss part (0x2004..0x2010) of the data segment
    const img = Image.build(&code, 0x1000);
    _ = try loader.loadElf(&cpu, &img.bytes);
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "segments: the PT_LOAD segments, with their flags, of a valid image" {
    const img = Image.build(&code, 0x1000);
    var it = try loader.segments(&img.bytes);
    try std.testing.expectEqual(loader.Segment{ .offset = 116, .vaddr = 0x1000, .filesz = 16, .memsz = 16, .flags = 5 }, it.next().?);
    try std.testing.expectEqual(loader.Segment{ .offset = 132, .vaddr = 0x2000, .filesz = 4, .memsz = 16, .flags = 6 }, it.next().?);
    try std.testing.expectEqual(@as(?loader.Segment, null), it.next());

    var bad = img;
    bad.bytes[56] = 0xFF; // code segment's file offset beyond the image
    try std.testing.expectError(error.InvalidElf, loader.segments(&bad.bytes));
    // Where the segments go is loadElf's check, not this one.
    var high = img;
    Image.put32(&high.bytes, 92, 0xFFFF_0000);
    _ = try loader.segments(&high.bytes);
}

test "isElf" {
    try std.testing.expect(loader.isElf("\x7fELF\x01"));
    try std.testing.expect(!loader.isElf("\x7fEL"));
    try std.testing.expect(!loader.isElf(&code));
}
