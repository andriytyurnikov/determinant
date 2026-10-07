//! Runs every program (`*.bin`) of the corpus on a fresh VM and prints one line per
//! program, sorted by path:
//!
//!     <root>/<path> <stop> <cycles> <sha256 of the final VM state>
//!
//! where <stop> is `ecall`, `ebreak`, `limit` or `error.<Name>`.
//!
//! usage: corpus_digests [--check FILE] [--expect ROOT=DIR]... [--pass ROOT]...
//!                       [--no-decode-cache] ROOT=DIR...
//!
//!   ROOT=DIR          run every *.bin under DIR, naming it ROOT/<path relative to DIR>
//!   --pass ROOT       programs under ROOT follow the riscv-tests convention: each must
//!                     stop at EBREAK with gp (x3) = 1; exit 1 otherwise
//!   --no-decode-cache run on a VM without the decode cache (results must not change)
//!   --check FILE      compare the lines with FILE instead of printing them; exit 1 on
//!                     any difference
//!   --expect ROOT=DIR programs under ROOT follow the C corpus convention (crt0 ends with
//!                     EBREAK, a0 = result, a1 = address of 16 result words); compare them
//!                     with DIR/<program>.txt, the output of the same C run natively
//!
//! CI checks every job (each OS, optimize mode, endianness and decoder) against the same
//! golden file, tests/digests.txt, so all of them must reach bit-identical final states.
//! After an intended change in guest-visible behavior, regenerate it with
//! `zig build digests > tests/digests.txt` and review the diff.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

/// Every corpus program runs with 256 KiB of memory, like the compliance suite.
const corpus_memory = 256 * 1024;
const CorpusCpu = det.CpuType(corpus_memory, .{});
const UncachedCpu = det.CpuType(corpus_memory, .{ .decode_cache_entries = 0 });
const max_cycles: u64 = 100_000_000;

const Root = struct { name: []const u8, dir: []const u8, expect_dir: ?[]const u8 = null, must_pass: bool = false };

fn usage() noreturn {
    std.debug.print("usage: corpus_digests [--check FILE] [--expect ROOT=DIR]... [--pass ROOT]... [--no-decode-cache] ROOT=DIR...\n", .{});
    std.process.exit(2);
}

fn splitAssignment(arg: []const u8) struct { []const u8, []const u8 } {
    const eq = std.mem.indexOfScalar(u8, arg, '=') orelse usage();
    return .{ arg[0..eq], arg[eq + 1 ..] };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var roots: std.ArrayList(Root) = .empty;
    var expects: std.ArrayList(Root) = .empty;
    var passes: std.ArrayList([]const u8) = .empty;
    var check_path: ?[]const u8 = null;
    var decode_cache = true;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--no-decode-cache")) {
            decode_cache = false;
        } else if (std.mem.eql(u8, args[i], "--check")) {
            i += 1;
            if (i == args.len) usage();
            check_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--pass")) {
            i += 1;
            if (i == args.len) usage();
            try passes.append(arena, args[i]);
        } else if (std.mem.eql(u8, args[i], "--expect")) {
            i += 1;
            if (i == args.len) usage();
            const name, const dir = splitAssignment(args[i]);
            try expects.append(arena, .{ .name = name, .dir = dir });
        } else {
            const name, const dir = splitAssignment(args[i]);
            try roots.append(arena, .{ .name = name, .dir = dir });
        }
    }
    if (roots.items.len == 0) usage();
    for (expects.items) |e| {
        for (roots.items) |*r| {
            if (std.mem.eql(u8, r.name, e.name)) r.expect_dir = e.dir;
        }
    }
    for (passes.items) |name| {
        for (roots.items) |*r| {
            if (std.mem.eql(u8, r.name, name)) r.must_pass = true;
        }
    }

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var counts: Counts = .{};
    if (decode_cache) {
        try runCorpus(CorpusCpu, io, gpa, arena, roots.items, &out.writer, &counts);
    } else {
        try runCorpus(UncachedCpu, io, gpa, arena, roots.items, &out.writer, &counts);
    }
    const n_programs = counts.programs;
    const n_unexpected = counts.unexpected;

    if (check_path) |golden_path| {
        const golden = try Io.Dir.cwd().readFileAlloc(io, golden_path, arena, .limited(1 << 24));
        if (!std.mem.eql(u8, golden, out.written())) {
            reportDifferences(golden, out.written());
            std.debug.print("corpus digests differ from {s}; if the change is intended, regenerate it with `zig build digests`\n", .{golden_path});
            std.process.exit(1);
        }
        std.debug.print("corpus digests: {d} programs match {s}{s}\n", .{ n_programs, golden_path, if (decode_cache) "" else " (decode cache off)" });
    } else {
        var buf: [4096]u8 = undefined;
        var fw: Io.File.Writer = .initStreaming(Io.File.stdout(), io, &buf);
        try fw.interface.writeAll(out.written());
        try fw.interface.flush();
    }
    if (n_unexpected != 0) std.process.exit(1);
}

const Counts = struct { programs: usize = 0, unexpected: usize = 0 };

fn runCorpus(
    comptime Cpu: type,
    io: Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    roots: []const Root,
    out: *Io.Writer,
    counts: *Counts,
) !void {
    const vm = try gpa.create(Cpu);
    defer gpa.destroy(vm);
    for (roots) |root| {
        var dir = try Io.Dir.cwd().openDir(io, root.dir, .{ .iterate = true });
        defer dir.close(io);
        const paths = try collectPrograms(io, gpa, arena, dir);
        for (paths) |p| {
            const program = try dir.readFileAlloc(io, p, arena, .limited(Cpu.mem_size + 1));
            vm.reset();
            const stop = try runProgram(arena, vm, program);
            try out.print("{s}/{s} {s} {d} {x}\n", .{ root.name, p, stop, vm.cycle_count, &vm.stateDigest() });
            counts.programs += 1;
            if (root.must_pass and !(std.mem.eql(u8, stop, "ebreak") and vm.readReg(3) == 1)) {
                std.debug.print("{s}/{s}: did not pass (stop {s}, gp = {d})\n", .{ root.name, p, stop, vm.readReg(3) });
                counts.unexpected += 1;
            }
            if (root.expect_dir) |expect_dir| {
                if (!try resultMatches(io, arena, vm, stop, expect_dir, p)) {
                    std.debug.print("{s}/{s}: result differs from the native run\n", .{ root.name, p });
                    counts.unexpected += 1;
                }
            }
        }
    }
}

/// Program paths under `dir`, relative to it, with '/' separators, sorted.
fn collectPrograms(io: Io, gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: Io.Dir) ![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".bin")) continue;
        if (entry.basename[0] == '.') continue; // e.g. macOS AppleDouble "._x.bin" files
        const p = try arena.dupe(u8, entry.path);
        std.mem.replaceScalar(u8, p, std.fs.path.sep, '/');
        try paths.append(arena, p);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    return paths.items;
}

/// Load and run one program; returns how it stopped.
fn runProgram(arena: std.mem.Allocator, vm: anytype, program: []const u8) ![]const u8 {
    vm.loadProgram(program, 0) catch |err| return std.fmt.allocPrint(arena, "error.{s}", .{@errorName(err)});
    const result = vm.run(max_cycles) catch |err| return std.fmt.allocPrint(arena, "error.{s}", .{@errorName(err)});
    return switch (result) {
        .ecall => "ecall",
        .ebreak => "ebreak",
        .@"continue" => "limit",
    };
}

/// Compare a C corpus program's result (a0, and the 16 words at a1) with the expected
/// text in `expect_dir`/<program name>.txt, formatted like native_main.c prints it.
fn resultMatches(io: Io, arena: std.mem.Allocator, vm: anytype, stop: []const u8, expect_dir: []const u8, path: []const u8) !bool {
    if (!std.mem.eql(u8, stop, "ebreak")) return false;
    const base = std.fs.path.basenamePosix(path);
    const name = base[0 .. base.len - ".bin".len];
    const expect_path = try std.fmt.allocPrint(arena, "{s}/{s}.txt", .{ expect_dir, name });
    const expected = try Io.Dir.cwd().readFileAlloc(io, expect_path, arena, .limited(4096));

    var got: Io.Writer.Allocating = .init(arena);
    try got.writer.print("a0={x:0>8} out=", .{vm.readReg(10)});
    const out_addr = vm.readReg(11);
    for (0..16) |k| {
        const word = vm.readWord(out_addr +% @as(u32, @intCast(4 * k))) catch return false;
        try got.writer.print("{x:0>8}{s}", .{ word, if (k < 15) "," else "\n" });
    }
    return std.mem.eql(u8, std.mem.trimEnd(u8, expected, "\r\n"), std.mem.trimEnd(u8, got.written(), "\n"));
}

/// Print the lines that are only in `expected` or only in `actual`.
fn reportDifferences(expected: []const u8, actual: []const u8) void {
    var it = std.mem.splitScalar(u8, expected, '\n');
    while (it.next()) |line| {
        if (line.len != 0 and !containsLine(actual, line)) std.debug.print("- {s}\n", .{line});
    }
    it = std.mem.splitScalar(u8, actual, '\n');
    while (it.next()) |line| {
        if (line.len != 0 and !containsLine(expected, line)) std.debug.print("+ {s}\n", .{line});
    }
}

fn containsLine(text: []const u8, line: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |l| {
        if (std.mem.eql(u8, l, line)) return true;
    }
    return false;
}
