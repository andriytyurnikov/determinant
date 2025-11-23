const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

// --- Error recovery tests ---
// Verify that the CPU continues to function correctly after encountering an error.

test "step: valid step after decode error" {
    var cpu = Cpu.init();
    // NOP at addr 0
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    // Illegal instruction at addr 4: all zeros → C_ADDI4SPN with nzuimm=0
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000000, .little);
    // NOP at addr 4 (overwrite lower 4 bytes won't help — we need addr 4 to be illegal)
    // Actually, the illegal is 16-bit (0x0000), so PC will be at 4 after first NOP.
    // After the error, PC stays at 4. Place a recovery NOP at addr 4 as 32-bit.
    // But 0x0000 decodes as compressed illegal — we need to place the illegal and then
    // replace it with valid code after the error. Instead, structure the test differently:
    // Place NOP at 0, illegal at 4, recovery NOP at 6 (since 0x0000 is 16-bit compressed).
    // Wait — the error means step() returns error, PC is NOT advanced. So PC stays at 4.
    // We overwrite addr 4 with a valid NOP after the error.

    // Step 1: execute NOP at addr 0
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);

    // Step 2: attempt illegal instruction at addr 4 (0x0000 = illegal compressed)
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
    // PC and cycle_count unchanged after error
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);

    // Overwrite addr 4 with a valid NOP for recovery
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);

    // Step 3: recovery — execute NOP at addr 4
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: valid step after load error" {
    var cpu = Cpu.init();
    // ADDI x2, x0, 42 at addr 0
    h.loadInst(&cpu, h.encodeI(0b0010011, 0b000, 2, 0, 42));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);

    // LW x3, 0(x1) at addr 4 — x1=0 is valid, but let's use OOB address
    // Set x1 to an out-of-bounds address
    cpu.writeReg(1, Cpu.mem_size);
    // LW x3, 0(x1) at current PC
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 3, 1, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
    // PC and cycle_count unchanged; x2 preserved
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(2));

    // Recovery: ADDI x3, x0, 99 at addr 4
    h.loadInst(&cpu, h.encodeI(0b0010011, 0b000, 3, 0, 99));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 99), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(2)); // preserved
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: valid step after store error" {
    var cpu = Cpu.init();
    // Set up OOB store: x1 = OOB address, x2 = value
    cpu.writeReg(1, Cpu.mem_size);
    cpu.writeReg(2, 0xDEAD);
    // SW x2, 0(x1) at addr 0 — OOB store
    h.loadInst(&cpu, h.encodeS(0b010, 1, 2, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
    try std.testing.expectEqual(@as(u64, 0), cpu.cycle_count);

    // Recovery: valid store — set x1 to valid address
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xCAFE);
    h.loadInst(&cpu, h.encodeS(0b010, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xCAFE), try cpu.readWord(256));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "step: reservation preserved across error" {
    var cpu = Cpu.init();
    // Store value at address 256 for LR.W
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);

    // LR.W x3, (x1) — sets reservation
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(3));
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);

    // Trigger OOB load error: set x4 to OOB address
    cpu.writeReg(4, Cpu.mem_size);
    // LW x5, 0(x4) — OOB
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 5, 4, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());

    // Reservation must still be set after the error
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);

    // SC.W x6, x2, (x1) — should succeed (reservation intact)
    cpu.writeReg(2, 0x99);
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 6, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(6)); // success = 0
    try std.testing.expectEqual(@as(u32, 0x99), try cpu.readWord(256));
}
