//! Benchmark: runs every C corpus program several times and reports the best time and
//! the speed in MIPS (millions of retired instructions per second), plus the geometric
//! mean over all programs.
//!
//! usage: bench [--runs N] DIR
//!
//! Run with `zig build bench` (always ReleaseFast). Only VM execution is timed, not
//! loading. Compare numbers from the same machine only.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

const BenchCpu = det.CpuType(256 * 1024, det.Cpu.decode);
const max_cycles: u64 = 1_000_000_000;

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
        std.mem.replaceScalar(u8, p, std.fs.path.sep, '/');
        try paths.append(arena, p);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    const vm = try gpa.create(BenchCpu);
    defer gpa.destroy(vm);

    var buf: [4096]u8 = undefined;
    var fw: Io.File.Writer = .init(Io.File.stdout(), io, &buf);
    const out = &fw.interface;
    try out.print("{s:<28} {s:>12} {s:>10} {s:>8}\n", .{ "program", "instructions", "best ms", "MIPS" });

    var log_sum: f64 = 0;
    var total_cycles: u64 = 0;
    var total_ns: u64 = 0;
    for (paths.items) |p| {
        const program = try dir.readFileAlloc(io, p, arena, .limited(BenchCpu.mem_size + 1));
        var best_ns: u64 = std.math.maxInt(u64);
        var cycles: u64 = 0;
        for (0..runs) |_| {
            vm.reset();
            try vm.loadProgram(program, 0);
            const start = Io.Timestamp.now(io, .awake);
            const result = try vm.run(max_cycles);
            const elapsed = start.durationTo(Io.Timestamp.now(io, .awake));
            if (result != .ebreak) {
                std.debug.print("{s}: did not stop at EBREAK\n", .{p});
                std.process.exit(1);
            }
            cycles = vm.cycle_count;
            best_ns = @min(best_ns, @as(u64, @intCast(elapsed.nanoseconds)));
        }
        const mips = @as(f64, @floatFromInt(cycles)) * 1e3 / @as(f64, @floatFromInt(@max(best_ns, 1)));
        log_sum += @log(mips);
        total_cycles += cycles;
        total_ns += best_ns;
        try out.print("{s:<28} {d:>12} {d:>10.2} {d:>8.1}\n", .{ p, cycles, @as(f64, @floatFromInt(best_ns)) / 1e6, mips });
    }
    const n: f64 = @floatFromInt(@max(paths.items.len, 1));
    try out.print("{s:<28} {d:>12} {d:>10.2} {d:>8.1}  (overall)\n", .{ "total", total_cycles, @as(f64, @floatFromInt(total_ns)) / 1e6, @as(f64, @floatFromInt(total_cycles)) * 1e3 / @as(f64, @floatFromInt(@max(total_ns, 1))) });
    try out.print("geometric mean: {d:.1} MIPS (best of {d} runs each)\n", .{ @exp(log_sum / n), runs });
    try out.flush();
}
