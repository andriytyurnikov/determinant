const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("instructions/test_helpers.zig");

// --- CSR instruction tests at CPU level ---

test "step: CSRRW write and read back" {
    var cpu = Cpu.init();

    // CSRRW x0, 0x340, x1 — write x1 to mscratch (rd=0, no read)
    cpu.writeReg(1, 0xDEAD);
    h.loadInst(&cpu, h.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();

    // CSRRS x3, 0x340, x0 — read mscratch into x3 (rs1=0, no write)
    h.loadInst(&cpu, h.encodeCsr(0b010, 3, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEAD), cpu.readReg(3));
}

test "step: CSRRC clears bits" {
    var cpu = Cpu.init();

    // Write 0xFF to mscratch
    cpu.writeReg(1, 0xFF);
    h.loadInst(&cpu, h.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();

    // CSRRC x3, 0x340, x2 — clear bits from x2 in mscratch
    cpu.writeReg(2, 0x0F);
    h.loadInst(&cpu, h.encodeCsr(0b011, 3, 2, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(3)); // old value

    // Read back: should be 0xFF & ~0x0F = 0xF0
    h.loadInst(&cpu, h.encodeCsr(0b010, 4, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.readReg(4));
}

test "step: CSRRWI and CSRRSI immediate variants" {
    var cpu = Cpu.init();

    // CSRRWI x0, 0x340, zimm=5 — write 5 to mscratch (rs1 field=5 used as zimm)
    h.loadInst(&cpu, h.encodeCsr(0b101, 0, 5, 0x340));
    _ = try cpu.step();

    // CSRRSI x3, 0x340, zimm=0x10 — read mscratch, set bit 4
    h.loadInst(&cpu, h.encodeCsr(0b110, 3, 0x10, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3)); // old value = 5

    // Read back: 5 | 0x10 = 0x15
    h.loadInst(&cpu, h.encodeCsr(0b010, 4, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x15), cpu.readReg(4));
}

test "step: write to read-only CSR (cycle counter) returns error" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);

    // CSRRW x0, 0xC00, x1 — attempt to write cycle counter (read-only)
    h.loadInst(&cpu, h.encodeCsr(0b001, 0, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}
