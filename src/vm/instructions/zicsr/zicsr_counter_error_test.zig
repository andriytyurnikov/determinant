const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder/branch_decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
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
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(1));
}

test "step: read cycleh (0xC80)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0005_0000_0000;
    // CSRRS x1, 0xC80, x0 -- read cycle high 32
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC80));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
}

test "step: read instret (0xC02) same as cycle" {
    var cpu = Cpu.init();
    cpu.cycle_count = 999;
    // CSRRS x1, 0xC02, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC02));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 999), cpu.readReg(1));
}

test "step: read instreth (0xC82) same as cycleh" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0003_0000_0000;
    // CSRRS x1, 0xC82, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC82));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(1));
}

// --- Error tests ---

test "step: write to read-only CSR (cycle) is illegal" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    // CSRRW x2, 0xC00, x1 -- attempt to write cycle counter
    loadInst(&cpu, encodeCsr(0b001, 2, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRS to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 77;
    // CSRRS x1, 0xC00, x0 -- read-only access to read-only CSR is fine
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 77), cpu.readReg(1));
}

test "step: CSRRC to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 88;
    // CSRRC x1, 0xC00, x0
    loadInst(&cpu, encodeCsr(0b011, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 88), cpu.readReg(1));
}

test "step: CSRRSI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 55;
    // CSRRSI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b110, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 55), cpu.readReg(1));
}

test "step: CSRRCI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 66;
    // CSRRCI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b111, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 66), cpu.readReg(1));
}

test "step: unknown CSR address is illegal" {
    var cpu = Cpu.init();
    // CSRRS x1, 0x001, x0 -- unknown CSR
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0x001));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRS with rs1!=x0 to read-only CSR is illegal" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    // CSRRS x2, 0xC00, x1 -- rs1!=x0, attempts write to read-only
    loadInst(&cpu, encodeCsr(0b010, 2, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRWI with rd=x0 to read-only CSR still fails (write attempted)" {
    var cpu = Cpu.init();
    // CSRRWI x0, 0xC00, 5 -- rd=x0 skips read, but write still attempted
    loadInst(&cpu, encodeCsr(0b101, 0, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRCI with zimm!=0 to read-only CSR fails" {
    var cpu = Cpu.init();
    // CSRRCI x2, 0xC00, 5 -- zimm=5 (!=0), attempts clear on read-only CSR
    loadInst(&cpu, encodeCsr(0b111, 2, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRW x0 to read-only CSR still fails (write attempted)" {
    var cpu = Cpu.init();
    // CSRRW x0, 0xC00, x1 -- rd=x0, but write still attempted
    cpu.writeReg(1, 42);
    loadInst(&cpu, encodeCsr(0b001, 0, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRSI with zimm!=0 to read-only CSR fails" {
    var cpu = Cpu.init();
    // CSRRSI x2, 0xC00, 5 -- zimm=5 (!=0), attempts set on read-only CSR
    loadInst(&cpu, encodeCsr(0b110, 2, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

// --- Isolated Csr unit tests (no CPU step) ---

const zicsr = @import("zicsr.zig");

test "Csr.write to read-only address (0xC00) returns IllegalInstruction" {
    var csr = zicsr.Csr{};
    try std.testing.expectError(error.IllegalInstruction, csr.write(0xC00, 42));
}

test "Csr.read cycle counter returns low 32 bits" {
    const csr = zicsr.Csr{};
    const val = try csr.read(0x0000_0001_DEAD_BEEF, 0xC00);
    try std.testing.expectEqual(@as(u32, 0xDEAD_BEEF), val);
}

test "Csr.read cycleh returns high 32 bits" {
    const csr = zicsr.Csr{};
    const val = try csr.read(0x0000_0005_0000_0000, 0xC80);
    try std.testing.expectEqual(@as(u32, 5), val);
}

test "Csr.read unknown address returns IllegalInstruction" {
    const csr = zicsr.Csr{};
    try std.testing.expectError(error.IllegalInstruction, csr.read(0, 0x001));
}

test "Csr.write and read mscratch round-trip" {
    var csr = zicsr.Csr{};
    try csr.write(0x340, 0xCAFE);
    const val = try csr.read(0, 0x340);
    try std.testing.expectEqual(@as(u32, 0xCAFE), val);
}
