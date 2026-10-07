const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
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
    try std.testing.expectEqual(0x42, cpu.readReg(3));

    // SC.W x4, x2, (x1): funct5=00011, rd=4, rs1=1, rs2=2
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(0, cpu.readReg(4)); // success = 0
    try std.testing.expectEqual(0x99, try cpu.readWord(256));
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
    try std.testing.expectEqual(1, cpu.readReg(4)); // failure = 1
    try std.testing.expectEqual(0x00, try cpu.readWord(260)); // memory unchanged
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
    try std.testing.expectEqual(1, cpu.readReg(4)); // failure
    try std.testing.expectEqual(0xBB, try cpu.readWord(256)); // SW value
}

test "step: SC.W without prior LR.W fails" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);

    // SC.W x4, x2, (x1) — no prior LR.W
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(4)); // failure
    try std.testing.expectEqual(0x42, try cpu.readWord(256)); // unchanged
}

test "step: AMOSWAP.W swaps memory and register" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0xAAAA);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xBBBB);

    // AMOSWAP.W x3, x2, (x1): funct5=00001
    h.loadInst(&cpu, h.encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(0xAAAA, cpu.readReg(3)); // old value
    try std.testing.expectEqual(0xBBBB, try cpu.readWord(256)); // new value
}

test "step: AMOADD.W atomic add" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 100);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 50);

    // AMOADD.W x3, x2, (x1): funct5=00000
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(100, cpu.readReg(3)); // old value
    try std.testing.expectEqual(150, try cpu.readWord(256)); // 100 + 50
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
    try std.testing.expectEqual(0xFFFFFFFF, cpu.readReg(3)); // old value
    // signed min(-1, 1) = -1, so memory unchanged
    try std.testing.expectEqual(0xFFFFFFFF, try cpu.readWord(256));
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
    try std.testing.expectEqual(5, cpu.readReg(3)); // old value
    // unsigned max(5, 0xFFFFFFFF) = 0xFFFFFFFF
    try std.testing.expectEqual(0xFFFFFFFF, try cpu.readWord(256));
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
    try std.testing.expectEqual(0x42, cpu.readReg(4));

    // SB x3, 0(x1) — sub-word store to same word-aligned address
    h.loadInst(&cpu, h.encodeS(0b000, 1, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail (SB invalidated reservation)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(5)); // failure
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
    try std.testing.expectEqual(0x42, cpu.readReg(4));

    // SH x3, 0(x1) — halfword store to same word-aligned address
    h.loadInst(&cpu, h.encodeS(0b001, 1, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(5));
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
    try std.testing.expectEqual(1, cpu.readReg(4));

    // SC.W x6, x2, (x1) — original address, but reservation was cleared
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 6, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(6));
    try std.testing.expectEqual(0x42, try cpu.readWord(256)); // unchanged
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
    try std.testing.expectEqual(100, cpu.readReg(4));

    // AMOADD.W x5, x3, (x1) — atomic add, also writes to same word
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 5, 1, 3));
    _ = try cpu.step();
    try std.testing.expectEqual(150, try cpu.readWord(256));

    // SC.W x6, x2, (x1) — should fail (AMO invalidated reservation)
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 6, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(6));
    try std.testing.expectEqual(150, try cpu.readWord(256)); // AMO value preserved
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
    try std.testing.expectEqual(1, cpu.readReg(5));
}

// --- Atomic bad-address tests ---

const MEMORY_SIZE = Cpu.mem_size;

test "step: table (atomic)" {
    try h.expectSteps(&.{
        // LR.W x3, (x1): funct5=00010
        .{ .name = "LR.W out of bounds", .inst = h.encodeAtomic(0b00010, 3, 1, 0), .regs = &.{.{ 1, MEMORY_SIZE }}, .err = error.AddressOutOfBounds },
        // LR.W x3, (x1)
        .{ .name = "LR.W misaligned leaves reservation unchanged", .inst = h.encodeAtomic(0b00010, 3, 1, 0), .regs = &.{.{ 1, 0x101 }}, .reservation = 0x200, .err = error.MisalignedAccess, .check_reservation = true, .want_reservation = 0x200 },
        // AMOADD.W x3, x2, (x1): funct5=00000
        .{ .name = "AMOADD.W misaligned address", .inst = h.encodeAtomic(0b00000, 3, 1, 2), .regs = &.{ .{ 1, 0x103 }, .{ 2, 50 } }, .err = error.MisalignedAccess },
        // AMOSWAP.W x3, x2, (x1): funct5=00001
        .{ .name = "AMOSWAP.W out of bounds", .inst = h.encodeAtomic(0b00001, 3, 1, 2), .regs = &.{ .{ 1, MEMORY_SIZE }, .{ 2, 0xBBBB } }, .err = error.AddressOutOfBounds },
        // SC.W x4, x2, (x1)
        .{ .name = "out-of-bounds SC.W faults without a reservation", .inst = h.encodeAtomic(0b00011, 4, 1, 2), .regs = &.{ .{ 1, MEMORY_SIZE }, .{ 2, 0x99 }, .{ 4, 0x5555 } }, .err = error.AddressOutOfBounds, .want = &.{.{ 4, 0x5555 }}, .want_pc = 0, .check_reservation = true, .want_reservation = null },
    });
}

test "step: misaligned SC.W faults and keeps an existing reservation" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0x100, 0x42);
    cpu.writeReg(1, 0x100); // aligned address for LR
    cpu.writeReg(2, 0x99); // value to store
    cpu.writeReg(4, 0x5555); // rd sentinel

    // LR.W x3, (x1) — reserve address 0x100
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x1) at 0x103 — must fault before looking at the reservation
    cpu.writeReg(1, 0x103);
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    const pc = cpu.pc;
    const cycles = cpu.cycle_count;
    try std.testing.expectError(error.MisalignedAccess, cpu.step());

    try std.testing.expectEqual(@as(?u32, 0x100), cpu.reservation); // unchanged
    try std.testing.expectEqual(0x5555, cpu.readReg(4)); // rd not written
    try std.testing.expectEqual(0x42, h.readWordAt(&cpu, 0x100)); // memory untouched
    try std.testing.expectEqual(pc, cpu.pc); // did not retire
    try std.testing.expectEqual(cycles, cpu.cycle_count);
}

test "step: out-of-bounds SC.W faults and keeps a reservation elsewhere" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x100);
    // LR.W x3, (x1) — reserve address 0x100
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x5) with x5 one word past the end of memory
    cpu.writeReg(5, MEMORY_SIZE);
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 5, 2));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
    try std.testing.expectEqual(@as(?u32, 0x100), cpu.reservation);
}

test "step: SC.W to the last word of memory succeeds" {
    var cpu = Cpu.init();
    const last = MEMORY_SIZE - 4;
    cpu.writeReg(1, last);
    cpu.writeReg(2, 0xCAFE);
    // LR.W x3, (x1); SC.W x4, x2, (x1)
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(0, cpu.readReg(4)); // success
    try std.testing.expectEqual(0xCAFE, try cpu.readWord(last));
}

test "reservation: only writes overlapping the reserved word invalidate it" {
    var cpu = Cpu.init();
    cpu.reservation = 256;
    try cpu.writeWord(252, 1); // previous word
    try cpu.writeHalfword(260, 1); // next word
    try cpu.writeByte(255, 1); // last byte of the previous word
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);
    try cpu.writeByte(259, 1); // last byte of the reserved word
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "step: LR.W, SW to another word, SC.W still succeeds" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256); // reserved address
    cpu.writeReg(5, 260); // neighbouring word
    cpu.writeReg(2, 0x99);
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    _ = try cpu.step();
    h.loadInst(&cpu, h.encodeS(0b010, 5, 2, 0)); // SW x2, 0(x5)
    _ = try cpu.step();
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2)); // SC.W x4, x2, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(0, cpu.readReg(4)); // success
    try std.testing.expectEqual(0x99, try cpu.readWord(256));
}

// --- Host writes and the reservation ---

test "loadProgram over the reserved word makes SC.W fail" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);

    try cpu.loadProgram(&.{ 0x11, 0x22, 0x33, 0x44 }, 256);
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);

    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2)); // SC.W x4, x2, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(1, cpu.readReg(4)); // failure
    try std.testing.expectEqual(0x44332211, try cpu.readWord(256)); // host bytes kept
}

test "loadProgram elsewhere keeps the reservation; SC.W succeeds" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    _ = try cpu.step();

    try cpu.loadProgram(&.{ 0x11, 0x22, 0x33, 0x44 }, 512);
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);

    h.loadInst(&cpu, h.encodeAtomic(0b00011, 4, 1, 2)); // SC.W x4, x2, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(0, cpu.readReg(4)); // success
    try std.testing.expectEqual(0x99, try cpu.readWord(256));
}

test "loadProgram: overlap with the reserved word is byte-exact" {
    var cpu = Cpu.init();
    // Ends just before the reserved word (252..255): kept
    cpu.reservation = 256;
    try cpu.loadProgram(&.{ 1, 2, 3, 4 }, 252);
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);
    // Starts just after it (260..263): kept
    try cpu.loadProgram(&.{ 1, 2, 3, 4 }, 260);
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);
    // Empty program at the reserved address writes nothing: kept
    try cpu.loadProgram(&.{}, 256);
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);
    // Covers only the first byte (253..256): cleared
    try cpu.loadProgram(&.{ 1, 2, 3, 4 }, 253);
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
    // Covers only the last byte (259..262): cleared
    cpu.reservation = 256;
    try cpu.loadProgram(&.{ 1, 2, 3, 4 }, 259);
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
    // A failed (out-of-bounds) load writes nothing: kept
    cpu.reservation = 256;
    try std.testing.expectError(error.AddressOutOfBounds, cpu.loadProgram(&.{ 1, 2 }, MEMORY_SIZE - 1));
    try std.testing.expectEqual(@as(?u32, 256), cpu.reservation);
}

test "clearReservation drops the reservation" {
    var cpu = Cpu.init();
    cpu.reservation = 256;
    cpu.memory[256] = 0xFF; // a direct host write...
    cpu.clearReservation(); // ...must be followed by this
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}
