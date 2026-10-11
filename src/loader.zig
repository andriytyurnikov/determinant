//! ELF32 RISC-V executable loader (docs/design/program-loading.md).
//!
//! Every header field is read with an explicit little-endian integer read from the byte
//! image — never a struct cast — so loading behaves the same on every host. Segments
//! are copied with loadProgram(), which respects LR reservations.

const std = @import("std");

pub const LoadError = error{
    /// Not a RISC-V ELF32 little-endian executable, or a malformed one.
    InvalidElf,
    /// A segment does not fit inside the VM's memory.
    AddressOutOfBounds,
};

const elf_header_len = 52;
const program_header_len = 32;
const ELFCLASS32 = 1;
const ELFDATA2LSB = 1;
const EV_CURRENT = 1;
const ET_EXEC = 2;
const EM_RISCV = 243;
const PT_LOAD = 1;

/// True if `image` starts with the ELF magic.
pub fn isElf(image: []const u8) bool {
    return image.len >= 4 and std.mem.eql(u8, image[0..4], "\x7fELF");
}

/// A PT_LOAD segment: `filesz` bytes at `offset` in the file go to `vaddr`, and the
/// rest of `memsz` is zero-filled. `flags` holds PF_X, PF_W and PF_R.
pub const Segment = struct { offset: u32, vaddr: u32, filesz: u32, memsz: u32, flags: u32 };

/// Segment flag: the segment holds code.
pub const PF_X = 1;

/// The PT_LOAD segments of an image, in program-header order.
pub const Segments = struct {
    image: []const u8,
    phoff: u64,
    phentsize: u64,
    phnum: u64,
    index: u64 = 0,

    pub fn next(self: *Segments) ?Segment {
        while (self.index < self.phnum) {
            const ph = self.phoff + self.index * self.phentsize;
            self.index += 1;
            if (segment(self.image, ph)) |s| return s;
        }
        return null;
    }
};

/// The PT_LOAD segments of a RISC-V ELF32 executable, for example to find its code.
/// The image gets the checks loadElf makes on the file; whether the segments fit in a
/// VM's memory is checked only by loadElf.
pub fn segments(image: []const u8) error{InvalidElf}!Segments {
    return (try parse(image)).segments;
}

/// Load every PT_LOAD segment of a RISC-V ELF32 executable into `vm` (any CpuType)
/// and return its entry point. Each segment's file bytes go to p_vaddr and the rest
/// of p_memsz is zero-filled. Everything is validated before anything is written, so
/// a rejected image leaves the VM unchanged.
pub fn loadElf(vm: anytype, image: []const u8) LoadError!u32 {
    const elf = try parse(image);
    const mem_size: u64 = vm.memory.len;
    var check = elf.segments;
    while (check.next()) |s| {
        if (@as(u64, s.vaddr) + s.memsz > mem_size) return error.AddressOutOfBounds;
    }
    var load = elf.segments;
    while (load.next()) |s| {
        vm.loadProgram(image[s.offset..][0..s.filesz], s.vaddr) catch unreachable; // validated above
        const bss_start: usize = @as(usize, s.vaddr) + s.filesz;
        const bss_end: usize = @as(usize, s.vaddr) + s.memsz;
        if (bss_end > bss_start) {
            @memset(vm.memory[bss_start..bss_end], 0);
            vm.clearReservation(); // a direct memory write
        }
    }
    return elf.entry;
}

/// The entry point and the segments of a valid image: everything is checked except
/// where the segments go in memory.
fn parse(image: []const u8) error{InvalidElf}!struct { entry: u32, segments: Segments } {
    if (image.len < elf_header_len or !isElf(image)) return error.InvalidElf;
    if (image[4] != ELFCLASS32 or image[5] != ELFDATA2LSB or image[6] != EV_CURRENT) return error.InvalidElf;
    if (u16At(image, 16) != ET_EXEC or u16At(image, 18) != EM_RISCV or u32At(image, 20) != EV_CURRENT) return error.InvalidElf;
    const entry = u32At(image, 24);
    const phoff: u64 = u32At(image, 28);
    const phentsize: u64 = u16At(image, 42);
    const phnum: u64 = u16At(image, 44);
    if (entry % 2 != 0) return error.InvalidElf;
    if (phnum != 0 and phentsize < program_header_len) return error.InvalidElf;
    if (phoff + phentsize * phnum > image.len) return error.InvalidElf;

    const all: Segments = .{ .image = image, .phoff = phoff, .phentsize = phentsize, .phnum = phnum };
    var it = all;
    while (it.next()) |s| {
        if (@as(u64, s.offset) + s.filesz > image.len) return error.InvalidElf;
        if (s.filesz > s.memsz) return error.InvalidElf;
    }
    return .{ .entry = entry, .segments = all };
}

/// The PT_LOAD segment described at `offset`, or null for other segment types.
fn segment(image: []const u8, offset: u64) ?Segment {
    const ph: usize = @intCast(offset);
    if (u32At(image, ph) != PT_LOAD) return null;
    return .{
        .offset = u32At(image, ph + 4),
        .vaddr = u32At(image, ph + 8),
        .filesz = u32At(image, ph + 16),
        .memsz = u32At(image, ph + 20),
        .flags = u32At(image, ph + 24),
    };
}

fn u16At(image: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, image[offset..][0..2], .little);
}

fn u32At(image: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, image[offset..][0..4], .little);
}

test {
    _ = @import("loader_test.zig");
}
