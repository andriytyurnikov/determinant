const std = @import("std");
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("../test_helpers.zig");

const encodeCsr = h.encodeCsr;
const loadInst = h.loadInst;

// --- Performance counter tests ---

test "step: read cycle counter (0xC00)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0001_FFFF_FFFE;
    // CSRRS x1, 0xC00, x0 -- read cycle low 32
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(0xFFFFFFFE, cpu.readReg(1));
}

test "step: read cycleh (0xC80)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0005_0000_0000;
    // CSRRS x1, 0xC80, x0 -- read cycle high 32
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC80));
    _ = try cpu.step();
    try std.testing.expectEqual(5, cpu.readReg(1));
}

test "step: read instret (0xC02) same as cycle" {
    var cpu = Cpu.init();
    cpu.cycle_count = 999;
    // CSRRS x1, 0xC02, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC02));
    _ = try cpu.step();
    try std.testing.expectEqual(999, cpu.readReg(1));
}

test "step: read instreth (0xC82) same as cycleh" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0003_0000_0000;
    // CSRRS x1, 0xC82, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC82));
    _ = try cpu.step();
    try std.testing.expectEqual(3, cpu.readReg(1));
}

// --- Error tests ---

test "step: table (counter_error)" {
    try h.expectSteps(&.{
        // CSRRW x2, 0xC00, x1 -- attempt to write cycle counter
        .{ .name = "write to read-only CSR (cycle) is illegal", .inst = encodeCsr(0b001, 2, 1, 0xC00), .regs = &.{.{ 1, 42 }}, .err = error.IllegalInstruction },
        // CSRRS x1, 0x001, x0 -- unknown CSR
        .{ .name = "unknown CSR address is illegal", .inst = encodeCsr(0b010, 1, 0, 0x001), .err = error.IllegalInstruction },
        // CSRRW x0, 0x001, x1 -- unknown CSR, but not read-only
        .{ .name = "write to unknown non-read-only CSR is illegal", .inst = encodeCsr(0b001, 0, 1, 0x001), .regs = &.{.{ 1, 42 }}, .err = error.IllegalInstruction },
        // CSRRS x2, 0xC00, x1 -- rs1!=x0, attempts write to read-only
        .{ .name = "CSRRS with rs1!=x0 to read-only CSR is illegal", .inst = encodeCsr(0b010, 2, 1, 0xC00), .regs = &.{.{ 1, 0 }}, .err = error.IllegalInstruction },
        // CSRRWI x0, 0xC00, 5 -- rd=x0 skips read, but write still attempted
        .{ .name = "CSRRWI with rd=x0 to read-only CSR still fails (write attempted)", .inst = encodeCsr(0b101, 0, 5, 0xC00), .err = error.IllegalInstruction },
        // CSRRCI x2, 0xC00, 5 -- zimm=5 (!=0), attempts clear on read-only CSR
        .{ .name = "CSRRCI with zimm!=0 to read-only CSR fails", .inst = encodeCsr(0b111, 2, 5, 0xC00), .err = error.IllegalInstruction },
        // CSRRW x0, 0xC00, x1 -- rd=x0, but write still attempted
        .{ .name = "CSRRW x0 to read-only CSR still fails (write attempted)", .inst = encodeCsr(0b001, 0, 1, 0xC00), .regs = &.{.{ 1, 42 }}, .err = error.IllegalInstruction },
        // CSRRSI x2, 0xC00, 5 -- zimm=5 (!=0), attempts set on read-only CSR
        .{ .name = "CSRRSI with zimm!=0 to read-only CSR fails", .inst = encodeCsr(0b110, 2, 5, 0xC00), .err = error.IllegalInstruction },
    });
}

test "step: CSRRS to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 77;
    // CSRRS x1, 0xC00, x0 -- read-only access to read-only CSR is fine
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(77, cpu.readReg(1));
}

test "step: CSRRC to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 88;
    // CSRRC x1, 0xC00, x0
    loadInst(&cpu, encodeCsr(0b011, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(88, cpu.readReg(1));
}

test "step: CSRRSI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 55;
    // CSRRSI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b110, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(55, cpu.readReg(1));
}

test "step: CSRRCI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 66;
    // CSRRCI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b111, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(66, cpu.readReg(1));
}

// --- Isolated Csr unit tests (no CPU step) ---

const zicsr = @import("../zicsr.zig");

test "Csr.write to read-only address (0xC00) returns IllegalInstruction" {
    var csr = zicsr.Csr{};
    try std.testing.expectError(error.IllegalInstruction, csr.write(0xC00, 42));
}

test "Csr.read cycle counter returns low 32 bits" {
    const csr = zicsr.Csr{};
    const val = try csr.read(0x0000_0001_DEAD_BEEF, 0xC00);
    try std.testing.expectEqual(0xDEAD_BEEF, val);
}

test "Csr.read cycleh returns high 32 bits" {
    const csr = zicsr.Csr{};
    const val = try csr.read(0x0000_0005_0000_0000, 0xC80);
    try std.testing.expectEqual(5, val);
}

test "Csr.read unknown address returns IllegalInstruction" {
    const csr = zicsr.Csr{};
    try std.testing.expectError(error.IllegalInstruction, csr.read(0, 0x001));
}

test "Csr.write to unknown non-read-only address returns IllegalInstruction" {
    var csr = zicsr.Csr{};
    try std.testing.expectError(error.IllegalInstruction, csr.write(0x001, 42));
}

test "Csr.write and read mscratch round-trip" {
    var csr = zicsr.Csr{};
    try csr.write(0x340, 0xCAFE);
    const val = try csr.read(0, 0x340);
    try std.testing.expectEqual(0xCAFE, val);
}
