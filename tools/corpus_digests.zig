//! Runs every program (`*.bin`) under a corpus directory on a fresh VM and prints one
//! line per program, sorted by path:
//!
//!     <path> <stop> <cycles> <sha256 of the final VM state>
//!
//! where <stop> is `ecall`, `ebreak`, `limit` or `error.<Name>`. With `--check FILE`,
//! compares the lines with FILE instead and exits 1 on any difference.
//!
//! CI checks every job (each OS, optimize mode, endianness and decoder) against the same
//! golden file, tests/digests.txt, so all of them must reach bit-identical final states.
//! After an intended change in guest-visible behavior, regenerate it with
//! `zig build digests > tests/digests.txt` and review the diff.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

/// Every corpus program runs with 256 KiB of memory, like the compliance suite.
const CorpusCpu = det.CpuType(256 * 1024, det.Cpu.decode);
const max_cycles: u64 = 10_000_000;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var dir_path: ?[]const u8 = null;
    var check_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--check") and i + 1 < args.len) {
            i += 1;
            check_path = args[i];
        } else if (dir_path == null) {
            dir_path = args[i];
        } else {
            std.debug.print("usage: corpus_digests <dir> [--check <golden-file>]\n", .{});
            std.process.exit(2);
        }
    }
    const root = dir_path orelse {
        std.debug.print("usage: corpus_digests <dir> [--check <golden-file>]\n", .{});
        std.process.exit(2);
    };

    // Collect program paths, relative to the corpus root, with '/' separators.
    var dir = try Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
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

    const vm = try gpa.create(CorpusCpu);
    defer gpa.destroy(vm);

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    for (paths.items) |p| {
        const program = try dir.readFileAlloc(io, p, arena, .limited(CorpusCpu.mem_size + 1));
        vm.reset();
        try out.writer.print("{s} ", .{p});
        if (vm.loadProgram(program, 0)) {
            if (vm.run(max_cycles)) |result| {
                try out.writer.print("{s}", .{switch (result) {
                    .ecall => "ecall",
                    .ebreak => "ebreak",
                    .@"continue" => "limit",
                }});
            } else |err| {
                try out.writer.print("error.{s}", .{@errorName(err)});
            }
        } else |err| {
            try out.writer.print("error.{s}", .{@errorName(err)});
        }
        try out.writer.print(" {d} {x}\n", .{ vm.cycle_count, &vm.stateDigest() });
    }

    if (check_path) |golden_path| {
        const golden = try Io.Dir.cwd().readFileAlloc(io, golden_path, arena, .limited(1 << 24));
        if (std.mem.eql(u8, golden, out.written())) {
            std.debug.print("corpus digests: {d} programs match {s}\n", .{ paths.items.len, golden_path });
            return;
        }
        reportDifferences(golden, out.written());
        std.debug.print("corpus digests differ from {s}; if the change is intended, regenerate it with `zig build digests`\n", .{golden_path});
        std.process.exit(1);
    } else {
        var buf: [4096]u8 = undefined;
        var fw: Io.File.Writer = .init(Io.File.stdout(), io, &buf);
        try fw.interface.writeAll(out.written());
        try fw.interface.flush();
    }
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
