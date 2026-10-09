//! CLI executable (docs/design/cli.md): runs a RISC-V program, an ELF32 executable,
//! a flat binary or the built-in demo, and reports how it stopped. The program's
//! output goes to stdout and the report to stderr; the exit status tells how the run
//! ended (see ExitStatus).

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const det = @import("determinant");
const cli_options = @import("cli_options");

pub const args = @import("main/args.zig");
pub const disasm = @import("main/disasm.zig");
pub const dump = @import("main/dump.zig");
pub const load = @import("main/load.zig");
pub const report = @import("main/report.zig");
pub const units = @import("main/units.zig");

/// Process exit status. When the program calls exit (docs/design/host-calls.md) the
/// status is the low 8 bits of the program's status instead.
pub const ExitStatus = enum(u8) {
    /// The program stopped at ECALL or EBREAK (or --help, --version or --disassemble
    /// succeeded).
    ok = 0,
    /// Usage error, or an I/O error (unreadable file, output that cannot be written).
    usage_or_io = 1,
    /// The cycle limit (--max-cycles) was reached before the program stopped.
    cycle_limit = 2,
    /// The VM raised a fault: illegal instruction, misaligned or out-of-bounds access, ...
    vm_fault = 3,
    /// Any other value: the status the program passed to exit.
    _,
};

/// The stack pointer a program starts with: the top of memory, 16-byte aligned
/// (docs/design/program-loading.md). The VM's reset() leaves it 0; this is CLI policy.
pub const initial_sp: u32 = det.Cpu.mem_size & ~@as(u32, 15);

const mem_size: units.MemSize = .{ .bytes = det.Cpu.mem_size };

/// Largest --input.
const max_input = 1 << 30;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_fr = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_fw = stdStreamWriter(Io.File.stdout(), io, &stdout_buffer);
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_fw = stdStreamWriter(Io.File.stderr(), io, &stderr_buffer);

    const cli: Cli = .{
        .io = io,
        .gpa = init.gpa,
        .stdin = &stdin_fr.interface,
        .stdout = &stdout_fw.interface,
        .stderr = &stderr_fw.interface,
    };
    return cli.run(try init.minimal.args.toSlice(init.arena.allocator()));
}

/// Writer for stdout or stderr. It must stream (write at the file's current offset):
/// the default positional mode writes each stream from its own offset 0, so with
/// `> out.txt 2>&1` stdout and stderr would overwrite each other, and `>> log.txt`
/// would overwrite the log instead of appending to it.
pub fn stdStreamWriter(file: Io.File, io: Io, buffer: []u8) Io.File.Writer {
    return .initStreaming(file, io, buffer);
}

/// What the CLI runs with. stdout carries only the program's own output (fd 1); stderr
/// carries the program's fd 2 and the CLI's report.
pub const Cli = struct {
    io: Io,
    gpa: std.mem.Allocator,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
    stderr: *Io.Writer,

    /// Run the CLI on `argv` (argv[0] is the program name) and flush the output.
    /// Returns the process exit status (see ExitStatus). Failures, including output
    /// that cannot be written, are reported on stderr and give a non-zero status,
    /// never a stack trace.
    pub fn run(cli: Cli, argv: []const [:0]const u8) u8 {
        const status: ExitStatus = cli.command(argv) catch |err| switch (err) {
            error.UserError => .usage_or_io, // already reported
            error.WriteFailed => return cli.outputFailed(),
            else => blk: {
                cli.stderr.print("Error: {s}\n", .{report.ioText(err)}) catch {};
                break :blk .usage_or_io;
            },
        };
        // Flush with error checking: buffered output that cannot be written must not
        // end in a zero exit status.
        cli.stdout.flush() catch return cli.outputFailed();
        cli.stderr.flush() catch return @backingInt(ExitStatus.usage_or_io);
        return @backingInt(status);
    }

    fn outputFailed(cli: Cli) u8 {
        cli.stderr.writeAll("Error: cannot write output\n") catch {};
        cli.stderr.flush() catch {};
        return @backingInt(ExitStatus.usage_or_io);
    }

    fn command(cli: Cli, argv: []const [:0]const u8) !ExitStatus {
        const cmd = args.parse(argv, det.Cpu.mem_size, cli.stderr) catch |err| switch (err) {
            error.Usage => {
                try cli.stderr.writeAll("Run 'determinant --help' for usage.\n");
                return error.UserError;
            },
            error.WriteFailed => return error.WriteFailed,
        };
        switch (cmd) {
            .help => try args.printHelp(cli.stdout, det.Cpu.mem_size, initial_sp),
            .version => try cli.stdout.print("determinant {s} ({f} of VM memory, {s} build)\n", .{ cli_options.version, mem_size, @tagName(builtin.mode) }),
            .usage => {
                try cli.stderr.writeAll(args.usage_text ++ "Run 'determinant --help' for the options, or 'determinant --demo' for a demo.\n");
                return error.UserError;
            },
            .run => |config| return cli.runProgram(config),
        }
        return .ok;
    }

    fn runProgram(cli: Cli, config: args.Config) !ExitStatus {
        // The VM embeds its whole memory, so it must not live on the stack: a few MiB
        // of memory would overflow it.
        const vm = try cli.gpa.create(det.Cpu);
        defer cli.gpa.destroy(vm);
        vm.reset();
        const loaded = try load.load(cli.io, cli.gpa, cli.stderr, vm, config);
        defer loaded.deinit(cli.gpa);

        if (config.disassemble) {
            for (loaded.code, 0..) |range, i| {
                if (i > 0) try cli.stdout.writeAll("\n");
                try disasm.printListing(cli.stdout, &vm.memory, range.start, range.start + range.len);
            }
            return .ok;
        }

        const input = try cli.readInput(config.input);
        defer if (config.input != null) cli.gpa.free(input);

        var out: Report = .{ .cli = cli };
        if (!config.quiet) {
            if (config.program == .demo) {
                try out.section("Demo program:\n", .{});
                try disasm.printListing(cli.stderr, &vm.memory, 0, load.demo_program.len);
            }
            try out.section("Running {f} in {f} of VM memory, {f}\n", .{ loaded, mem_size, Limit{ .max_cycles = config.max_cycles } });
            try cli.stderr.flush(); // before the program's output
        }

        vm.pc = loaded.entry;
        vm.writeReg(2, initial_sp);
        if (config.trace) out.started = true; // the trace lines come first
        var env: det.hostcall.Env = .{ .input = input, .stdout = cli.stdout, .stderr = cli.stderr };
        const status: ExitStatus = if (cli.execute(vm, config, &env)) |stop| blk: {
            if (!config.quiet) {
                try out.section("", .{});
                try report.printStop(cli.stderr, vm, stop);
                try report.printRegisters(cli.stderr, vm);
                if (config.program == .demo) {
                    if (vm.readWord(load.demo_store_addr)) |word| {
                        try out.section("Memory at 0x{X:0>8} (the demo's store): 0x{X:0>8}  {d}\n", .{ load.demo_store_addr, word, word });
                    } else |_| {}
                }
            }
            break :blk switch (stop) {
                .ebreak, .ecall => .ok,
                .cycle_limit => .cycle_limit,
                .exit => |s| @fromBackingInt(@as(u8, @truncate(s))),
            };
        } else |err| switch (err) {
            error.WriteFailed => return error.WriteFailed,
            else => |fault| blk: {
                try out.section("", .{});
                try report.printFault(cli.stderr, vm, fault);
                try report.printRegisters(cli.stderr, vm);
                break :blk .vm_fault;
            },
        };

        if (config.dump) |d| {
            const range = d.range orelse args.Range{ .start = 0, .len = det.Cpu.mem_size };
            try out.section("", .{});
            try dump.dumpMemory(cli.stderr, vm.memory[range.start..][0..range.len], range.start, d.format);
        }
        if (config.digest) try out.section("State digest: {s}\n", .{&std.fmt.bytesToHex(vm.stateDigest(), .lower)});
        return status;
    }

    /// The bytes the program's read host call returns.
    fn readInput(cli: Cli, input: ?args.Input) ![]const u8 {
        return switch (input orelse return &.{}) {
            .file => |path| Io.Dir.cwd().readFileAlloc(cli.io, path, cli.gpa, .limited(max_input)) catch |err|
                report.userError(cli.stderr, "cannot read input '{s}': {s}", .{ path, report.ioText(err) }),
            .stdin => cli.stdin.allocRemaining(cli.gpa, .limited(max_input)) catch |err| switch (err) {
                error.ReadFailed => report.userError(cli.stderr, "cannot read input from stdin", .{}),
                else => report.userError(cli.stderr, "cannot read input from stdin: {s}", .{report.ioText(err)}),
            },
        };
    }

    /// Run the program, performing its host calls, until it stops.
    fn execute(cli: Cli, vm: *det.Cpu, config: args.Config, env: *det.hostcall.Env) (det.StepError || Io.Writer.Error)!report.Stop {
        while (true) {
            const result = if (config.trace) try cli.traceRun(vm, config.max_cycles) else try vm.run(config.max_cycles);
            switch (result) {
                .@"continue" => return .cycle_limit,
                .ebreak => return .ebreak,
                .ecall => {},
            }
            // A write to one stream flushes the other first, so that the program's
            // stdout and stderr, and the report, keep their order.
            if (vm.readReg(17) == @backingInt(det.hostcall.Call.write)) switch (vm.readReg(10)) {
                1 => try cli.stderr.flush(),
                2 => try cli.stdout.flush(),
                else => {},
            };
            switch (try det.hostcall.handle(vm, env)) {
                .resumed => if (config.trace) try cli.stdout.flush(), // before the next trace line
                .exit => |status| return .{ .exit = status },
                .unknown => |number| return .{ .ecall = number }, // not a host call: stop, as ECALL always did
            }
        }
    }

    /// vm.run(max_cycles), one step at a time, printing a trace line for each
    /// instruction that retires. A faulting instruction gets no line: the fault report
    /// describes it.
    fn traceRun(cli: Cli, vm: *det.Cpu, max_cycles: ?u64) (det.StepError || Io.Writer.Error)!det.StepResult {
        while (true) {
            if (max_cycles) |limit| {
                if (vm.cycle_count >= limit) return .@"continue";
            }
            const cycle = vm.cycle_count;
            const pc = vm.pc;
            const raw = try vm.fetch(); // before step(): the instruction may overwrite itself
            const result = try vm.step();
            try report.printTraceLine(cli.stderr, cycle, pc, raw, vm);
            if (result != .@"continue") return result;
        }
    }
};

/// The report on stderr, in sections separated by blank lines. Each section first
/// flushes stdout, so that the program's output so far comes before it.
const Report = struct {
    cli: Cli,
    /// Whether a section was written (none needs a blank line before it).
    started: bool = false,

    fn section(self: *Report, comptime fmt: []const u8, fmt_args: anytype) Io.Writer.Error!void {
        try self.cli.stdout.flush();
        if (self.started) try self.cli.stderr.writeAll("\n");
        self.started = true;
        try self.cli.stderr.print(fmt, fmt_args);
    }
};

/// "no cycle limit" or "at most N cycles".
const Limit = struct {
    max_cycles: ?u64,

    pub fn format(self: Limit, w: *Io.Writer) Io.Writer.Error!void {
        const n = self.max_cycles orelse return w.writeAll("no cycle limit");
        return w.print("at most {f}", .{units.cycles(n)});
    }
};

test {
    _ = @import("main/tests.zig");
}
