const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = cpu_mod.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

// --- Helper to load a single instruction ---

fn loadInst(cpu: *Cpu, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[cpu.pc..][0..4], word, .little);
}

test "init zeroes everything" {
    const cpu = Cpu.init();
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
    for (cpu.regs) |r| {
        try std.testing.expectEqual(@as(u32, 0), r);
    }
}

test "x0 hardwired to zero" {
    var cpu = Cpu.init();
    cpu.writeReg(0, 12345);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "register read/write" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(1));
    cpu.writeReg(31, 42);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(31));
}

test "fetch from memory" {
    var cpu = Cpu.init();
    // Write a little-endian u32 at address 0
    std.mem.writeInt(u32, cpu.memory[0..4], 0x12345678, .little);
    const inst = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x12345678), inst);
}

test "fetch misaligned PC" {
    var cpu = Cpu.init();
    cpu.pc = 2;
    try std.testing.expectError(error.MisalignedPC, cpu.fetch());
}

test "fetch PC out of bounds" {
    var cpu = Cpu.init();
    cpu.pc = MEMORY_SIZE;
    try std.testing.expectError(error.PCOutOfBounds, cpu.fetch());
}

test "loadProgram" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0x13, 0x00, 0x50, 0x00 }; // ADDI x0, x0, 5
    try cpu.loadProgram(&program, 0);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[0]);
    try std.testing.expectEqual(@as(u8, 0x00), cpu.memory[1]);
    try std.testing.expectEqual(@as(u8, 0x50), cpu.memory[2]);
    try std.testing.expectEqual(@as(u8, 0x00), cpu.memory[3]);
}

test "loadProgram at offset" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0xAA, 0xBB };
    try cpu.loadProgram(&program, 100);
    try std.testing.expectEqual(@as(u8, 0xAA), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0xBB), cpu.memory[101]);
}

test "loadProgram out of bounds" {
    var cpu = Cpu.init();
    const program = [_]u8{0xFF} ** 8;
    try std.testing.expectError(error.AddressOutOfBounds, cpu.loadProgram(&program, MEMORY_SIZE - 4));
}

// --- Memory helper tests ---

test "readByte / writeByte" {
    var cpu = Cpu.init();
    try cpu.writeByte(100, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), try cpu.readByte(100));
}

test "readHalfword / writeHalfword little-endian" {
    var cpu = Cpu.init();
    try cpu.writeHalfword(100, 0x1234);
    try std.testing.expectEqual(@as(u16, 0x1234), try cpu.readHalfword(100));
    // Verify little-endian byte order
    try std.testing.expectEqual(@as(u8, 0x34), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0x12), cpu.memory[101]);
}

test "readWord / writeWord little-endian" {
    var cpu = Cpu.init();
    try cpu.writeWord(100, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try cpu.readWord(100));
    try std.testing.expectEqual(@as(u8, 0xEF), cpu.memory[100]);
    try std.testing.expectEqual(@as(u8, 0xBE), cpu.memory[101]);
    try std.testing.expectEqual(@as(u8, 0xAD), cpu.memory[102]);
    try std.testing.expectEqual(@as(u8, 0xDE), cpu.memory[103]);
}

test "readHalfword misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.readHalfword(3));
}

test "writeHalfword misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.writeHalfword(5, 0));
}

test "readWord misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.readWord(2));
}

test "writeWord misaligned" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.MisalignedAccess, cpu.writeWord(1, 0));
}

test "readByte out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.readByte(MEMORY_SIZE));
}

test "writeWord out of bounds" {
    var cpu = Cpu.init();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.writeWord(MEMORY_SIZE, 0));
}

// --- Step / executor tests ---

test "step: ADDI" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42 = 0x02A00093
    loadInst(&cpu, 0x02A00093);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "step: ADDI negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    // ADDI x2, x1, -1 = 0xFFF08113
    loadInst(&cpu, 0xFFF08113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 99), cpu.readReg(2));
}

test "step: ADD" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 10);
    // ADD x3, x1, x2 = 0x002081B3
    loadInst(&cpu, 0x002081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 15), cpu.readReg(3));
}

test "step: SUB" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 7);
    // SUB x3, x1, x2 = 0x402081B3
    loadInst(&cpu, 0x402081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 13), cpu.readReg(3));
}

test "step: SUB wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 1);
    // SUB x3, x1, x2
    loadInst(&cpu, 0x402081B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: SLL" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 4);
    // SLL x3, x1, x2 = 0x002091B3
    loadInst(&cpu, 0x002091B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 16), cpu.readReg(3));
}

test "step: SLT signed" {
    var cpu = Cpu.init();
    // -1 (0xFFFFFFFF) < 1 signed
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // SLT x3, x1, x2 = 0x0020A1B3
    loadInst(&cpu, 0x0020A1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

test "step: SLTU unsigned" {
    var cpu = Cpu.init();
    // 0xFFFFFFFF > 1 unsigned
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // SLTU x3, x1, x2 = 0x0020B1B3
    loadInst(&cpu, 0x0020B1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: XOR" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    // XOR x3, x1, x2 = 0x0020C1B3
    loadInst(&cpu, 0x0020C1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF00FF00F), cpu.readReg(3));
}

test "step: SRL" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 4);
    // SRL x3, x1, x2 = 0x0020D1B3
    loadInst(&cpu, 0x0020D1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x08000000), cpu.readReg(3));
}

test "step: SRA" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // -2147483648
    cpu.writeReg(2, 4);
    // SRA x3, x1, x2 = 0x4020D1B3
    loadInst(&cpu, 0x4020D1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF8000000), cpu.readReg(3));
}

test "step: OR" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xF0F0F0F0);
    cpu.writeReg(2, 0x0F0F0F0F);
    // OR x3, x1, x2 = 0x0020E1B3
    loadInst(&cpu, 0x0020E1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: AND" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    // AND x3, x1, x2 = 0x0020F1B3
    loadInst(&cpu, 0x0020F1B3);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0F000F00), cpu.readReg(3));
}

test "step: SLTI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    // SLTI x2, x1, 10 = 0x00A0A113
    loadInst(&cpu, 0x00A0A113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: SLTIU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    // SLTIU x2, x1, 10 = 0x00A0B113
    loadInst(&cpu, 0x00A0B113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: XORI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    // XORI x2, x1, 0x0F = 0x00F0C113
    loadInst(&cpu, 0x00F0C113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.readReg(2));
}

test "step: ORI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xF0);
    // ORI x2, x1, 0x0F = 0x00F0E113
    loadInst(&cpu, 0x00F0E113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(2));
}

test "step: ANDI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    // ANDI x2, x1, 0x0F = 0x00F0F113
    loadInst(&cpu, 0x00F0F113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0F), cpu.readReg(2));
}

test "step: SLLI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    // SLLI x2, x1, 31 = 0x01F09113
    loadInst(&cpu, 0x01F09113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(2));
}

test "step: SRLI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    // SRLI x2, x1, 31 = 0x01F0D113
    loadInst(&cpu, 0x01F0D113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(2));
}

test "step: SRAI" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    // SRAI x2, x1, 31 = 0x41F0D113
    loadInst(&cpu, 0x41F0D113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(2));
}

test "step: shift by 0" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    // SLLI x2, x1, 0 = 0x00009113
    loadInst(&cpu, 0x00009113);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(2));
}

test "step: LW / SW" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100); // base address
    cpu.writeReg(2, 0xCAFEBABE);
    // SW x2, 0(x1) = 0x0020A023
    loadInst(&cpu, 0x0020A023);
    _ = try cpu.step();
    // LW x3, 0(x1) = 0x0000A183
    loadInst(&cpu, 0x0000A183);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), cpu.readReg(3));
}

test "step: LB sign-extends" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80; // -128 as i8
    cpu.writeReg(1, 200);
    // LB x2, 0(x1) = 0x00008103
    loadInst(&cpu, 0x00008103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(2));
}

test "step: LBU zero-extends" {
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LBU x2, 0(x1) = 0x0000C103
    loadInst(&cpu, 0x0000C103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80), cpu.readReg(2));
}

test "step: LH sign-extends" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..202], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1) = 0x00009103
    loadInst(&cpu, 0x00009103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(2));
}

test "step: LHU zero-extends" {
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..202], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LHU x2, 0(x1) = 0x0000D103
    loadInst(&cpu, 0x0000D103);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x8000), cpu.readReg(2));
}

test "step: SB stores low byte" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 300);
    cpu.writeReg(2, 0xDEADBE42);
    // SB x2, 0(x1) = 0x00208023
    loadInst(&cpu, 0x00208023);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u8, 0x42), cpu.memory[300]);
}

test "step: SH stores low halfword" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 300);
    cpu.writeReg(2, 0xDEAD1234);
    // SH x2, 0(x1) = 0x00209023
    loadInst(&cpu, 0x00209023);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u16, 0x1234), std.mem.readInt(u16, cpu.memory[300..302], .little));
}

test "step: BEQ taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BEQ not taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BEQ x1, x2, +8 = 0x00208463
    loadInst(&cpu, 0x00208463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: BNE taken" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 2);
    // BNE x1, x2, +8 = 0x00209463
    loadInst(&cpu, 0x00209463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLT signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF); // -1
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8 = 0x0020C463
    loadInst(&cpu, 0x0020C463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGE signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF); // -1
    // BGE x1, x2, +8 = 0x0020D463
    loadInst(&cpu, 0x0020D463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BLTU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    cpu.writeReg(2, 0xFFFFFFFF);
    // BLTU x1, x2, +8 = 0x0020E463
    loadInst(&cpu, 0x0020E463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: BGEU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    // BGEU x1, x2, +8 = 0x0020F463
    loadInst(&cpu, 0x0020F463);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: LUI" {
    var cpu = Cpu.init();
    // LUI x1, 0xDEAD = 0xDEAD0093 ... actually LUI x1, 0xDEADB = 0xDEADB0B7
    // LUI x1, 0x12345 = 0x123450B7
    loadInst(&cpu, 0x123450B7);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x12345000), cpu.readReg(1));
}

test "step: AUIPC" {
    var cpu = Cpu.init();
    cpu.pc = 0x1000;
    // AUIPC x1, 0x2 = 0x00002097
    std.mem.writeInt(u32, cpu.memory[0x1000..][0..4], 0x00002097, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1000 + 0x2000), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 0x1004), cpu.pc);
}

test "step: JAL" {
    var cpu = Cpu.init();
    cpu.pc = 0x100;
    // JAL x1, +8 = encode JAL: imm=8, rd=1
    // JAL encoding: imm[20|10:1|11|19:12] | rd | 1101111
    // imm=8 → bits: 0_0000000100_0_00000000
    // [20]=0, [10:1]=0000000100, [11]=0, [19:12]=00000000
    // raw = 0_0000000100_0_00000000 | 00001 | 1101111
    // = (0b0000000100 << 21) | (0 << 20) | (0b00000000 << 12) | (1 << 7) | 0b1101111
    const jal_word: u32 = (0b0000000100 << 21) | (0b00001 << 7) | 0b1101111;
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], jal_word, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x104), cpu.readReg(1)); // return address
    try std.testing.expectEqual(@as(u32, 0x108), cpu.pc); // jumped to pc+8
}

test "step: JALR clears LSB" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x103); // odd address
    // JALR x2, x1, 0 = 0x000080E7 — but let me encode: JALR x2, 0(x1)
    // opcode=1100111, funct3=000, rd=2, rs1=1, imm=0
    // = (0 << 20) | (1 << 15) | (0b000 << 12) | (2 << 7) | 0b1100111
    const jalr_word: u32 = (0b00001 << 15) | (0b00010 << 7) | 0b1100111;
    loadInst(&cpu, jalr_word);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // return address = pc + 4
    try std.testing.expectEqual(@as(u32, 0x102), cpu.pc); // (0x103 + 0) & ~1
}

test "step: JALR rd == rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x200);
    // JALR x1, x1, 4 — rd=rs1=x1
    // = (4 << 20) | (1 << 15) | (0b000 << 12) | (1 << 7) | 0b1100111
    const jalr_word: u32 = (4 << 20) | (0b00001 << 15) | (0b00001 << 7) | 0b1100111;
    loadInst(&cpu, jalr_word);
    _ = try cpu.step();
    // rd should get return addr (pc+4 = 4), NOT the computed target
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(1));
    // pc = (0x200 + 4) & ~1 = 0x204
    try std.testing.expectEqual(@as(u32, 0x204), cpu.pc);
}

test "step: ECALL" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00000073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: EBREAK" {
    var cpu = Cpu.init();
    loadInst(&cpu, 0x00100073);
    const result = try cpu.step();
    try std.testing.expectEqual(StepResult.Ebreak, result);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "step: x0 writes ignored" {
    var cpu = Cpu.init();
    // ADDI x0, x0, 42 — should not change x0
    loadInst(&cpu, 0x02A00013);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "step: cycle count increments" {
    var cpu = Cpu.init();
    // Two NOPs (ADDI x0, x0, 0 = 0x00000013)
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: multi-instruction ADDI + ADD" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 5 = 0x00500093
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00500093, .little);
    // ADDI x2, x0, 10 = 0x00A00113
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00A00113, .little);
    // ADD x3, x1, x2 = 0x002081B3
    std.mem.writeInt(u32, cpu.memory[8..12], 0x002081B3, .little);

    _ = try cpu.step();
    _ = try cpu.step();
    _ = try cpu.step();

    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 15), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 12), cpu.pc);
    try std.testing.expectEqual(@as(u64, 3), cpu.cycle_count);
}

test "step: full demo program" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 100
    // imm=100=0x64, rs1=0, rd=1, funct3=000, opcode=0010011
    // = 0x06400093
    std.mem.writeInt(u32, cpu.memory[0..4], 0x06400093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00A00113, .little);
    // ADD x3, x1, x2
    std.mem.writeInt(u32, cpu.memory[8..12], 0x002081B3, .little);
    // SW x3, 0(x1) — store at address 100 (aligned)
    std.mem.writeInt(u32, cpu.memory[12..16], 0x0030A023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[16..20], 0x00000073, .little);

    var result: StepResult = .Continue;
    while (result == .Continue) {
        result = try cpu.step();
    }

    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 100), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 5), cpu.cycle_count);
    // Verify SW wrote to memory at address 100
    try std.testing.expectEqual(@as(u32, 110), std.mem.readInt(u32, cpu.memory[100..104], .little));
}

// --- run() tests ---

test "run: stops on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run: stops on EBREAK" {
    var cpu = Cpu.init();
    // EBREAK
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00100073, .little);

    const result = try cpu.run(0);
    try std.testing.expectEqual(StepResult.Ebreak, result);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "run: respects max_cycles" {
    var cpu = Cpu.init();
    // 4 NOPs then ECALL
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[8..12], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[12..16], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[16..20], 0x00000073, .little);

    // Limit to 2 cycles — should stop before ECALL
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "run: max_cycles exactly at ECALL" {
    var cpu = Cpu.init();
    // NOP then ECALL
    std.mem.writeInt(u32, cpu.memory[0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..8], 0x00000073, .little);

    // max_cycles=2: should execute both instructions
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}
