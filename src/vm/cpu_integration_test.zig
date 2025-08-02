const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = Cpu.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

// --- CPU integration tests for stores, LUI, AUIPC, atomics, CSR ---

test "step: SB stores byte" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 200); // base address
    cpu.writeReg(2, 0xDEADBEAB); // only low byte 0xAB stored
    // SB x2, 0(x1): funct3=000
    h6.loadInst(&cpu, h6.encodeS(0b000, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u8, 0xAB), cpu.memory[200]);
    // Adjacent bytes untouched
    try std.testing.expectEqual(@as(u8, 0), cpu.memory[201]);
}

test "step: SH stores halfword" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 200); // base address (aligned)
    cpu.writeReg(2, 0xDEAD1234); // only low halfword 0x1234 stored
    // SH x2, 0(x1): funct3=001
    h6.loadInst(&cpu, h6.encodeS(0b001, 1, 2, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u16, 0x1234), std.mem.readInt(u16, cpu.memory[200..][0..2], .little));
    // Adjacent bytes untouched
    try std.testing.expectEqual(@as(u8, 0), cpu.memory[202]);
}

test "step: LUI loads upper immediate" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // LUI x3, 0xABCDE → x3 = 0xABCDE000
    h6.loadInst(&cpu, h6.encodeU(0b0110111, 3, 0xABCDE));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xABCDE000), cpu.readReg(3));
}

test "step: AUIPC at non-zero PC" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.pc = 0x100;
    // AUIPC x3, 0x00002 → x3 = PC + (0x00002 << 12) = 0x100 + 0x2000 = 0x2100
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], h6.encodeU(0b0010111, 3, 0x00002), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x2100), cpu.readReg(3));
}

test "step: LR.W + SC.W success" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // Store a value at address 256
    h6.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256); // address register
    cpu.writeReg(2, 0x99); // value to store conditionally

    // LR.W x3, (x1): funct5=00010, rd=3, rs1=1, rs2=0
    h6.loadInst(&cpu, h6.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(3));

    // SC.W x4, x2, (x1): funct5=00011, rd=4, rs1=1, rs2=2
    h6.loadInst(&cpu, h6.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(4)); // success = 0
    try std.testing.expectEqual(@as(u32, 0x99), try cpu.readWord(256));
}

test "step: LR.W + SC.W failure (different address)" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 0x42);
    h6.storeWordAt(&cpu, 260, 0x00);
    cpu.writeReg(1, 256); // LR address
    cpu.writeReg(5, 260); // SC address (different)
    cpu.writeReg(2, 0x99);

    // LR.W x3, (x1)
    h6.loadInst(&cpu, h6.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x5) — different address → failure
    h6.loadInst(&cpu, h6.encodeAtomic(0b00011, 4, 5, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure = 1
    try std.testing.expectEqual(@as(u32, 0x00), try cpu.readWord(260)); // memory unchanged
}

test "step: LR.W + SW invalidates + SC.W fails" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);
    cpu.writeReg(6, 0xBB); // value for intervening store

    // LR.W x3, (x1)
    h6.loadInst(&cpu, h6.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SW x6, 0(x1) — intervening store to same address invalidates reservation
    h6.loadInst(&cpu, h6.encodeS(0b010, 1, 6, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x1) — should fail (reservation invalidated)
    h6.loadInst(&cpu, h6.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0xBB), try cpu.readWord(256)); // SW value
}

test "step: SC.W without prior LR.W fails" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0x99);

    // SC.W x4, x2, (x1) — no prior LR.W
    h6.loadInst(&cpu, h6.encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0x42), try cpu.readWord(256)); // unchanged
}

test "step: AMOSWAP.W swaps memory and register" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 0xAAAA);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xBBBB);

    // AMOSWAP.W x3, x2, (x1): funct5=00001
    h6.loadInst(&cpu, h6.encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 0xBBBB), try cpu.readWord(256)); // new value
}

test "step: AMOADD.W atomic add" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 100);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 50);

    // AMOADD.W x3, x2, (x1): funct5=00000
    h6.loadInst(&cpu, h6.encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 100), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 150), try cpu.readWord(256)); // 100 + 50
}

test "step: CSRRW write and read back" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();

    // CSRRW x0, 0x340, x1 — write x1 to mscratch (rd=0, no read)
    cpu.writeReg(1, 0xDEAD);
    h6.loadInst(&cpu, h6.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();

    // CSRRS x3, 0x340, x0 — read mscratch into x3 (rs1=0, no write)
    h6.loadInst(&cpu, h6.encodeCsr(0b010, 3, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEAD), cpu.readReg(3));
}

test "step: CSRRC clears bits" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();

    // Write 0xFF to mscratch
    cpu.writeReg(1, 0xFF);
    h6.loadInst(&cpu, h6.encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();

    // CSRRC x3, 0x340, x2 — clear bits from x2 in mscratch
    cpu.writeReg(2, 0x0F);
    h6.loadInst(&cpu, h6.encodeCsr(0b011, 3, 2, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(3)); // old value

    // Read back: should be 0xFF & ~0x0F = 0xF0
    h6.loadInst(&cpu, h6.encodeCsr(0b010, 4, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.readReg(4));
}

test "step: CSRRWI and CSRRSI immediate variants" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();

    // CSRRWI x0, 0x340, zimm=5 — write 5 to mscratch (rs1 field=5 used as zimm)
    h6.loadInst(&cpu, h6.encodeCsr(0b101, 0, 5, 0x340));
    _ = try cpu.step();

    // CSRRSI x3, 0x340, zimm=0x10 — read mscratch, set bit 4
    h6.loadInst(&cpu, h6.encodeCsr(0b110, 3, 0x10, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3)); // old value = 5

    // Read back: 5 | 0x10 = 0x15
    h6.loadInst(&cpu, h6.encodeCsr(0b010, 4, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x15), cpu.readReg(4));
}

test "step: write to read-only CSR (cycle counter) returns error" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);

    // CSRRW x0, 0xC00, x1 — attempt to write cycle counter (read-only)
    h6.loadInst(&cpu, h6.encodeCsr(0b001, 0, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "run(0) terminates on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}
