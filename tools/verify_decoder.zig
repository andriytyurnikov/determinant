//! Exhaustive check of the decoder against its specification, the opcode registry
//! (src/decoders/registry.zig): for every one of the 2^30 32-bit encodings (low two bits
//! 0b11), decode() must succeed exactly when a registry entry matches, and must then
//! return that entry's instruction with every operand field. Exits 1 on any mismatch.
//!
//! Run with `zig build verify-decoder` (always ReleaseFast; about a minute on 4 cores).
//! 16-bit RV32C encodings are outside the registry; the rv32c unit tests and the LLVM
//! disassembler comparison cover them.

const std = @import("std");
const det = @import("determinant");
const registry = det.decoders.registry;

const max_samples = 16;

const Stats = struct {
    legal: u64 = 0,
    illegal: u64 = 0,
    mismatches: u64 = 0,
    samples: [max_samples]u32 = undefined,
    n_samples: usize = 0,
};

fn agrees(raw: u32, stats: *Stats) bool {
    const got = det.decode(raw);
    if (registry.lookup(raw)) |e| {
        const inst = got catch return false;
        stats.legal += 1;
        return std.meta.eql(inst, registry.instruction(e, raw));
    }
    if (got) |_| return false else |_| {}
    stats.illegal += 1;
    return true;
}

fn worker(stats: *Stats, start: u64, end: u64) void {
    var x = start;
    while (x < end) : (x += 1) {
        const raw: u32 = @intCast((x << 2) | 0b11);
        if (!agrees(raw, stats)) {
            stats.mismatches += 1;
            if (stats.n_samples < max_samples) {
                stats.samples[stats.n_samples] = raw;
                stats.n_samples += 1;
            }
        }
    }
}

pub fn main() !void {
    const n_threads = @min(std.Thread.getCpuCount() catch 4, 64);
    var stats: [64]Stats = @splat(.{});
    var threads: [64]std.Thread = undefined;
    const total: u64 = 1 << 30;
    const chunk = total / n_threads;
    for (0..n_threads) |t| {
        const end = if (t == n_threads - 1) total else (t + 1) * chunk;
        threads[t] = try std.Thread.spawn(.{}, worker, .{ &stats[t], t * chunk, end });
    }
    for (threads[0..n_threads]) |th| th.join();

    var sum: Stats = .{};
    for (stats[0..n_threads]) |s| {
        sum.legal += s.legal;
        sum.illegal += s.illegal;
        sum.mismatches += s.mismatches;
        for (s.samples[0..s.n_samples]) |raw| {
            if (sum.n_samples < max_samples) {
                sum.samples[sum.n_samples] = raw;
                sum.n_samples += 1;
            }
        }
    }

    std.debug.print("decoder vs registry over all 2^30 32-bit encodings ({d} threads): {d} legal, {d} illegal, {d} mismatches\n", .{ n_threads, sum.legal, sum.illegal, sum.mismatches });
    if (sum.legal + sum.illegal + sum.mismatches != total) {
        std.debug.print("error: checked {d} encodings, expected {d}\n", .{ sum.legal + sum.illegal + sum.mismatches, total });
        std.process.exit(1);
    }
    if (sum.mismatches != 0) {
        for (sum.samples[0..sum.n_samples]) |raw| {
            std.debug.print("  mismatch at 0x{x:0>8}: registry says ", .{raw});
            if (registry.lookup(raw)) |e| std.debug.print("{s}", .{e.op.name()}) else std.debug.print("illegal", .{});
            std.debug.print(", decoder says ", .{});
            if (det.decode(raw)) |inst| std.debug.print("{s}\n", .{inst.op.name()}) else |err| std.debug.print("{s}\n", .{@errorName(err)});
        }
        std.process.exit(1);
    }
}
