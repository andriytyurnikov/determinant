//! Argument parsing (args.parse): one row per case.

const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const args = main_mod.args;
const h = @import("test_helpers.zig");

const Want = union(enum) {
    command: args.Command,
    /// A usage error whose message contains this.
    err: []const u8,
};

const Case = struct { args: []const [:0]const u8, want: Want };

fn run(config: args.Config) Want {
    return .{ .command = .{ .run = config } };
}

fn file(path: []const u8) args.Program {
    return .{ .file = path };
}

fn err(msg: []const u8) Want {
    return .{ .err = msg };
}

const cases = [_]Case{
    // Commands
    .{ .args = &.{}, .want = .{ .command = .usage } },
    .{ .args = &.{"--help"}, .want = .{ .command = .help } },
    .{ .args = &.{"-h"}, .want = .{ .command = .help } },
    .{ .args = &.{"--version"}, .want = .{ .command = .version } },
    .{ .args = &.{ "--bogus", "--help" }, .want = .{ .command = .help } }, // --help wins anywhere
    .{ .args = &.{ "p.bin", "--max-cycles", "--version" }, .want = .{ .command = .version } },
    .{ .args = &.{ "--", "--help" }, .want = run(.{ .program = file("--help") }) },
    .{ .args = &.{"p.bin"}, .want = run(.{ .program = file("p.bin") }) },
    .{ .args = &.{"--demo"}, .want = run(.{ .program = .demo }) },
    .{ .args = &.{"-"}, .want = run(.{ .program = file("-") }) }, // an argument, not an option
    .{ .args = &.{ "--", "-weird.bin" }, .want = run(.{ .program = file("-weird.bin") }) },

    // Values: the next argument or after '=', and the number syntax
    .{ .args = &.{ "p.bin", "--max-cycles", "1000" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 1000 }) },
    .{ .args = &.{ "--max-cycles=1000", "p.bin" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 1000 }) },
    .{ .args = &.{ "p.bin", "--max-cycles", "0x10" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 16 }) },
    .{ .args = &.{ "p.bin", "--max-cycles", "1_000_000" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 1_000_000 }) },
    .{ .args = &.{ "p.bin", "--max-cycles", "0" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 0 }) },
    .{ .args = &.{ "p.bin", "--max-cycles", "18446744073709551615" }, .want = run(.{ .program = file("p.bin"), .max_cycles = std.math.maxInt(u64) }) },
    .{ .args = &.{ "p.bin", "--max-cycles", "1", "--max-cycles", "2" }, .want = run(.{ .program = file("p.bin"), .max_cycles = 2 }) }, // the last wins
    .{ .args = &.{ "p.bin", "--input", "in.txt" }, .want = run(.{ .program = file("p.bin"), .input = .{ .file = "in.txt" } }) },
    .{ .args = &.{ "p.bin", "--input", "-" }, .want = run(.{ .program = file("p.bin"), .input = .stdin }) },
    .{ .args = &.{ "p.bin", "--input=-" }, .want = run(.{ .program = file("p.bin"), .input = .stdin }) },
    .{ .args = &.{ "p.bin", "--input", "--digest" }, .want = run(.{ .program = file("p.bin"), .input = .{ .file = "--digest" } }) }, // a value, even if it looks like an option
    .{ .args = &.{ "p.bin", "--load-addr", "0x100" }, .want = run(.{ .program = file("p.bin"), .load_addr = 0x100 }) },
    .{ .args = &.{ "p.bin", "--load-addr=0" }, .want = run(.{ .program = file("p.bin"), .load_addr = 0 }) },
    .{ .args = &.{ "p.bin", "--load-addr", "0xFFFE" }, .want = run(.{ .program = file("p.bin"), .load_addr = 0xFFFE }) },

    // Memory: bytes or KiB/MiB/GiB, and the limits it sets, wherever it is
    .{ .args = &.{ "p.bin", "--memory", "1024" }, .want = run(.{ .program = file("p.bin"), .memory = 1024 }) },
    .{ .args = &.{ "p.bin", "--memory=4" }, .want = run(.{ .program = file("p.bin"), .memory = 4 }) }, // the smallest
    .{ .args = &.{ "p.bin", "--memory", "0x100" }, .want = run(.{ .program = file("p.bin"), .memory = 256 }) },
    .{ .args = &.{ "p.bin", "--memory", "1KiB" }, .want = run(.{ .program = file("p.bin"), .memory = 1024 }) },
    .{ .args = &.{ "p.bin", "--memory", "64 KiB" }, .want = run(.{ .program = file("p.bin"), .memory = 64 * 1024 }) }, // as the report prints it
    .{ .args = &.{ "p.bin", "--memory", "1MiB" }, .want = run(.{ .program = file("p.bin"), .memory = 1 << 20 }) },
    .{ .args = &.{ "p.bin", "--memory", "3GiB" }, .want = run(.{ .program = file("p.bin"), .memory = 3 << 30 }) },
    .{ .args = &.{ "p.bin", "--memory", "4294967292" }, .want = run(.{ .program = file("p.bin"), .memory = 0xFFFF_FFFC }) }, // the largest
    .{ .args = &.{ "p.bin", "--memory", "1MiB", "--memory", "2KiB" }, .want = run(.{ .program = file("p.bin"), .memory = 2048 }) }, // the last wins
    .{ .args = &.{ "--load-addr", "0x20000", "--memory", "256KiB", "p.bin" }, .want = run(.{ .program = file("p.bin"), .memory = 256 * 1024, .load_addr = 0x20000 }) },
    .{ .args = &.{ "p.bin", "--dump-range", "0x3FFF0:16", "--memory", "256KiB" }, .want = run(.{ .program = file("p.bin"), .memory = 256 * 1024, .dump = .{ .range = .{ .start = 0x3FFF0, .len = 16 } } }) },
    .{ .args = &.{ "--disassemble", "p.bin", "--memory", "1MiB" }, .want = run(.{ .program = file("p.bin"), .disassemble = true, .memory = 1 << 20 }) },

    // Dumps: the format only after '=', the range in either order
    .{ .args = &.{ "p.bin", "--dump-memory" }, .want = run(.{ .program = file("p.bin"), .dump = .{} }) },
    .{ .args = &.{ "p.bin", "--dump-memory=raw" }, .want = run(.{ .program = file("p.bin"), .dump = .{ .format = .raw } }) },
    .{ .args = &.{ "p.bin", "--dump-memory=hexdump" }, .want = run(.{ .program = file("p.bin"), .dump = .{} }) },
    .{ .args = &.{ "--dump-memory", "raw" }, .want = run(.{ .program = file("raw"), .dump = .{} }) },
    .{ .args = &.{ "p.bin", "--dump-range", "0x10:16" }, .want = run(.{ .program = file("p.bin"), .dump = .{ .range = .{ .start = 16, .len = 16 } } }) },
    .{ .args = &.{ "p.bin", "--dump-range=0xFFF0:0x10" }, .want = run(.{ .program = file("p.bin"), .dump = .{ .range = .{ .start = 0xFFF0, .len = 16 } } }) }, // up to the top
    .{ .args = &.{ "p.bin", "--dump-memory=raw", "--dump-range", "0:4" }, .want = run(.{ .program = file("p.bin"), .dump = .{ .format = .raw, .range = .{ .start = 0, .len = 4 } } }) },
    .{ .args = &.{ "p.bin", "--dump-range", "0:4", "--dump-memory=raw" }, .want = run(.{ .program = file("p.bin"), .dump = .{ .format = .raw, .range = .{ .start = 0, .len = 4 } } }) },

    // Flags
    .{ .args = &.{ "p.bin", "--digest", "--trace", "-q" }, .want = run(.{ .program = file("p.bin"), .digest = true, .trace = true, .quiet = true }) },
    .{ .args = &.{ "--quiet", "--demo" }, .want = run(.{ .program = .demo, .quiet = true }) },
    .{ .args = &.{ "--disassemble", "p.bin", "--load-addr", "8" }, .want = run(.{ .program = file("p.bin"), .disassemble = true, .load_addr = 8 }) },
    .{ .args = &.{ "--disassemble", "--demo" }, .want = run(.{ .program = .demo, .disassemble = true }) },

    // Usage errors
    .{ .args = &.{"--bogus"}, .want = err("unknown option '--bogus'") },
    .{ .args = &.{ "p.bin", "-x" }, .want = err("unknown option '-x'") },
    .{ .args = &.{ "p.bin", "--max-cycles" }, .want = err("--max-cycles needs a value") },
    .{ .args = &.{ "p.bin", "--max-cycles", "abc" }, .want = err("--max-cycles 'abc' is not a number") },
    .{ .args = &.{ "p.bin", "--max-cycles", "" }, .want = err("is not a number") },
    .{ .args = &.{ "p.bin", "--max-cycles=" }, .want = err("is not a number") },
    .{ .args = &.{ "p.bin", "--max-cycles", "1e6" }, .want = err("--max-cycles '1e6' is not a number") },
    .{ .args = &.{ "p.bin", "--max-cycles", "-1" }, .want = err("--max-cycles '-1' is negative") },
    .{ .args = &.{ "p.bin", "--max-cycles", "18446744073709551616" }, .want = err("is too large (at most 18446744073709551615)") },
    .{ .args = &.{ "p.bin", "--load-addr", "0x101" }, .want = err("--load-addr '0x101' must be even") },
    .{ .args = &.{ "p.bin", "--load-addr", "65536" }, .want = err("--load-addr '65536' is not inside the 64 KiB of VM memory") },
    .{ .args = &.{ "p.bin", "--load-addr", "0x200", "--memory", "512" }, .want = err("--load-addr '0x200' is not inside the 512 bytes of VM memory") },
    .{ .args = &.{ "p.bin", "--load-addr", "0x100000000" }, .want = err("is too large") },
    .{ .args = &.{ "p.bin", "--load-addr", "nope" }, .want = err("--load-addr 'nope' is not a number") },
    .{ .args = &.{ "p.bin", "--input" }, .want = err("--input needs a value") },
    .{ .args = &.{ "p.bin", "--dump-memory=bin" }, .want = err("unknown --dump-memory format 'bin' (hexdump or raw)") },
    .{ .args = &.{ "p.bin", "--dump-memory=" }, .want = err("unknown --dump-memory format ''") },
    .{ .args = &.{ "p.bin", "--dump-range", "16" }, .want = err("--dump-range '16' is not ADDR:LEN") },
    .{ .args = &.{ "p.bin", "--dump-range", "x:1" }, .want = err("--dump-range address 'x' is not a number") },
    .{ .args = &.{ "p.bin", "--dump-range", "0:" }, .want = err("--dump-range length '' is not a number") },
    .{ .args = &.{ "p.bin", "--dump-range", "0:0" }, .want = err("--dump-range '0:0' is empty") },
    .{ .args = &.{ "p.bin", "--dump-range", "0xFFF0:0x11" }, .want = err("--dump-range '0xFFF0:0x11' is not inside the 64 KiB of VM memory") },
    .{ .args = &.{ "p.bin", "--dump-range", "0xFFFFFFFF:0xFFFFFFFF" }, .want = err("is not inside") }, // no overflow
    .{ .args = &.{ "p.bin", "--dump-range", "0xFFFFFFF0:0x20" }, .want = err("is not inside") }, // would wrap to 0x10
    .{ .args = &.{ "p.bin", "--memory", "512", "--dump-range", "0x1F0:0x11" }, .want = err("--dump-range '0x1F0:0x11' is not inside the 512 bytes of VM memory") },
    .{ .args = &.{ "p.bin", "--memory" }, .want = err("--memory needs a value") },
    .{ .args = &.{ "p.bin", "--memory", "abc" }, .want = err("--memory 'abc' is not a size (bytes, or a number with KiB, MiB or GiB)") },
    .{ .args = &.{ "p.bin", "--memory", "" }, .want = err("--memory '' is not a size") },
    .{ .args = &.{ "p.bin", "--memory", "KiB" }, .want = err("--memory 'KiB' is not a size") },
    .{ .args = &.{ "p.bin", "--memory", "-4" }, .want = err("--memory '-4' is not a size") },
    .{ .args = &.{ "p.bin", "--memory", "1.5MiB" }, .want = err("--memory '1.5MiB' is not a size") },
    .{ .args = &.{ "p.bin", "--memory", "64KB" }, .want = err("--memory '64KB' is not a size") },
    .{ .args = &.{ "p.bin", "--memory", "0" }, .want = err("--memory '0' must be a positive multiple of 4 bytes") },
    .{ .args = &.{ "p.bin", "--memory", "6" }, .want = err("--memory '6' must be a positive multiple of 4 bytes") },
    .{ .args = &.{ "p.bin", "--memory", "4294967295" }, .want = err("must be a positive multiple of 4 bytes") },
    .{ .args = &.{ "p.bin", "--memory", "4GiB" }, .want = err("--memory '4GiB' is too large: it must be less than 4 GiB") },
    .{ .args = &.{ "p.bin", "--memory", "4294967296" }, .want = err("is too large: it must be less than 4 GiB") },
    .{ .args = &.{ "p.bin", "--memory", "17179869184GiB" }, .want = err("is too large") }, // the multiplication overflows
    .{ .args = &.{ "p.bin", "--memory", "18446744073709551616" }, .want = err("is too large") },
    .{ .args = &.{ "p.bin", "--digest=yes" }, .want = err("--digest takes no value") },
    .{ .args = &.{ "p.bin", "-q=1" }, .want = err("--quiet takes no value") },
    .{ .args = &.{ "a.bin", "b.bin" }, .want = err("unexpected argument 'b.bin' after the program 'a.bin' (programs take no arguments)") },
    .{ .args = &.{ "a.bin", "--", "b.bin" }, .want = err("unexpected argument 'b.bin'") },
    .{ .args = &.{ "--demo", "a.bin" }, .want = err("--demo runs the built-in program, so it takes no program file ('a.bin')") },
    .{ .args = &.{ "--demo", "--load-addr", "0" }, .want = err("--load-addr does not apply to --demo") },
    .{ .args = &.{"-q"}, .want = err("no program to run (a file, or --demo)") },
    .{ .args = &.{"--"}, .want = err("no program to run") },
    .{ .args = &.{ "--disassemble", "p.bin", "--max-cycles", "1" }, .want = err("--max-cycles does not apply to --disassemble") },
    .{ .args = &.{ "--disassemble", "p.bin", "--input", "x" }, .want = err("--input does not apply to --disassemble") },
    .{ .args = &.{ "--disassemble", "p.bin", "--dump-range", "0:4" }, .want = err("--dump-memory or --dump-range does not apply to --disassemble") },
    .{ .args = &.{ "--disassemble", "p.bin", "--digest" }, .want = err("--digest does not apply to --disassemble") },
    .{ .args = &.{ "--disassemble", "p.bin", "--trace" }, .want = err("--trace does not apply to --disassemble, which lists the program without running it") },
    .{ .args = &.{ "--disassemble", "p.bin", "-q" }, .want = err("--quiet does not apply to --disassemble") },
};

test "parse: table" {
    for (cases) |c| {
        var argv: std.ArrayList([:0]const u8) = .empty;
        defer argv.deinit(h.alloc);
        try argv.append(h.alloc, "determinant");
        try argv.appendSlice(h.alloc, c.args);
        var diag: Io.Writer.Allocating = .init(h.alloc);
        defer diag.deinit();

        const got = args.parse(argv.items, &diag.writer);
        errdefer std.debug.print("\nargs: {any}\nmessage: {s}\n", .{ c.args, diag.written() });
        switch (c.want) {
            .command => |want| {
                try std.testing.expectEqualDeep(want, try got);
                try std.testing.expectEqualStrings("", diag.written());
            },
            .err => |msg| {
                try std.testing.expectError(error.Usage, got);
                try std.testing.expectStringStartsWith(diag.written(), "Error: ");
                try h.expectContains(diag.written(), msg);
                try std.testing.expect(std.mem.endsWith(u8, diag.written(), "\n"));
            },
        }
    }
}

test "--help lists every option and the exit statuses, on stdout" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{"--help"}));
    try std.testing.expectStringStartsWith(fx.stdout(), args.usage_text);
    for (args.specs) |spec| {
        try h.expectContains(fx.stdout(), spec.name);
        if (spec.short) |short| try h.expectContains(fx.stdout(), short);
    }
    try h.expectContains(fx.stdout(), "Exit status:");
    try std.testing.expectEqualStrings("", fx.stderr());
}

test "--version shows the version and the build mode, on stdout" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{"--version"}));
    try std.testing.expectEqualStrings("determinant " ++ @import("cli_options").version ++ " (" ++ @tagName(@import("builtin").mode) ++ " build)\n", fx.stdout());
}

test "no arguments: the usage on stderr, exit status 1" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.usage_or_io), try fx.run(&.{}));
    try std.testing.expectEqualStrings("", fx.stdout());
    try std.testing.expectEqualStrings(args.usage_text ++ "Run 'determinant --help' for the options, or 'determinant --demo' for a demo.\n", fx.stderr());
}

test "a usage error: the message and a pointer to --help on stderr, exit status 1" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.usage_or_io), try fx.run(&.{"--bogus"}));
    try std.testing.expectEqualStrings("", fx.stdout());
    try std.testing.expectEqualStrings("Error: unknown option '--bogus'\nRun 'determinant --help' for usage.\n", fx.stderr());
}
