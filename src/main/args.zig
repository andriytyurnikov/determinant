//! Command-line parsing (docs/design/cli.md). parse() is a pure function from the
//! arguments to a Command, so every case can be a row of a table in args_test.zig.

const std = @import("std");
const Io = std.Io;
const dump = @import("dump.zig");
const units = @import("units.zig");

pub const Range = struct { start: u32, len: u32 };

pub const Dump = struct {
    format: dump.Format = .hexdump,
    /// null dumps all of memory.
    range: ?Range = null,
};

pub const Program = union(enum) { demo, file: []const u8 };

pub const Input = union(enum) { stdin, file: []const u8 };

/// A program to run (or list) and how. An optional field is null when its option was
/// not given.
pub const Config = struct {
    program: Program,
    disassemble: bool = false,
    max_cycles: ?u64 = null,
    input: ?Input = null,
    /// Where a flat binary goes; null for the default, 0.
    load_addr: ?u32 = null,
    dump: ?Dump = null,
    digest: bool = false,
    trace: bool = false,
    quiet: bool = false,
};

pub const Command = union(enum) {
    help,
    version,
    /// No arguments at all: show the usage (exit status 1).
    usage,
    run: Config,
};

/// A usage error; its message is already written.
pub const Error = error{Usage} || Io.Writer.Error;

pub const Opt = enum { max_cycles, input, load_addr, dump_memory, dump_range, digest, trace, disassemble, quiet, demo, help, version };

pub const Value = enum { none, required, optional };

pub const Spec = struct { name: []const u8, short: ?[]const u8 = null, opt: Opt, value: Value = .none };

pub const specs = [_]Spec{
    .{ .name = "--max-cycles", .opt = .max_cycles, .value = .required },
    .{ .name = "--input", .opt = .input, .value = .required },
    .{ .name = "--load-addr", .opt = .load_addr, .value = .required },
    // Its format only after '=', so that `--dump-memory raw` cannot take a file named raw.
    .{ .name = "--dump-memory", .opt = .dump_memory, .value = .optional },
    .{ .name = "--dump-range", .opt = .dump_range, .value = .required },
    .{ .name = "--digest", .opt = .digest },
    .{ .name = "--trace", .opt = .trace },
    .{ .name = "--disassemble", .opt = .disassemble },
    .{ .name = "--quiet", .short = "-q", .opt = .quiet },
    .{ .name = "--demo", .opt = .demo },
    .{ .name = "--help", .short = "-h", .opt = .help },
    .{ .name = "--version", .opt = .version },
};

fn lookup(name: []const u8) ?Spec {
    for (specs) |s| {
        if (std.mem.eql(u8, name, s.name)) return s;
        if (s.short) |short| if (std.mem.eql(u8, name, short)) return s;
    }
    return null;
}

/// Is `arg` an option (or "--")? A lone "-" is not: it is an argument.
fn isOption(arg: []const u8) bool {
    return arg.len > 1 and arg[0] == '-';
}

/// Parse the arguments (args[0] is the program name) for a VM with `mem_size` bytes of
/// memory. A usage error is reported on `diag` ("Error: ...") and returns error.Usage.
pub fn parse(args: []const [:0]const u8, mem_size: u32, diag: *Io.Writer) Error!Command {
    if (args.len <= 1) return .usage;

    // --help and --version win wherever they are, even after an invalid option.
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) break;
        const spec = lookup(arg) orelse continue;
        switch (spec.opt) {
            .help => return .help,
            .version => return .version,
            else => {},
        }
    }

    var program: ?[]const u8 = null;
    var demo = false;
    var config: Config = .{ .program = .demo };
    var options_ended = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (options_ended or !isOption(arg)) {
            if (program) |first| return fail(diag, "unexpected argument '{s}' after the program '{s}' (programs take no arguments)", .{ arg, first });
            program = arg;
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            options_ended = true;
            continue;
        }

        var name: []const u8 = arg;
        var inline_value: ?[]const u8 = null;
        if (std.mem.cutScalar(u8, arg, '=')) |cut| {
            name = cut[0];
            inline_value = cut[1];
        }
        const spec = lookup(name) orelse return fail(diag, "unknown option '{s}'", .{arg});
        const value: ?[]const u8 = switch (spec.value) {
            .none => if (inline_value != null) return fail(diag, "{s} takes no value", .{spec.name}) else null,
            .optional => inline_value,
            .required => inline_value orelse blk: {
                i += 1;
                if (i == args.len) return fail(diag, "{s} needs a value", .{spec.name});
                break :blk args[i];
            },
        };

        switch (spec.opt) {
            .max_cycles => config.max_cycles = try number(u64, value.?, spec.name, diag),
            .input => config.input = if (std.mem.eql(u8, value.?, "-")) .stdin else .{ .file = value.? },
            .load_addr => {
                const addr = try number(u32, value.?, spec.name, diag);
                if (addr % 2 != 0 or addr >= mem_size) return fail(diag, "--load-addr '{s}' must be even and inside the {f} of VM memory", .{ value.?, units.MemSize{ .bytes = mem_size } });
                config.load_addr = addr;
            },
            .dump_memory => {
                const format: dump.Format = if (value) |v| std.meta.stringToEnum(dump.Format, v) orelse
                    return fail(diag, "unknown --dump-memory format '{s}' (hexdump or raw)", .{v}) else .hexdump;
                // Through a copy: an assignment that reads its own target sees it half-written.
                var d = config.dump orelse Dump{};
                d.format = format;
                config.dump = d;
            },
            .dump_range => {
                var d = config.dump orelse Dump{};
                d.range = try parseRange(value.?, mem_size, diag);
                config.dump = d;
            },
            .digest => config.digest = true,
            .trace => config.trace = true,
            .disassemble => config.disassemble = true,
            .quiet => config.quiet = true,
            .demo => demo = true,
            .help, .version => unreachable, // handled above
        }
    }

    if (demo) {
        if (program) |p| return fail(diag, "--demo runs the built-in program, so it takes no program file ('{s}')", .{p});
        if (config.load_addr != null) return fail(diag, "--load-addr does not apply to --demo", .{});
        config.program = .demo;
    } else {
        config.program = .{ .file = program orelse return fail(diag, "no program to run (a file, or --demo)", .{}) };
    }

    if (config.disassemble) {
        const run_options = [_]struct { []const u8, bool }{
            .{ "--max-cycles", config.max_cycles != null },
            .{ "--input", config.input != null },
            .{ "--dump-memory or --dump-range", config.dump != null },
            .{ "--digest", config.digest },
            .{ "--trace", config.trace },
            .{ "--quiet", config.quiet },
        };
        for (run_options) |o| {
            if (o[1]) return fail(diag, "{s} does not apply to --disassemble, which lists the program without running it", .{o[0]});
        }
    }
    return .{ .run = config };
}

fn fail(diag: *Io.Writer, comptime fmt: []const u8, args: anytype) Error {
    diag.print("Error: " ++ fmt ++ "\n", args) catch |err| return err;
    return error.Usage;
}

/// A number in decimal, or with a 0x, 0o or 0b prefix, with optional _ separators.
fn number(comptime T: type, text: []const u8, option: []const u8, diag: *Io.Writer) Error!T {
    if (std.mem.startsWith(u8, text, "-")) return fail(diag, "{s} '{s}' is negative", .{ option, text });
    return std.fmt.parseInt(T, text, 0) catch |err| switch (err) {
        error.Overflow => return fail(diag, "{s} '{s}' is too large (at most {d})", .{ option, text, std.math.maxInt(T) }),
        error.InvalidCharacter => return fail(diag, "{s} '{s}' is not a number", .{ option, text }),
    };
}

fn parseRange(text: []const u8, mem_size: u32, diag: *Io.Writer) Error!Range {
    const start_text, const len_text = std.mem.cutScalar(u8, text, ':') orelse
        return fail(diag, "--dump-range '{s}' is not ADDR:LEN", .{text});
    const range: Range = .{
        .start = try number(u32, start_text, "--dump-range address", diag),
        .len = try number(u32, len_text, "--dump-range length", diag),
    };
    if (range.len == 0) return fail(diag, "--dump-range '{s}' is empty", .{text});
    if (@as(u64, range.start) + range.len > mem_size) return fail(diag, "--dump-range '{s}' is not inside the {f} of VM memory", .{ text, units.MemSize{ .bytes = mem_size } });
    return range;
}

pub const usage_text =
    \\Usage: determinant [options] <program>
    \\       determinant --demo [options]
    \\
;

/// The --help text. `initial_sp` is where programs start their stack.
pub fn printHelp(w: *Io.Writer, mem_size: u32, initial_sp: u32) Io.Writer.Error!void {
    try w.writeAll(usage_text);
    try w.writeAll(
        \\
        \\Runs a RISC-V program, an ELF32 executable or a flat binary, and reports how it
        \\stopped. The program's output goes to stdout, the report to stderr.
        \\
        \\Options:
        \\  --max-cycles N         Stop after N cycles (retired instructions). Default: no limit
        \\  --input FILE           The bytes the program's read() returns; - reads stdin
        \\  --load-addr ADDR       Where a flat binary is loaded and starts. Default: 0
        \\  --dump-memory[=FMT]    Dump memory after the run: hexdump (default) or raw
        \\  --dump-range ADDR:LEN  Dump only LEN bytes from ADDR
        \\  --digest               Print the SHA-256 digest of the final VM state
        \\  --trace                Print each instruction as it retires
        \\  --disassemble          List the program's instructions instead of running it
        \\  -q, --quiet            Report only faults and what the options above ask for
        \\  --demo                 Run a built-in demo program
        \\  -h, --help             Show this help
        \\  --version              Show the version
        \\
        \\A value follows its option or an '=' (--max-cycles=1000). Numbers are decimal,
        \\or hex with 0x, with optional _ separators.
        \\
        \\
    );
    try w.print(
        \\VM memory: {f} (build option -Dmemory_size). Programs start with every
        \\register 0 except sp = 0x{X:0>8}.
        \\
        \\
    , .{ units.MemSize{ .bytes = mem_size }, initial_sp });
    try w.writeAll(
        \\Exit status:
        \\  0  the program stopped at ECALL or EBREAK
        \\  1  usage or I/O error
        \\  2  cycle limit reached
        \\  3  VM fault
        \\  N  the program called exit: the low 8 bits of its status
        \\
    );
}
