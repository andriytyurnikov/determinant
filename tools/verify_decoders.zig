//! Exhaustive decoder equivalence: runs the LUT and branch decoders on every one of
//! the 2^32 possible inputs and compares the complete results (error vs. success,
//! and every Instruction field). Exits 1 on any mismatch.
//!
//! Run with `zig build verify-decoders` (always built ReleaseFast; about 15 s on 4 cores).

const std = @import("std");
const det = @import("determinant");
const lut = det.decoders.lut;
const branch = det.decoders.branch;

const max_samples = 16;

const Stats = struct {
    legal: u64 = 0,
    illegal: u64 = 0,
    mismatches: u64 = 0,
    samples: [max_samples]u32 = undefined,
    n_samples: usize = 0,
};

fn worker(stats: *Stats, start: u64, end: u64) void {
    var x = start;
    while (x < end) : (x += 1) {
        const raw: u32 = @intCast(x);
        const a = lut.decode(raw);
        const b = branch.decode(raw);
        if (!std.meta.eql(a, b)) {
            stats.mismatches += 1;
            if (stats.n_samples < max_samples) {
                stats.samples[stats.n_samples] = raw;
                stats.n_samples += 1;
            }
        } else if (a) |_| {
            stats.legal += 1;
        } else |_| {
            stats.illegal += 1;
        }
    }
}

fn printResult(label: []const u8, r: det.DecodeError!det.Instruction) void {
    if (r) |i| {
        std.debug.print("    {s}: {s} rd={d} rs1={d} rs2={d} imm={d} raw=0x{x:0>8} compressed_op={any}\n", .{ label, i.op.name(), i.rd, i.rs1, i.rs2, i.imm, i.raw, i.compressed_op });
    } else |e| {
        std.debug.print("    {s}: error.{s}\n", .{ label, @errorName(e) });
    }
}

pub fn main() !void {
    const n_threads = @min(std.Thread.getCpuCount() catch 4, 64);
    var stats: [64]Stats = @splat(.{});
    var threads: [64]std.Thread = undefined;
    const total: u64 = 1 << 32;
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

    std.debug.print("LUT vs branch decoder over all 2^32 inputs ({d} threads): {d} legal, {d} illegal, {d} mismatches\n", .{ n_threads, sum.legal, sum.illegal, sum.mismatches });
    if (sum.legal + sum.illegal + sum.mismatches != total) {
        std.debug.print("error: checked {d} inputs, expected {d}\n", .{ sum.legal + sum.illegal + sum.mismatches, total });
        std.process.exit(1);
    }
    if (sum.mismatches != 0) {
        for (sum.samples[0..sum.n_samples]) |raw| {
            std.debug.print("  mismatch at 0x{x:0>8}\n", .{raw});
            printResult("lut   ", lut.decode(raw));
            printResult("branch", branch.decode(raw));
        }
        std.process.exit(1);
    }
}
