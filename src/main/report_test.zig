//! The report, exactly: whole runs of the CLI compared with the text they must print
//! (docs/design/cli.md), and the pieces the report is made of.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const main_mod = @import("../main.zig");
const report = main_mod.report;
const units = main_mod.units;
const h = @import("test_helpers.zig");

/// A whole run: the program (written to a file, whose path is the first argument;
/// null for none), the other arguments, and what must come out. In `stderr`,
/// {path} is the program's path, {mem} this build's memory size, and
/// {[sp]X:0>8} and {sp_dec} the initial sp.
const Run = struct {
    name: []const u8,
    program: ?[]const u8,
    args: []const [:0]const u8 = &.{},
    /// Smallest memory the run needs; others skip it.
    min_memory: u32,
    /// Largest memory with which the run does what is expected.
    max_memory: u32 = std.math.maxInt(u32),
    status: u8,
    stdin: []const u8 = "",
    stdout: []const u8 = "",
    stderr: []const u8,
};

const at100 = h.le(&.{
    0x02A00093, // ADDI ra, zero, 42
    0x00100073, // EBREAK
});

const oob = h.le(&.{
    0x800000B7, // LUI ra, 0x80000
    0x0040A103, // LW sp, 4(ra)
});

const pc_oob = h.le(&.{
    0x800002B7, // LUI t0, 0x80000
    0x00028067, // JALR zero, 0(t0)
});

const misaligned = h.le(&.{
    0x00100293, // ADDI t0, zero, 1
    0x0002A303, // LW t1, 0(t0)
});

/// A store, a 16-bit instruction, a taken branch: what --trace shows. Needs 0x101 bytes.
const trace_program = h.le(&.{
    0x05500293, // ADDI t0, zero, 0x55
    0x10500023, // SB t0, 0x100(zero)
}) ++ [_]u8{ 0x05, 0x05 } // C.ADDI a0, 1
++ h.le(&.{
    0x00000363, // BEQ zero, zero, +6 (to 0x10)
}) ++ [_]u8{ 0x01, 0x00 } // C.NOP, skipped
++ h.ebreak;

const runs = [_]Run{
    .{
        .name = "exit",
        .program = &h.hello,
        .min_memory = h.hello.len,
        .status = 7,
        .stdout = "hello\n",
        .stderr =
        \\Running {path} (42 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Program exited with status 7 after 9 cycles
        \\
        \\Registers:
        \\  pc        0x00000024
        \\  x2   sp   0x{sp}  {sp_dec}
        \\  x10  a0   0x00000007  7
        \\  x11  a1   0x00000024  36
        \\  x12  a2   0x00000006  6
        \\  x17  a7   0x0000005D  93
        \\
        ,
    },
    .{
        .name = "EBREAK, at --load-addr",
        .program = &at100,
        .args = &.{ "--load-addr", "0x100" },
        .min_memory = 0x108,
        .status = 0,
        .stderr =
        \\Running {path} (8 bytes at 0x00000100) in {mem} of VM memory, no cycle limit
        \\
        \\Stopped at EBREAK (0x00000104) after 2 cycles
        \\
        \\Registers:
        \\  pc        0x00000108
        \\  x1   ra   0x0000002A  42
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "an ECALL that is not a host call",
        .program = &h.ecall,
        .min_memory = 4,
        .status = 0,
        .stderr =
        \\Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Stopped at ECALL (0x00000000) after 1 cycle: a7 = 0 is not a host call
        \\
        \\Registers:
        \\  pc        0x00000004
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "the cycle limit",
        .program = &h.loop,
        .args = &.{ "--max-cycles", "100" },
        .min_memory = 4,
        .status = 2,
        .stderr =
        \\Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, at most 100 cycles
        \\
        \\Cycle limit reached after 100 cycles
        \\
        \\Registers:
        \\  pc        0x00000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "an illegal instruction",
        .program = &h.illegal,
        .min_memory = 4,
        .status = 3,
        .stderr =
        \\Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Fault after 0 cycles: illegal instruction (IllegalInstruction)
        \\  instruction at 0x00000000: FFFFFFFF  (does not decode)
        \\
        \\Registers:
        \\  pc        0x00000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "a load outside memory",
        .program = &oob,
        .min_memory = 8,
        .max_memory = 0x8000_0000,
        .status = 3,
        .stderr =
        \\Running {path} (8 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Fault after 1 cycle: memory access out of bounds (AddressOutOfBounds)
        \\  instruction at 0x00000004: 0040A103  LW sp, 4(ra)
        \\  data address 0x80000004, not inside the {mem} of VM memory (build option -Dmemory_size)
        \\
        \\Registers:
        \\  pc        0x00000004
        \\  x1   ra   0x80000000  -2147483648
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "a jump outside memory",
        .program = &pc_oob,
        .min_memory = 8,
        .max_memory = 0x8000_0000,
        .status = 3,
        .stderr =
        \\Running {path} (8 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Fault after 2 cycles: pc out of bounds (PCOutOfBounds)
        \\  instruction at 0x80000000, not inside the {mem} of VM memory (build option -Dmemory_size)
        \\
        \\Registers:
        \\  pc        0x80000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\  x5   t0   0x80000000  -2147483648
        \\
        ,
    },
    .{
        .name = "a misaligned load",
        .program = &misaligned,
        .min_memory = 8,
        .status = 3,
        .stderr =
        \\Running {path} (8 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Fault after 1 cycle: misaligned memory access (MisalignedAccess)
        \\  instruction at 0x00000004: 0002A303  LW t1, 0(t0)
        \\  data address 0x00000001
        \\
        \\Registers:
        \\  pc        0x00000004
        \\  x2   sp   0x{sp}  {sp_dec}
        \\  x5   t0   0x00000001  1
        \\
        ,
    },
    .{
        .name = "the demo",
        .program = null,
        .args = &.{"--demo"},
        .min_memory = 104,
        .status = 0,
        .stderr =
        \\Demo program:
        \\00000000  06400093  ADDI ra, zero, 100
        \\00000004  00A00113  ADDI sp, zero, 10
        \\00000008  002081B3  ADD gp, ra, sp
        \\0000000C  0030A023  SW gp, 0(ra)
        \\00000010  00000073  ECALL
        \\
        \\Running the demo (20 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Stopped at ECALL (0x00000010) after 5 cycles: a7 = 0 is not a host call
        \\
        \\Registers:
        \\  pc        0x00000014
        \\  x1   ra   0x00000064  100
        \\  x2   sp   0x0000000A  10
        \\  x3   gp   0x0000006E  110
        \\
        \\Memory at 0x00000064 (the demo's store): 0x0000006E  110
        \\
        ,
    },
    .{
        .name = "--trace",
        .program = &trace_program,
        .args = &.{"--trace"},
        .min_memory = 0x101,
        .status = 0,
        .stderr =
        \\Running {path} (20 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\       0  00000000  05500293  ADDI t0, zero, 85           t0 = 0x00000055
        \\       1  00000004  10500023  SB t0, 256(zero)            mem[0x00000100] = 0x55
        \\       2  00000008  0505      C.ADDI a0, a0, 1            a0 = 0x00000001
        \\       3  0000000A  00000363  BEQ zero, zero, 0x00000010
        \\       4  00000010  00100073  EBREAK
        \\
        \\Stopped at EBREAK (0x00000010) after 5 cycles
        \\
        \\Registers:
        \\  pc        0x00000014
        \\  x2   sp   0x{sp}  {sp_dec}
        \\  x5   t0   0x00000055  85
        \\  x10  a0   0x00000001  1
        \\
        ,
    },
    .{
        .name = "--trace shows an instruction that overwrites itself as it ran",
        .program = &h.le(&.{
            0x01300293, // ADDI t0, zero, 0x13 (a NOP's bits)
            0x00502223, // SW t0, 4(zero): over itself
            0x00100073, // EBREAK
        }),
        .args = &.{ "--trace", "-q" },
        .min_memory = 12,
        .status = 0,
        .stderr =
        \\       0  00000000  01300293  ADDI t0, zero, 19           t0 = 0x00000013
        \\       1  00000004  00502223  SW t0, 4(zero)              mem[0x00000004] = 0x00000013
        \\       2  00000008  00100073  EBREAK
        \\
        ,
    },
    .{
        .name = "--trace stops at the cycle limit",
        .program = &h.loop,
        .args = &.{ "--trace", "--max-cycles", "2" },
        .min_memory = 4,
        .status = 2,
        .stderr =
        \\Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, at most 2 cycles
        \\       0  00000000  0000006F  JAL zero, 0x00000000
        \\       1  00000000  0000006F  JAL zero, 0x00000000
        \\
        \\Cycle limit reached after 2 cycles
        \\
        \\Registers:
        \\  pc        0x00000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "--trace: a faulting instruction has no line",
        .program = &misaligned,
        .args = &.{ "--trace", "-q" },
        .min_memory = 8,
        .status = 3,
        .stderr =
        \\       0  00000000  00100293  ADDI t0, zero, 1            t0 = 0x00000001
        \\
        \\Fault after 1 cycle: misaligned memory access (MisalignedAccess)
        \\  instruction at 0x00000004: 0002A303  LW t1, 0(t0)
        \\  data address 0x00000001
        \\
        \\Registers:
        \\  pc        0x00000004
        \\  x2   sp   0x{sp}  {sp_dec}
        \\  x5   t0   0x00000001  1
        \\
        ,
    },
    .{
        .name = "-q: only the program's output",
        .program = &h.hello,
        .args = &.{"-q"},
        .min_memory = h.hello.len,
        .status = 7,
        .stdout = "hello\n",
        .stderr = "",
    },
    .{
        .name = "-q: a fault is still reported",
        .program = &h.illegal,
        .args = &.{"--quiet"},
        .min_memory = 4,
        .status = 3,
        .stderr =
        \\Fault after 0 cycles: illegal instruction (IllegalInstruction)
        \\  instruction at 0x00000000: FFFFFFFF  (does not decode)
        \\
        \\Registers:
        \\  pc        0x00000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        ,
    },
    .{
        .name = "--dump-range, after the report",
        .program = &h.ebreak,
        .args = &.{ "--dump-range", "0:0x34" },
        .min_memory = 0x34,
        .status = 0,
        .stderr =
        \\Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, no cycle limit
        \\
        \\Stopped at EBREAK (0x00000000) after 1 cycle
        \\
        \\Registers:
        \\  pc        0x00000004
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        \\00000000  73 00 10 00 00 00 00 00  00 00 00 00 00 00 00 00  |s...............|
        \\00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
        \\*
        \\00000030  00 00 00 00                                       |....|
        \\00000034
        \\
        ,
    },
    .{
        .name = "--dump-memory after a fault, -q",
        .program = &h.illegal,
        .args = &.{ "-q", "--dump-memory=raw", "--dump-range", "0:8" },
        .min_memory = 8,
        .status = 3,
        .stderr =
        \\Fault after 0 cycles: illegal instruction (IllegalInstruction)
        \\  instruction at 0x00000000: FFFFFFFF  (does not decode)
        \\
        \\Registers:
        \\  pc        0x00000000
        \\  x2   sp   0x{sp}  {sp_dec}
        \\
        \\FFFFFFFF00000000
        \\
        ,
    },
    .{
        .name = "--input - reads stdin",
        .program = &h.echo,
        .args = &.{ "-q", "--input", "-" },
        .min_memory = 0x240,
        .status = 7,
        .stdin = "piped in\n",
        .stdout = "piped in\n",
        .stderr = "",
    },
};

test "report: whole runs, exactly" {
    for (runs) |r| {
        if (det.Cpu.mem_size >= r.min_memory and det.Cpu.mem_size <= r.max_memory) {
            var fx: h.Fixture = .init();
            defer fx.deinit();
            fx.stdin = .fixed(r.stdin);
            var argv: std.ArrayList([:0]const u8) = .empty;
            defer argv.deinit(h.alloc);
            const path: []const u8 = if (r.program) |p| try fx.file("prog.bin", p) else "";
            if (r.program != null) try argv.append(h.alloc, try fx.path("prog.bin"));
            try argv.appendSlice(h.alloc, r.args);

            const got = try fx.run(argv.items);
            errdefer std.debug.print("\nrun: {s}\n", .{r.name});
            const want_stderr = try h.expand(r.stderr, path);
            defer h.alloc.free(want_stderr);
            try std.testing.expectEqualStrings(want_stderr, fx.stderr());
            try std.testing.expectEqualStrings(r.stdout, fx.stdout());
            try std.testing.expectEqual(r.status, got);
        }
    }
}

test "--digest: the SHA-256 of the final state, as stateDigest() gives it" {
    try h.needMemory(h.hello.len);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("hello.bin", &h.hello);
    try std.testing.expectEqual(@as(u8, 7), try fx.run(&.{ prog, "-q", "--digest" }));

    // The same run through the library: load at 0, sp at the top, host calls.
    const vm = try h.alloc.create(det.Cpu);
    defer h.alloc.destroy(vm);
    vm.reset();
    try vm.loadProgram(&h.hello, 0);
    vm.writeReg(2, main_mod.initial_sp);
    var sink: Io.Writer.Discarding = .init(&.{});
    var env: det.hostcall.Env = .{ .stdout = &sink.writer, .stderr = &sink.writer };
    while (try vm.run(null) == .ecall) {
        if (try det.hostcall.handle(vm, &env) == .exit) break;
    }
    const want = try h.alloc.print("State digest: {s}\n", .{&std.fmt.bytesToHex(vm.stateDigest(), .lower)});
    defer h.alloc.free(want);
    try std.testing.expectEqualStrings(want, fx.stderr());
}

test "--trace changes nothing the program computes" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const input = try fx.file("input.txt", "some input\n");
    const programs = [_]struct { []const u8, u32 }{
        .{ &h.echo, 0x240 },
        .{ &h.hello, h.hello.len },
        .{ &trace_program, 0x101 },
        .{ &misaligned, 8 }, // a fault
        .{ &h.loop, 4 }, // the cycle limit
    };
    for (programs) |p| {
        if (det.Cpu.mem_size < p[1]) continue;
        const prog = try fx.file("prog.bin", p[0]);
        const plain_status = try fx.run(&.{ prog, "-q", "--digest", "--input", input, "--max-cycles", "1000" });
        const plain_stdout = try h.alloc.dupe(u8, fx.stdout());
        defer h.alloc.free(plain_stdout);
        const plain_digest = try h.alloc.dupe(u8, lastLine(fx.stderr()));
        defer h.alloc.free(plain_digest);

        const traced_status = try fx.run(&.{ prog, "-q", "--digest", "--input", input, "--max-cycles", "1000", "--trace" });
        try std.testing.expectEqual(plain_status, traced_status);
        try std.testing.expectEqualStrings(plain_stdout, fx.stdout());
        try std.testing.expectStringStartsWith(plain_digest, "State digest: ");
        try std.testing.expectEqualStrings(plain_digest, lastLine(fx.stderr()));
    }
}

fn lastLine(text: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, text, "\n");
    const start = if (std.mem.findScalarLast(u8, trimmed, '\n')) |i| i + 1 else 0;
    return trimmed[start..];
}

test "stdout carries only the program's output, and the streams keep their order" {
    // The program writes "A" to stdout, "B" to stderr and "C" to stdout. With both
    // streams buffered into one file, as with `> log 2>&1`, the log must show the
    // report and the three writes in the order they happened.
    try h.needMemory(66);
    const streams = h.le(&.{
        0x00000597, // AUIPC a1, 0
        0x03C58593, // ADDI a1, a1, 60 (the text)
        0x00200613, // ADDI a2, zero, 2
        0x04000893, // ADDI a7, zero, 64 (write)
        0x00100513, // ADDI a0, zero, 1
        0x00000073, // ECALL: "A\n" to stdout
        0x00258593, // ADDI a1, a1, 2
        0x00200513, // ADDI a0, zero, 2
        0x00000073, // ECALL: "B\n" to stderr
        0x00258593, // ADDI a1, a1, 2
        0x00100513, // ADDI a0, zero, 1
        0x00000073, // ECALL: "C\n" to stdout
        0x00000513, // ADDI a0, zero, 0
        0x05D00893, // ADDI a7, zero, 93 (exit)
        0x00000073, // ECALL
    }) ++ "A\nB\nC\n".*;
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("streams.bin", &streams);
    const log = try fx.tmp.dir.createFile(h.io, "log.txt", .{ .read = true });
    defer log.close(h.io);
    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_fw = main_mod.stdStreamWriter(log, h.io, &out_buf);
    var err_fw = main_mod.stdStreamWriter(log, h.io, &err_buf);
    var cli = fx.cli();
    cli.stdout = &out_fw.interface;
    cli.stderr = &err_fw.interface;
    try std.testing.expectEqual(@as(u8, 0), cli.run(&.{ "determinant", prog }));

    var content: [4096]u8 = undefined;
    const text = content[0..try log.readPositionalAll(h.io, &content, 0)];
    const running = std.mem.find(u8, text, "Running ") orelse return error.TestExpectedEqual;
    const a = std.mem.find(u8, text, "A\n") orelse return error.TestExpectedEqual;
    const b = std.mem.find(u8, text, "B\n") orelse return error.TestExpectedEqual;
    const c = std.mem.find(u8, text, "C\n") orelse return error.TestExpectedEqual;
    const exited = std.mem.find(u8, text, "Program exited") orelse return error.TestExpectedEqual;
    try std.testing.expect(running < a and a < b and b < c and c < exited);

    // Apart, stdout holds exactly what the program wrote there.
    try std.testing.expectEqual(@as(u8, 0), try fx.run(&.{ prog, "-q" }));
    try std.testing.expectEqualStrings("A\nC\n", fx.stdout());
    try std.testing.expectEqualStrings("B\n", fx.stderr());
}

test "the preamble is written before the program starts, so it shows while the program runs" {
    // A program that runs for a long time, or hangs, must already show its "Running"
    // line. With --trace, each instruction writes its line as it retires, so the
    // preamble must arrive in a write of its own, before the first trace line; without
    // it, before the report.
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("loop.bin", &h.loop);
    const want = try h.expand("Running {path} (4 bytes at 0x00000000) in {mem} of VM memory, at most 3 cycles\n", prog);
    defer h.alloc.free(want);
    const argvs = [_][]const [:0]const u8{
        &.{ "determinant", prog, "--max-cycles", "3" },
        &.{ "determinant", prog, "--max-cycles", "3", "--trace" },
    };
    for (argvs) |argv| {
        var buf: [4096]u8 = undefined;
        var writes: h.Writes = .init(&buf);
        defer writes.deinit();
        var cli = fx.cli();
        cli.stderr = &writes.writer;
        try std.testing.expectEqual(h.status(.cycle_limit), cli.run(argv));
        try std.testing.expect(writes.log.items.len >= 2);
        try std.testing.expectEqualStrings(want, writes.log.items[0]);
    }
}

test "printStop: an exit status is shown signed, as the program passed it" {
    const vm = try h.alloc.create(det.Cpu);
    defer h.alloc.destroy(vm);
    vm.reset();
    vm.cycle_count = 1;
    var aw: Io.Writer.Allocating = .init(h.alloc);
    defer aw.deinit();
    try report.printStop(&aw.writer, vm, .{ .exit = 0xFFFF_FFFF });
    try std.testing.expectEqualStrings("Program exited with status -1 after 1 cycle\n", aw.written());
}

test "printRegisters: pc, then every non-zero register with its ABI name" {
    const vm = try h.alloc.create(det.Cpu);
    defer h.alloc.destroy(vm);
    vm.reset();
    vm.pc = 0x1234;
    for (1..32) |i| vm.writeReg(@intCast(i), @intCast(i));
    vm.writeReg(31, 0xFFFF_FFFF);
    var aw: Io.Writer.Allocating = .init(h.alloc);
    defer aw.deinit();
    try report.printRegisters(&aw.writer, vm);
    try std.testing.expectStringStartsWith(aw.written(), "\nRegisters:\n  pc        0x00001234\n  x1   ra   0x00000001  1\n");
    try h.expectContains(aw.written(), "\n  x8   s0   0x00000008  8\n");
    try h.expectContains(aw.written(), "\n  x27  s11  0x0000001B  27\n");
    try std.testing.expect(std.mem.endsWith(u8, aw.written(), "\n  x31  t6   0xFFFFFFFF  -1\n"));
    try h.expectNotContains(aw.written(), "zero");
}

test "faultText: every fault has its own words" {
    const faults = [_]det.StepError{ error.IllegalInstruction, error.MisalignedPC, error.PCOutOfBounds, error.MisalignedAccess, error.AddressOutOfBounds };
    for (faults, 0..) |a, i| {
        try std.testing.expect(report.faultText(a).len > 0);
        for (faults[i + 1 ..]) |b| try std.testing.expect(!std.mem.eql(u8, report.faultText(a), report.faultText(b)));
    }
}

test "ioText: common I/O errors in words, others by name" {
    try std.testing.expectEqualStrings("no such file", report.ioText(error.FileNotFound));
    try std.testing.expectEqualStrings("is a directory", report.ioText(error.IsDir));
    try std.testing.expectEqualStrings("permission denied", report.ioText(error.AccessDenied));
    try std.testing.expectEqualStrings("too large", report.ioText(error.StreamTooLong));
    try std.testing.expectEqualStrings("Unexpected", report.ioText(error.Unexpected));
}

test "MemSize and Count" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("64 KiB", try std.mem.print(&buf, "{f}", .{units.MemSize{ .bytes = 64 * 1024 }}));
    try std.testing.expectEqualStrings("256 MiB", try std.mem.print(&buf, "{f}", .{units.MemSize{ .bytes = 256 * 1024 * 1024 }}));
    try std.testing.expectEqualStrings("1025 KiB", try std.mem.print(&buf, "{f}", .{units.MemSize{ .bytes = 1024 * 1024 + 1024 }}));
    try std.testing.expectEqualStrings("100 bytes", try std.mem.print(&buf, "{f}", .{units.MemSize{ .bytes = 100 }}));
    try std.testing.expectEqualStrings("0 cycles", try std.mem.print(&buf, "{f}", .{units.cycles(0)}));
    try std.testing.expectEqualStrings("1 cycle", try std.mem.print(&buf, "{f}", .{units.cycles(1)}));
    try std.testing.expectEqualStrings("1 byte", try std.mem.print(&buf, "{f}", .{units.count(1, "byte")}));
    try std.testing.expectEqualStrings("2 bytes", try std.mem.print(&buf, "{f}", .{units.count(2, "byte")}));
}
