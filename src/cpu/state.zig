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
};

comptime {
    // Every CSR must be encoded: update encodeHeader and bump `version` when adding one.
    if (std.meta.fields(zicsr.Csr).len != 1) @compileError("zicsr.Csr changed: update cpu/state.zig");
}

fn checkFields(comptime Cpu: type) void {
    comptime {
        for (std.meta.fields(Cpu)) |f| {
            var known = false;
            for (encoded_fields ++ excluded_fields) |name| {
                if (std.mem.eql(u8, f.name, name)) known = true;
            }
            if (!known) @compileError("CpuType field '" ++ f.name ++ "' is not covered by cpu/state.zig");
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
    std.mem.writeInt(u32, buf[8..12], Cpu.mem_size, .little);
    std.mem.writeInt(u32, buf[12..16], cpu.pc, .little);
    for (cpu.regs, 0..) |r, i| std.mem.writeInt(u32, buf[16 + 4 * i ..][0..4], r, .little);
    std.mem.writeInt(u64, buf[144..152], cpu.cycle_count, .little);
    std.mem.writeInt(u32, buf[152..156], @intFromBool(cpu.reservation != null), .little);
    std.mem.writeInt(u32, buf[156..160], cpu.reservation orelse 0, .little);
    std.mem.writeInt(u32, buf[160..164], cpu.csrs.mscratch, .little);
    return buf;
}

/// SHA-256 of the header followed by the whole memory image.
pub fn digest(cpu: anytype) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(&encodeHeader(cpu));
    hasher.update(&cpu.memory);
    return hasher.finalResult();
}
