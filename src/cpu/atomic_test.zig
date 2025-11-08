const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

// --- Atomic operation tests (LR/SC, AMO) ---

test "step: LR.W + SC.W success" {
    var cpu = Cpu.init();
    // Store a value at address 256
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256); // address register
    cpu.writeReg(2, 0x99); // value to store conditionally

    // LR.W x3, (x1): funct5=00010, rd=3, rs1=1, rs2=0
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(3));

    // SC.W x4, x2, (x1): funct5=00011, rd=4, rs1=1, rs2=2
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(4)); // success = 0
    try std.testing.expectEqual(@as(u32, 0x99), try cpu.readWord(256));
}

test "step: LR.W + SC.W failure (different address)" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    h.storeWordAt(&cpu, 260, 0x00);
    cpu.writeReg(1, 256); // LR address
    cpu.writeReg(5, 260); // SC address (different)
    cpu.writeReg(2, 0x99);

    // LR.W x3, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x5) — different address → failure
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 5, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure = 1
    try std.testing.expectEqual(@as(u32, 0x00), try cpu.readWord(260)); // memory unchanged
}

test "step: LR.W + SW invalidates + SC.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    cpu.writeReg(6, 0xBB); // value for intervening store

    // LR.W x3, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SW x6, 0(x1) — intervening store to same address invalidates reservation
    h.loadInst(&cpu, h.encodeS(0b010, 1, 6, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x1) — should fail (reservation invalidated)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0xBB), try cpu.readWord(256)); // SW value
}

test "step: SC.W without prior LR.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);

    // SC.W x4, x2, (x1) — no prior LR.W
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0x42), try cpu.readWord(256)); // unchanged
}

test "step: AMOSWAP.W swaps memory and register" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0xAAAA);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xBBBB);

    // AMOSWAP.W x3, x2, (x1): funct5=00001
    h.loadInst(&cpu, h.encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0xBBBB), try cpu.readWord(256)); // new value
}

test "step: AMOADD.W atomic add" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 100);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 50);

    // AMOADD.W x3, x2, (x1): funct5=00000
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 100), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 150), try cpu.readWord(256)); // 100 + 50
}

test "step: AMOMIN.W picks signed minimum" {
    var cpu = Cpu.init();
    // mem[256] = -1 (0xFFFFFFFF), rs2 = 1
    h.storeWordAt(&cpu, 256, 0xFFFFFFFF);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 1);

    // AMOMIN.W x3, x2, (x1): funct5=10000
    h.loadInst(&cpu, h.encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // old value
    // signed min(-1, 1) = -1, so memory unchanged
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), try cpu.readWord(256));
}

test "step: AMOMAXU.W picks unsigned maximum" {
    var cpu = Cpu.init();
    // mem[256] = 5, rs2 = 0xFFFFFFFF
    h.storeWordAt(&cpu, 256, 5);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xFFFFFFFF);

    // AMOMAXU.W x3, x2, (x1): funct5=11100
    h.loadInst(&cpu, h.encodeAtomic(0b11100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3)); // old value
    // unsigned max(5, 0xFFFFFFFF) = 0xFFFFFFFF
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), try cpu.readWord(256));
}

test "step: LR.W + SB invalidates reservation + SC.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256); // address for LR/SC
    cpu.writeReg(2, 0x99); // SC value
    cpu.writeReg(3, 0xAA); // SB value

    // LR.W x4, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 4, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(4));

    // SB x3, 0(x1) — sub-word store to same word-aligned address
    h.loadInst(&cpu, h.encodeS(0b000, 1, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail (SB invalidated reservation)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(5)); // failure
}

test "step: LR.W + SH invalidates reservation + SC.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    cpu.writeReg(3, 0xBEEF);

    // LR.W x4, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 4, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(4));

    // SH x3, 0(x1) — halfword store to same word-aligned address
    h.loadInst(&cpu, h.encodeS(0b001, 1, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(5));
}

test "step: failed SC.W clears reservation" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    h.storeWordAt(&cpu, 260, 0x00);
    cpu.writeReg(1, 256);
    cpu.writeReg(5, 260);
    cpu.writeReg(2, 0x99);

    // LR.W x3, (x1) — reserve address 256
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x5) — different address → fails
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 5, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4));

    // SC.W x6, x2, (x1) — original address, but reservation was cleared
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 6, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(6));
    try std.testing.expectEqual(@as(u32, 0x42), try cpu.readWord(256)); // unchanged
}

test "step: AMO invalidates reservation + SC.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 100);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    cpu.writeReg(3, 50);

    // LR.W x4, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 4, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 100), cpu.readReg(4));

    // AMOADD.W x5, x3, (x1) — atomic add, also writes to same word
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 5, 1, 3));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 150), try cpu.readWord(256));

    // SC.W x6, x2, (x1) — should fail (AMO invalidated reservation)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 6, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(6));
    try std.testing.expectEqual(@as(u32, 150), try cpu.readWord(256)); // AMO value preserved
}

test "step: SB to byte within reserved word invalidates reservation" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    cpu.writeReg(7, 258); // byte 2 of the same word
    cpu.writeReg(3, 0xFF);

    // LR.W x4, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 4, 1, 0));
    _ = try cpu.step();

    // SB x3, 0(x7) — store byte at address 258, same word as 256
    h.loadInst(&cpu, h.encodeS(0b000, 7, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(5));
}

// --- Atomic bad-address tests ---

const MEMORY_SIZE = Cpu.mem_size;

test "step: LR.W out of bounds" {
    var cpu = Cpu.init();
    cpu.writeReg(1, MEMORY_SIZE); // address = MEMORY_SIZE (one past end)

    // LR.W x3, (x1): funct5=00010
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
}

test "step: LR.W misaligned leaves reservation unchanged" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x101); // misaligned for word access

    // LR.W x3, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
    // Reservation must remain null after the error
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "step: AMOADD.W misaligned address" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x103); // misaligned
    cpu.writeReg(2, 50);

    // AMOADD.W x3, x2, (x1): funct5=00000
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 3, 1, 2));
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
}

test "step: AMOSWAP.W out of bounds" {
    var cpu = Cpu.init();
    cpu.writeReg(1, MEMORY_SIZE); // out of bounds
    cpu.writeReg(2, 0xBBBB);

    // AMOSWAP.W x3, x2, (x1): funct5=00001
    h.loadInst(&cpu, h.encodeAtomic(0b00001, 3, 1, 2));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
}

test "step: SC.W to misaligned address fails without error" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 0x42);
    cpu.writeReg(1, 0x100); // aligned address for LR
    cpu.writeReg(2, 0x99); // value to store

    // LR.W x3, (x1) — reserve address 0x100
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // Change rs1 to misaligned address for SC
    cpu.writeReg(1, 0x103);

    // SC.W x4, x2, (x1) — reservation(0x100) != 0x103, so fails with rd=1 (no memory error)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    // Reservation cleared after SC (even on failure)
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "step: SC.W to out-of-bounds address fails without error" {
    var cpu = Cpu.init();
    cpu.writeReg(1, MEMORY_SIZE); // out of bounds, no prior LR.W (reservation=null)
    cpu.writeReg(2, 0x99);

    // SC.W x4, x2, (x1) — reservation is null != MEMORY_SIZE, so fails with rd=1
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}
