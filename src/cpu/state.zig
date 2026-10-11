//! Canonical encoding of VM state: a fixed-size little-endian header followed by the
//! memory image. stateDigest() is the SHA-256 of these bytes, so two VMs have the same
//! digest exactly when their architectural state is identical, whatever the host.

const std = @import("std");
const zicsr = @import("../instructions/zicsr.zig");

pub const magic = "DTRM".*;
/// Bump whenever the encoding changes; digests change with it.
pub const version: u32 = 1;

/// Header layout (all little-endian):
///   0  magic "DTRM"        4  version u32       8  memory size u32   12  pc u32
///   16 regs[0..32] u32 (regs[0] included)       144 cycle_count u64
///   152 reservation valid u32 (0/1)  156 reservation address u32 (0 if none)
///   160 mscratch u32
pub const header_len = 164;

/// Fields of CpuType that the encoding covers. A new field must either be encoded
/// (and `version` bumped) or listed in `excluded_fields` with a reason.
const encoded_fields = [_][]const u8{ "pc", "regs", "memory", "cycle_count", "reservation", "csrs" };
const excluded_fields = [_][]const u8{
    "decode_cache", // a memo of decode(), not architectural state
    "stop_pc", // where the last ECALL/EBREAK was: host-facing metadata
};

comptime {
    // Every CSR must be encoded: update encodeHeader and bump `version` when adding one.
    if (@typeInfo(zicsr.Csr).@"struct".field_names.len != 1) @compileError("zicsr.Csr changed: update cpu/state.zig");
}

fn checkFields(comptime Cpu: type) void {
    comptime {
        for (@typeInfo(Cpu).@"struct".field_names) |field_name| {
            var known = false;
            for (encoded_fields ++ excluded_fields) |name| {
                if (std.mem.eql(u8, field_name, name)) known = true;
            }
            if (!known) @compileError("CpuType field '" ++ field_name ++ "' is not covered by cpu/state.zig");
        }
    }
}

/// Encode everything except memory into the fixed-size header.
pub fn encodeHeader(cpu: anytype) [header_len]u8 {
    const Cpu = @TypeOf(cpu.*);
    checkFields(Cpu);
    var buf: [header_len]u8 = undefined;
    buf[0..4].* = magic;
    std.mem.writeInt(u32, buf[4..8], version, .little);
    std.mem.writeInt(u32, buf[8..12], cpu.memSize(), .little);
    std.mem.writeInt(u32, buf[12..16], cpu.pc, .little);
    for (cpu.regs, 0..) |r, i| std.mem.writeInt(u32, buf[16 + 4 * i ..][0..4], r, .little);
    std.mem.writeInt(u64, buf[144..152], cpu.cycle_count, .little);
    std.mem.writeInt(u32, buf[152..156], @intFromBool(cpu.reservation != null), .little);
    std.mem.writeInt(u32, buf[156..160], cpu.reservation orelse 0, .little);
    std.mem.writeInt(u32, buf[160..164], cpu.csrs.mscratch, .little);
    return buf;
}

/// Write the snapshot: the header followed by the whole memory image (the bytes the
/// digest hashes). See docs/design/snapshots.md.
pub fn writeSnapshot(cpu: anytype, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll(&encodeHeader(cpu));
    try w.writeAll(cpu.memory[0..]);
}

pub const RestoreError = error{InvalidSnapshot} || std.Io.Reader.Error;

/// Restore the architectural state from a snapshot. The header is validated before
/// anything changes. If the reader then fails inside the memory image, the VM is left
/// partly restored (the header's state, some of the memory): reset() or restore again.
pub fn restoreSnapshot(cpu: anytype, r: *std.Io.Reader) RestoreError!void {
    const Cpu = @TypeOf(cpu.*);
    checkFields(Cpu);
    var hdr: [header_len]u8 = undefined;
    try r.readSliceAll(&hdr);
    if (!std.mem.eql(u8, hdr[0..4], &magic)) return error.InvalidSnapshot;
    if (readU32(&hdr, 4) != version) return error.InvalidSnapshot;
    if (readU32(&hdr, 8) != cpu.memSize()) return error.InvalidSnapshot;
    if (readU32(&hdr, 16) != 0) return error.InvalidSnapshot; // regs[0]
    const res_valid = readU32(&hdr, 152);
    const res_addr = readU32(&hdr, 156);
    switch (res_valid) {
        0 => if (res_addr != 0) return error.InvalidSnapshot,
        1 => if (res_addr % 4 != 0 or res_addr > cpu.memSize() - 4) return error.InvalidSnapshot,
        else => return error.InvalidSnapshot,
    }

    cpu.pc = readU32(&hdr, 12);
    for (&cpu.regs, 0..) |*reg, i| reg.* = readU32(&hdr, 16 + 4 * i);
    cpu.cycle_count = std.mem.readInt(u64, hdr[144..152], .little);
    cpu.reservation = if (res_valid == 1) res_addr else null;
    cpu.csrs = .{ .mscratch = readU32(&hdr, 160) };
    try r.readSliceAll(cpu.memory[0..]);
}

/// The memory size in a snapshot's header, from its first 12 or more bytes: the magic,
/// the version and the size. error.InvalidSnapshot if they are not a valid header's.
pub fn memorySize(snapshot_start: []const u8) error{InvalidSnapshot}!u32 {
    if (snapshot_start.len < 12) return error.InvalidSnapshot;
    if (!std.mem.eql(u8, snapshot_start[0..4], &magic)) return error.InvalidSnapshot;
    if (std.mem.readInt(u32, snapshot_start[4..8], .little) != version) return error.InvalidSnapshot;
    const size = std.mem.readInt(u32, snapshot_start[8..12], .little);
    if (size < 4 or size % 4 != 0) return error.InvalidSnapshot;
    return size;
}

fn readU32(hdr: *const [header_len]u8, offset: usize) u32 {
    return std.mem.readInt(u32, hdr[offset..][0..4], .little);
}

/// SHA-256 of the header followed by the whole memory image.
pub fn digest(cpu: anytype) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&encodeHeader(cpu));
    hasher.update(cpu.memory[0..]);
    return hasher.finalResult();
}
