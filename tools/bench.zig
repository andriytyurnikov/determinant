//! Benchmark: runs every C corpus program several times on each kind of VM memory
//! (CpuType's, inside the VM, and RuntimeCpuType's, a host buffer) and reports the best
//! time and the speed in MIPS (millions of retired instructions per second), plus the
//! geometric mean over all programs.
//!
//! usage: bench [--runs N] DIR
//!
//! Run with `zig build bench` (always -Doptimize=fast). Only VM execution is timed, not
//! loading. Compare numbers from the same machine only.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

const bench_memory = 256 * 1024;
const FixedCpu = det.CpuType(bench_memory, .{});
const RuntimeCpu = det.RuntimeCpuType(.{});
const max_cycles: u64 = 1_000_000_000;

const Best = struct { cycles: u64, ns: u64 };

/// The best of `runs` runs of `program` on `vm`.
fn best(vm: anytype, program: []const u8, runs: usize, io: Io, name: []const u8) !Best {
    var result: Best = .{ .cycles = 0, .ns = std.math.maxInt(u64) };
    for (0..runs) |_| {
        vm.reset();
        try vm.loadProgram(program, 0);
        const start = Io.Timestamp.now(io, .awake);
        const stop = try vm.run(max_cycles);
        const elapsed = start.durationTo(Io.Timestamp.now(io, .awake));
        if (stop != .ebreak) {
            std.debug.print("{s}: did not stop at EBREAK\n", .{name});
            std.process.exit(1);
        }
        result.cycles = vm.cycle_count;
        result.ns = @min(result.ns, @as(u64, @intCast(elapsed.nanoseconds)));
    }
    return result;
}

fn mips(b: Best) f64 {
    return @as(f64, @floatFromInt(b.cycles)) * 1e3 / @as(f64, @floatFromInt(@max(b.ns, 1)));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var runs: usize = 5;
    var dir_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--runs") and i + 1 < args.len) {
            i += 1;
            runs = try std.fmt.parseInt(usize, args[i], 10);
        } else {
            dir_path = args[i];
        }
    }
    const root = dir_path orelse {
        std.debug.print("usage: bench [--runs N] DIR\n", .{});
        std.process.exit(2);
    };

    var dir = try Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var paths: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".bin") or entry.basename[0] == '.') continue;
        const p = try arena.dupe(u8, entry.path);
        std.mem.replaceScalar(u8, p, std.Io.Dir.path.sep, '/');
        try paths.append(arena, p);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    const fixed = try gpa.create(FixedCpu);
    defer gpa.destroy(fixed);
    const memory = try gpa.alloc(u8, bench_memory);
    defer gpa.free(memory);
    const runtime = try gpa.create(RuntimeCpu);
    defer gpa.destroy(runtime);
    try runtime.initInPlace(memory);

    var buf: [4096]u8 = undefined;
    var fw: Io.File.Writer = .initStreaming(Io.File.stdout(), io, &buf);
    const out = &fw.interface;
    try out.print("{s:<28} {s:>12} {s:>10} {s:>8} {s:>10} {s:>8}\n", .{ "program", "instructions", "fixed ms", "MIPS", "runtime ms", "MIPS" });

    var log_sum: [2]f64 = .{ 0, 0 };
    var total: [2]Best = .{ .{ .cycles = 0, .ns = 0 }, .{ .cycles = 0, .ns = 0 } };
    for (paths.items) |p| {
        const program = try dir.readFileAlloc(io, p, arena, .limited(bench_memory + 1));
        const results = [2]Best{ try best(fixed, program, runs, io, p), try best(runtime, program, runs, io, p) };
        if (results[0].cycles != results[1].cycles) {
            std.debug.print("{s}: {d} cycles with fixed memory, {d} with runtime memory\n", .{ p, results[0].cycles, results[1].cycles });
            std.process.exit(1);
        }
        for (results, 0..) |r, k| {
            log_sum[k] += @log(mips(r));
            total[k].cycles += r.cycles;
            total[k].ns += r.ns;
        }
        try out.print("{s:<28} {d:>12} {d:>10.2} {d:>8.1} {d:>10.2} {d:>8.1}\n", .{ p, results[0].cycles, @as(f64, @floatFromInt(results[0].ns)) / 1e6, mips(results[0]), @as(f64, @floatFromInt(results[1].ns)) / 1e6, mips(results[1]) });
    }
    const n: f64 = @floatFromInt(@max(paths.items.len, 1));
    try out.print("{s:<28} {d:>12} {d:>10.2} {d:>8.1} {d:>10.2} {d:>8.1}  (overall)\n", .{ "total", total[0].cycles, @as(f64, @floatFromInt(total[0].ns)) / 1e6, mips(total[0]), @as(f64, @floatFromInt(total[1].ns)) / 1e6, mips(total[1]) });
    try out.print("geometric mean: {d:.1} MIPS with fixed memory, {d:.1} with runtime memory (best of {d} runs each)\n", .{ @exp(log_sum[0] / n), @exp(log_sum[1] / n), runs });
    try out.flush();
}
