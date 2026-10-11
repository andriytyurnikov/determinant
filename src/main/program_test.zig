//! Host calls through the CLI: --input, write and exit (docs/design/host-calls.md).

const std = @import("std");
const det = @import("determinant");
const h = @import("test_helpers.zig");

test "host calls: the program reads --input, writes it out and exits with its status" {
    try h.needMemory(0x240);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("echo.bin", &h.echo);
    const input = try fx.file("input.txt", "hello, host\n");
    try std.testing.expectEqual(@as(u8, 7), try fx.run(&.{ prog, "--input", input }));
    try std.testing.expectEqualStrings("hello, host\n", fx.stdout());
    try h.expectContains(fx.stderr(), "Program exited with status 7 after 13 cycles\n");
}

test "host calls: without --input, read returns end of input" {
    try h.needMemory(0x240);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("echo.bin", &h.echo);
    try std.testing.expectEqual(@as(u8, 7), try fx.run(&.{prog}));
    try std.testing.expectEqualStrings("", fx.stdout());
    try h.expectNotContains(fx.stderr(), "  x12 "); // a2, the bytes read, is 0
    try h.expectContains(fx.stderr(), "Program exited with status 7");
}

test "host calls: --input - reads all of stdin before the run" {
    try h.needMemory(0x240);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("echo.bin", &h.echo);
    fx.stdin = .fixed("from stdin\n");
    try std.testing.expectEqual(@as(u8, 7), try fx.run(&.{ prog, "--input", "-" }));
    try std.testing.expectEqualStrings("from stdin\n", fx.stdout());
}

test "--input: a missing file is an I/O error, before the run" {
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("stop.bin", &h.ebreak);
    try std.testing.expectEqual(h.status(.usage_or_io), try fx.run(&.{ prog, "--input", "/nonexistent/input" }));
    try std.testing.expectEqualStrings("Error: cannot read input '/nonexistent/input': no such file\n", fx.stderr());
}

test "host calls: exit(3) is not mistaken for a VM fault (--dump-memory still runs)" {
    try h.needMemory(16);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("exit3.bin", &h.le(&.{
        0x05D00893, // ADDI a7, zero, 93 (exit)
        0x00300513, // ADDI a0, zero, 3
        0x00000073, // ECALL
    }));
    try std.testing.expectEqual(@as(u8, 3), try fx.run(&.{ prog, "--dump-memory" }));
    try h.expectContains(fx.stderr(), "Program exited with status 3");
    try h.expectContains(fx.stderr(), "00000000  93 08 D0 05"); // the memory dump ran
    try h.expectNotContains(fx.stderr(), "Fault");
}

test "host calls: the exit status keeps the low 8 bits, as a POSIX process's does" {
    try h.needMemory(16);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("exit263.bin", &h.le(&.{
        0x05D00893, // ADDI a7, zero, 93 (exit)
        0x10700513, // ADDI a0, zero, 263
        0x00000073, // ECALL
    }));
    try std.testing.expectEqual(@as(u8, 7), try fx.run(&.{prog}));
    try h.expectContains(fx.stderr(), "Program exited with status 263");
}

test "host calls: exit_group (94) ends the program like exit" {
    try h.needMemory(16);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("exit_group.bin", &h.le(&.{
        0x05E00893, // ADDI a7, zero, 94 (exit_group)
        0x00500513, // ADDI a0, zero, 5
        0x00000073, // ECALL
    }));
    try std.testing.expectEqual(@as(u8, 5), try fx.run(&.{ prog, "-q" }));
    try std.testing.expectEqualStrings("", fx.stderr());
}

test "host calls: an ECALL that is not a host call names a7 and exits 0" {
    try h.needMemory(8);
    var fx: h.Fixture = .init();
    defer fx.deinit();
    const prog = try fx.file("ecall.bin", &h.le(&.{
        0x02A00893, // ADDI a7, zero, 42
        0x00000073, // ECALL
    }));
    try std.testing.expectEqual(h.status(.ok), try fx.run(&.{prog}));
    try h.expectContains(fx.stderr(), "Stopped at ECALL (0x00000004) after 2 cycles: a7 = 42 is not a host call\n");
}
