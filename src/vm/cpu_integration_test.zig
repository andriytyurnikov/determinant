const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = Cpu.mem_size;
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

test "step: AMOMIN.W picks signed minimum" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // mem[256] = -1 (0xFFFFFFFF), rs2 = 1
    h6.storeWordAt(&cpu, 256, 0xFFFFFFFF);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 1);

    // AMOMIN.W x3, x2, (x1): funct5=10000
    h6.loadInst(&cpu, h6.encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // old value
    // signed min(-1, 1) = -1, so memory unchanged
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), try cpu.readWord(256));
}

test "step: AMOMAXU.W picks unsigned maximum" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // mem[256] = 5, rs2 = 0xFFFFFFFF
    h6.storeWordAt(&cpu, 256, 5);
    cpu.writeReg(1, 256);
    cpu.writeReg(2, 0xFFFFFFFF);

    // AMOMAXU.W x3, x2, (x1): funct5=11100
    h6.loadInst(&cpu, h6.encodeAtomic(0b11100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3)); // old value
    // unsigned max(5, 0xFFFFFFFF) = 0xFFFFFFFF
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), try cpu.readWord(256));
}

test "step: compressed C.ADDI dispatches through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    // C.ADDI x1, 5 — encoding: [15:13]=000, [12]=0, [11:7]=00001, [6:2]=00101, [1:0]=01
    // imm[5]=bit12=0, imm[4:0]=bits[6:2]=00101 → imm=5
    const c_addi: u16 = 0b000_0_00001_00101_01;
    std.mem.writeInt(u16, cpu.memory[0..][0..2], c_addi, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 105), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc); // PC advances by 2
}

// --- Combined invariant tests ---

test "step: LB x0 with sign-extension — x0 stays zero" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // Store 0x80 at address 256 (high bit set → sign-extends to 0xFFFFFF80)
    cpu.memory[256] = 0x80;
    cpu.writeReg(1, 256); // base address
    // LB x0, 0(x1): opcode=0000011, funct3=000, rd=0, rs1=1, imm=0
    h6.loadInst(&cpu, h6.encodeI(0b0000011, 0b000, 0, 1, 0));
    _ = try cpu.step();
    // x0 must remain 0 despite sign-extension of loaded byte
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "step: LR.W + SB invalidates reservation + SC.W fails" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    h6.storeWordAt(&cpu, 256, 0x42);
    cpu.writeReg(1, 256); // address for LR/SC
    cpu.writeReg(2, 0x99); // SC value
    cpu.writeReg(3, 0xAA); // SB value

    // LR.W x4, (x1)
    h6.loadInst(&cpu, h6.encodeAtomic(0b00010, 4, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(4));

    // SB x3, 0(x1) — sub-word store to same word-aligned address
    h6.loadInst(&cpu, h6.encodeS(0b000, 1, 3, 0));
    _ = try cpu.step();

    // SC.W x5, x2, (x1) — should fail (SB invalidated reservation)
    h6.loadInst(&cpu, h6.encodeAtomic(0b00011, 5, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(5)); // failure
}

test "step: wrapping ADD then CSR read sees correct cycle count" {
    const h6 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    cpu.cycle_count = 10;

    // ADD x3, x1, x2 — wraps to 0
    h6.loadInst(&cpu, h6.encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3)); // wrapped result
    try std.testing.expectEqual(@as(u64, 11), cpu.cycle_count);

    // CSRRS x4, 0xC00, x0 — read cycle counter
    h6.loadInst(&cpu, h6.encodeCsr(0b010, 4, 0, 0xC00));
    _ = try cpu.step();
    // CSR read sees pre-step value (pipeline invariant): cycle_count was 11 before this step
    try std.testing.expectEqual(@as(u32, 11), cpu.readReg(4));
    try std.testing.expectEqual(@as(u64, 12), cpu.cycle_count);
}

test "step: C.NOP advances PC by 2 with no side effects" {
    var cpu = Cpu.init();
    // C.NOP = 0x0001 (quadrant 01, funct3=000, rd=0, imm=0)
    std.mem.writeInt(u16, cpu.memory[0..][0..2], 0x0001, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
    // All registers remain 0
    var i: u5 = 0;
    while (true) : (i +%= 1) {
        try std.testing.expectEqual(@as(u32, 0), cpu.readReg(i));
        if (i == 31) break;
    }
}

test "run(0) terminates on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}
