//! Loading the program: flat binaries, ELF files, the demo, the initial stack pointer,
//! and the errors a file can give.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const main_mod = @import("../main.zig");
const load = main_mod.load;
const h = @import("test_helpers.zig");

/// Run the CLI and check that it fails with a usage or I/O error whose message is
/// exactly `want` (a template for h.expand(), with `path` for {path}).
fn expectError(fx: *h.Fixture, argv: []const [:0]const u8, path: []const u8, comptime want: []const u8) !void {
    try std.testing.expectEqual(h.status(.usage_or_io), try fx.run(argv));
    const text = try h.expand("Error: " ++ want ++ "\n", path);
    defer h.alloc.free(text);
    try std.testing.expectEqualStrings(text, fx.stderr());
    try std.testing.expectEqualStrings("", fx.stdout());
}

test "a missing file, a directory and an empty file are I/O errors" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const missing = try fx.path("missing.bin");
    try expectError(&fx, &.{missing}, missing, "cannot open '{path}': no such file");
    try expectError(&fx, &.{"src"}, "src", "cannot read '{path}': is a directory");
    const empty = try fx.file("empty.bin", "");
    try expectError(&fx, &.{empty}, empty, "'{path}' is empty");
}

test "a flat binary larger than the memory above its load address" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    // One byte more than the default 64 KiB. setLength makes a sparse file.
    const f = try fx.tmp.dir.createFile(h.io, "big.bin", .{});
    try f.setLength(h.io, 64 * 1024 + 1);
    f.close(h.io);
    const big = try fx.path("big.bin");
    try expectError(&fx, &.{big}, big, "'{path}' is too large: 65537 bytes, and 65536 fit at 0x00000000 in the 64 KiB of VM memory (see --memory)");
    // With more memory it loads (and runs into the zero halfword, a reserved encoding).
    try std.testing.expectEqual(h.status(.vm_fault), try fx.run(&.{ big, "--memory", "128KiB", "-q" }));
    try h.expectContains(fx.stderr(), "(IllegalInstruction)");

    // A file that fits at 0 does not fit higher up.
    const prog = try fx.file("prog.bin", &(h.ebreak ++ h.ebreak));
    try expectError(&fx, &.{ prog, "--memory", "4096", "--load-addr", "4092" }, prog, "'{path}' is too large: 8 bytes, and 4 fit at 0x00000FFC in the 4 KiB of VM memory (see --memory)");
}

test "--load-addr: a flat binary is loaded and started at the address" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("prog.bin", &h.le(&.{ 0x02A00093, 0x00100073 })); // ADDI ra, zero, 42; EBREAK
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ prog, "--load-addr", "0x100" }));
    try h.expectContains(fx.stderr(), "(8 bytes at 0x00000100)");
    try h.expectContains(fx.stderr(), "Stopped at EBREAK (0x00000104)");
    try h.expectContains(fx.stderr(), "  x1   ra   0x0000002A  42\n");
}

test "initial sp: programs start with sp at the 16-byte-aligned top of memory" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("sp.bin", &h.le(&.{ 0x00010593, 0x00100073 })); // ADDI a1, sp, 0; EBREAK
    const cases = [_]struct { [:0]const u8, u32 }{
        .{ "16", 0x10 },
        .{ "28", 0x10 }, // rounded down
        .{ "4100", 0x1000 },
        .{ "64KiB", 0x10000 },
        .{ "1MiB", 0x100000 },
    };
    for (cases) |c| {
        try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ prog, "--memory", c[0] }));
        const want = try h.alloc.print("  x11  a1   0x{X:0>8}", .{c[1]});
        defer h.alloc.free(want);
        try h.expectContains(fx.stderr(), want);
    }
    try std.testing.expectEqual(@as(u32, 0x10), main_mod.initialSp(0x1C));
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFF0), main_mod.initialSp(0xFFFF_FFFC));
}

test "ELF: the CLI detects an ELF file, loads its segments and starts at its entry" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const elf = h.tinyElf(&h.le(&.{ 0x02A00093, 0x00100073 }), 0x40, 5); // ADDI ra, zero, 42; EBREAK
    const prog = try fx.file("tiny.elf", &elf);
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{prog}));
    try h.expectContains(fx.stderr(), "(ELF executable, entry 0x00000040)");
    try h.expectContains(fx.stderr(), "Stopped at EBREAK (0x00000044)");
    try h.expectContains(fx.stderr(), "  x1   ra   0x0000002A  42\n");
}

test "ELF: a malformed file, a segment outside memory and --load-addr are errors" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    var elf = h.tinyElf(&h.ebreak, 0x40, 5);
    elf[18] = 62; // EM_X86_64
    const x86 = try fx.file("x86.elf", &elf);
    try expectError(&fx, &.{x86}, x86, "'{path}' is not a RISC-V ELF32 little-endian executable");

    const far = try fx.file("far.elf", &h.tinyElf(&h.ebreak, 0xFFFE, 5));
    try expectError(&fx, &.{far}, far, "'{path}' has a segment that is not inside the 64 KiB of VM memory (see --memory)");
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ far, "--memory", "128KiB", "-q" }));

    const ok = try fx.file("ok.elf", &h.tinyElf(&h.ebreak, 0, 5));
    try expectError(&fx, &.{ ok, "--load-addr", "0" }, ok, "--load-addr is for flat binaries, and '{path}' is an ELF executable, which says where it goes");
}

test "ELF: a toolchain-built executable (crc32) computes the native result, with --memory" {
    // tests/programs/elf/crc32.elf is built by `zig build programs`; its crt0 puts the
    // stack at the top of 256 KiB, so with less it faults there.
    const expected = try Io.Dir.cwd().readFileAlloc(h.io, "tests/programs/expected/crc32.txt", h.alloc, .limited(4096));
    defer h.alloc.free(expected);
    const a0 = try std.fmt.parseInt(u32, expected["a0=".len..][0..8], 16);
    const want = try h.alloc.print("  x10  a0   0x{X:0>8}", .{a0});
    defer h.alloc.free(want);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ "tests/programs/elf/crc32.elf", "--memory", "256KiB" }));
    try h.expectContains(fx.stderr(), "Stopped at EBREAK");
    try h.expectContains(fx.stderr(), want);
    try std.testing.expectEqual(h.status(.vm_fault), try fx.run(&.{"tests/programs/elf/crc32.elf"}));
    try h.expectContains(fx.stderr(), "  data address 0x0003FFFC, not inside the 64 KiB of VM memory (see --memory)\n");
}

test "ELF: a toolchain-built executable (crc32) loads on a CpuType through the library" {
    const Vm = det.CpuType(256 * 1024, .{});
    const image = try Io.Dir.cwd().readFileAlloc(h.io, "tests/programs/elf/crc32.elf", h.alloc, .limited(1 << 20));
    defer h.alloc.free(image);
    const expected = try Io.Dir.cwd().readFileAlloc(h.io, "tests/programs/expected/crc32.txt", h.alloc, .limited(4096));
    defer h.alloc.free(expected);
    const vm = try h.alloc.create(Vm);
    defer h.alloc.destroy(vm);
    vm.reset();
    vm.pc = try det.loader.loadElf(vm, image);
    try std.testing.expectEqual(det.StepResult.ebreak, try vm.run(10_000_000));
    var a0_text: [12]u8 = undefined;
    const a0 = try std.mem.print(&a0_text, "a0={x:0>8}", .{vm.readReg(10)});
    try std.testing.expectStringStartsWith(expected, a0);
}

test "the demo: a memory too small for it fails cleanly" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    // The program itself does not fit: a configuration (usage) error
    try expectError(&fx, &.{ "--demo", "--memory", "16" }, "", "the demo program needs 20 bytes of VM memory, and there are 16 bytes (see --memory)");
    // The program loads, but its store to address 100 faults
    try std.testing.expectEqual(h.status(.vm_fault), try fx.run(&.{ "--demo", "--memory", "100" }));
    try h.expectContains(fx.stderr(), "(AddressOutOfBounds)");
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{ "--demo", "--memory", "104" }));
    try std.testing.expectEqual(@as(u32, 104), load.demo_min_memory);
}

test "demo_program: every instruction decodes as its comment says" {
    // Checks the real bytes. The second word once had 0x0A/0xA0 transposed,
    // which encodes ADDI x2, x20, 0 instead of ADDI x2, x0, 10.
    const Expect = struct { op: det.Opcode, rd: u5 = 0, rs1: u5 = 0, rs2: u5 = 0, imm: i32 = 0 };
    const want = [_]Expect{
        .{ .op = .{ .i = .ADDI }, .rd = 1, .rs1 = 0, .imm = 100 },
        .{ .op = .{ .i = .ADDI }, .rd = 2, .rs1 = 0, .imm = 10 },
        .{ .op = .{ .i = .ADD }, .rd = 3, .rs1 = 1, .rs2 = 2 },
        .{ .op = .{ .i = .SW }, .rs1 = 1, .rs2 = 3, .imm = 0 },
        .{ .op = .{ .i = .ECALL } },
    };
    try std.testing.expectEqual(want.len * 4, load.demo_program.len);
    for (want, 0..) |w, i| {
        const raw = std.mem.readInt(u32, load.demo_program[4 * i ..][0..4], .little);
        const inst = try det.decode(raw);
        try std.testing.expectEqual(w.op, inst.op);
        try std.testing.expectEqual(w.rd, inst.rd);
        try std.testing.expectEqual(w.rs1, inst.rs1);
        try std.testing.expectEqual(w.rs2, inst.rs2);
        try std.testing.expectEqual(w.imm, inst.imm);
    }
}
