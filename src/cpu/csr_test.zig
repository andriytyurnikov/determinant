const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

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

test "step: chained read-modify-write with three register variants" {
    var cpu = Cpu.init();

    // Step 1: CSRRW x1, mscratch, x2 — write 0xFFFFFFFF to mscratch, old value (0) into x1
    cpu.writeReg(2, 0xFFFFFFFF);
    h.loadInst(&cpu, h.encodeCsr(0b001, 1, 2, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(1)); // old value was 0
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.csrs.mscratch);

    // Step 2: CSRRC x3, mscratch, x4 — clear low 8 bits, old value into x3
    cpu.writeReg(4, 0xFF);
    h.loadInst(&cpu, h.encodeCsr(0b011, 3, 4, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0xFFFFFF00), cpu.csrs.mscratch);

    // Step 3: CSRRS x5, mscratch, x6 — set bit 31 (already set, noop), old value into x5
    cpu.writeReg(6, 0x80000000);
    h.loadInst(&cpu, h.encodeCsr(0b010, 5, 6, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF00), cpu.readReg(5)); // old value
    try std.testing.expectEqual(@as(u32, 0xFFFFFF00), cpu.csrs.mscratch); // unchanged

    // Step 4: CSRRW x7, mscratch, x8 — swap to 0x12345678, old value into x7
    cpu.writeReg(8, 0x12345678);
    h.loadInst(&cpu, h.encodeCsr(0b001, 7, 8, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF00), cpu.readReg(7)); // old value
    try std.testing.expectEqual(@as(u32, 0x12345678), cpu.csrs.mscratch);
}

test "step: CSR read value used as operand for next CSR operation" {
    var cpu = Cpu.init();

    // Step 1: CSRRW x0, mscratch, x1 — write 0xFF00FF00 to mscratch
    cpu.writeReg(1, 0xFF00FF00);
    h.loadInst(&cpu, h.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.csrs.mscratch);

    // Step 2: CSRRS x2, mscratch, x0 — read mscratch into x2 (rs1=x0, no set)
    h.loadInst(&cpu, h.encodeCsr(0b010, 2, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(2));

    // Step 3: CSRRC x3, mscratch, x2 — clear mscratch bits using x2 as mask
    // x2 = 0xFF00FF00, so mscratch & ~0xFF00FF00 = 0xFF00FF00 & 0x00FF00FF = 0x00FF00FF... wait
    // mscratch = 0xFF00FF00, clearing bits 0xFF00FF00 → 0xFF00FF00 & ~0xFF00FF00 = 0
    h.loadInst(&cpu, h.encodeCsr(0b011, 3, 2, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0), cpu.csrs.mscratch); // all set bits cleared
}

test "step: alternating immediate and register CSR variants" {
    var cpu = Cpu.init();

    // Step 1: CSRRWI x0, mscratch, zimm=31 — write 0x1F (31) to mscratch
    h.loadInst(&cpu, h.encodeCsr(0b101, 0, 31, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1F), cpu.csrs.mscratch);

    // Step 2: CSRRS x0, mscratch, x1 — set bits from x1=0xF0
    cpu.writeReg(1, 0xF0);
    h.loadInst(&cpu, h.encodeCsr(0b010, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.csrs.mscratch); // 0x1F | 0xF0 = 0xFF

    // Step 3: CSRRCI x0, mscratch, zimm=15 — clear low 4 bits (mask=0x0F)
    h.loadInst(&cpu, h.encodeCsr(0b111, 0, 15, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.csrs.mscratch); // 0xFF & ~0x0F = 0xF0

    // Step 4: CSRRSI x0, mscratch, zimm=8 — set bit 3
    h.loadInst(&cpu, h.encodeCsr(0b110, 0, 8, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF8), cpu.csrs.mscratch); // 0xF0 | 0x08 = 0xF8
}

test "step: consecutive cycle counter reads increment by one" {
    var cpu = Cpu.init();
    cpu.cycle_count = 1000;

    // Step 1: CSRRS x1, cycle, x0 — read cycle counter into x1 (rs1=x0, no set)
    h.loadInst(&cpu, h.encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1000), cpu.readReg(1)); // pre-step value

    // Step 2: CSRRS x2, cycle, x0 — read cycle counter into x2
    h.loadInst(&cpu, h.encodeCsr(0b010, 2, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1001), cpu.readReg(2)); // incremented by step 1

    // Step 3: CSRRS x3, cycle, x0 — read cycle counter into x3
    h.loadInst(&cpu, h.encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1002), cpu.readReg(3)); // incremented by step 2
}

test "step: set all bits then clear all bits round-trip" {
    var cpu = Cpu.init();

    // Step 1: CSRRW x0, mscratch, x1 — write 0 to mscratch
    cpu.writeReg(1, 0);
    h.loadInst(&cpu, h.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.csrs.mscratch);

    // Step 2: CSRRS x2, mscratch, x3 — set all bits (x3=0xFFFFFFFF), old value into x2
    cpu.writeReg(3, 0xFFFFFFFF);
    h.loadInst(&cpu, h.encodeCsr(0b010, 2, 3, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(2)); // old value was 0
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.csrs.mscratch);

    // Step 3: CSRRC x4, mscratch, x5 — clear all bits (x5=0xFFFFFFFF), old value into x4
    cpu.writeReg(5, 0xFFFFFFFF);
    h.loadInst(&cpu, h.encodeCsr(0b011, 4, 5, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(4)); // old value
    try std.testing.expectEqual(@as(u32, 0), cpu.csrs.mscratch);

    // Step 4: CSRRSI x6, mscratch, zimm=31 — set low 5 bits, old value into x6
    h.loadInst(&cpu, h.encodeCsr(0b110, 6, 31, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(6)); // old value was 0
    try std.testing.expectEqual(@as(u32, 0x1F), cpu.csrs.mscratch);
}
