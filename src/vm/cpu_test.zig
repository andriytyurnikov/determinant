const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const MEMORY_SIZE = cpu_mod.MEMORY_SIZE;
const StepResult = cpu_mod.StepResult;

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
    // Write a little-endian u32 at address 0 (bits[1:0]=11 so it's treated as 32-bit)
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x1234567F, .little);
    const inst = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x1234567F), inst);
}

test "fetch misaligned PC" {
    var cpu = Cpu.init();
    cpu.pc = 1; // odd address is misaligned (2-byte alignment required)
    try std.testing.expectError(error.MisalignedPC, cpu.fetch());
}

test "fetch at 2-byte-aligned address" {
    var cpu = Cpu.init();
    // Write a 32-bit instruction at address 2 (2-byte aligned but not 4-byte)
    std.mem.writeInt(u32, cpu.memory[2..][0..4], 0x00000013, .little);
    cpu.pc = 2;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x00000013), raw);
}

test "fetch compressed instruction returns zero-extended u16" {
    var cpu = Cpu.init();
    // C.NOP = 0x0001 (low 2 bits = 01, not 11 → compressed)
    std.mem.writeInt(u16, cpu.memory[0..][0..2], 0x0001, .little);
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x0001), raw);
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

// --- Pipeline infrastructure tests ---

test "step: cycle count increments" {
    var cpu = Cpu.init();
    // Two NOPs (ADDI x0, x0, 0 = 0x00000013)
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "step: multi-instruction ADDI + ADD" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 5 = 0x00500093
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00500093, .little);
    // ADDI x2, x0, 10 = 0x00A00113
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2 = 0x002081B3
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x002081B3, .little);

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
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x06400093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x002081B3, .little);
    // SW x3, 0(x1) — store at address 100 (aligned)
    std.mem.writeInt(u32, cpu.memory[12..][0..4], 0x0030A023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[16..][0..4], 0x00000073, .little);

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
    try std.testing.expectEqual(@as(u32, 110), std.mem.readInt(u32, cpu.memory[100..][0..4], .little));
}

// --- run() tests ---

test "run: stops on ECALL" {
    var cpu = Cpu.init();
    // ADDI x1, x0, 42
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x02A00093, .little);
    // ECALL
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(1));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "run: stops on EBREAK" {
    var cpu = Cpu.init();
    // EBREAK
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00100073, .little);

    const result = try cpu.run(100);
    try std.testing.expectEqual(StepResult.Ebreak, result);
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

test "run: respects max_cycles" {
    var cpu = Cpu.init();
    // 4 NOPs then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[8..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[12..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[16..][0..4], 0x00000073, .little);

    // Limit to 2 cycles — should stop before ECALL
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Continue, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "run: max_cycles exactly at ECALL" {
    var cpu = Cpu.init();
    // NOP then ECALL
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000073, .little);

    // max_cycles=2: should execute both instructions
    const result = try cpu.run(2);
    try std.testing.expectEqual(StepResult.Ecall, result);
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

// --- Boundary and edge-case tests ---

test "fetch: compressed instruction at MEMORY_SIZE - 2" {
    var cpu = Cpu.init();
    // Place a compressed NOP (C.NOP = 0x0001) at the very last 2 bytes
    const addr: usize = MEMORY_SIZE - 2;
    std.mem.writeInt(u16, cpu.memory[addr..][0..2], 0x0001, .little);
    cpu.pc = MEMORY_SIZE - 2;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x0001), raw);
}

test "fetch: 32-bit instruction at MEMORY_SIZE - 2 fails" {
    var cpu = Cpu.init();
    // Place bytes that look like a 32-bit instruction (bits[1:0] = 0b11) at MEMORY_SIZE-2
    // Only 2 bytes available, so 32-bit fetch must fail
    const addr: usize = MEMORY_SIZE - 2;
    std.mem.writeInt(u16, cpu.memory[addr..][0..2], 0x0013, .little); // ADDI low half, bits[1:0]=11
    cpu.pc = MEMORY_SIZE - 2;
    try std.testing.expectError(error.PCOutOfBounds, cpu.fetch());
}

test "fetch: 32-bit instruction at MEMORY_SIZE - 4 succeeds" {
    var cpu = Cpu.init();
    // NOP at the last 4-byte-aligned position
    const addr: usize = MEMORY_SIZE - 4;
    std.mem.writeInt(u32, cpu.memory[addr..][0..4], 0x00000013, .little);
    cpu.pc = MEMORY_SIZE - 4;
    const raw = try cpu.fetch();
    try std.testing.expectEqual(@as(u32, 0x00000013), raw);
}

test "loadProgram: exact fit (offset + len = MEMORY_SIZE)" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0x13, 0x00, 0x00, 0x00 };
    try cpu.loadProgram(&program, MEMORY_SIZE - 4);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[MEMORY_SIZE - 4]);
}

test "loadProgram: single byte at last address" {
    var cpu = Cpu.init();
    const program = [_]u8{0xFF};
    try cpu.loadProgram(&program, MEMORY_SIZE - 1);
    try std.testing.expectEqual(@as(u8, 0xFF), cpu.memory[MEMORY_SIZE - 1]);
}

test "loadProgram: one byte past end fails" {
    var cpu = Cpu.init();
    const program = [_]u8{ 0xFF, 0xFF };
    try std.testing.expectError(error.AddressOutOfBounds, cpu.loadProgram(&program, MEMORY_SIZE - 1));
}

test "loadProgram: full memory" {
    var cpu = Cpu.init();
    var program: [MEMORY_SIZE]u8 = undefined;
    @memset(&program, 0x13);
    try cpu.loadProgram(&program, 0);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[0]);
    try std.testing.expectEqual(@as(u8, 0x13), cpu.memory[MEMORY_SIZE - 1]);
}

test "readByte: last valid address" {
    var cpu = Cpu.init();
    cpu.memory[MEMORY_SIZE - 1] = 0xAB;
    try std.testing.expectEqual(@as(u8, 0xAB), try cpu.readByte(MEMORY_SIZE - 1));
}

test "readWord: last valid aligned address" {
    var cpu = Cpu.init();
    const addr: u32 = MEMORY_SIZE - 4;
    try cpu.writeWord(addr, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try cpu.readWord(addr));
}

test "readHalfword: last valid aligned address" {
    var cpu = Cpu.init();
    const addr: u32 = MEMORY_SIZE - 2;
    try cpu.writeHalfword(addr, 0xBEEF);
    try std.testing.expectEqual(@as(u16, 0xBEEF), try cpu.readHalfword(addr));
}

test "readWord: one past last valid address fails" {
    var cpu = Cpu.init();
    // MEMORY_SIZE - 3 is not 4-byte aligned, so MisalignedAccess
    try std.testing.expectError(error.MisalignedAccess, cpu.readWord(MEMORY_SIZE - 3));
    // MEMORY_SIZE is out of bounds
    try std.testing.expectError(error.AddressOutOfBounds, cpu.readWord(MEMORY_SIZE));
}

test "step: branch beyond memory causes PCOutOfBounds on next fetch" {
    const h = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // BEQ x0, x0, +4094 (large forward branch, always taken since x0==x0)
    // Target = 0 + 4094 = 4094, still in memory — but let's target beyond MEMORY_SIZE
    // Place instruction near end of memory, branch forward past it
    const pc: u32 = MEMORY_SIZE - 8;
    cpu.pc = pc;
    // BEQ x0, x0, +16 → target = (MEMORY_SIZE - 8) + 16 = MEMORY_SIZE + 8 → out of bounds
    h.loadInst(&cpu, h.encodeB(0b000, 0, 0, 16));
    _ = try cpu.step(); // branch is taken, sets next_pc beyond memory
    // PC is now MEMORY_SIZE + 8 (wrapped via +%)
    // Next fetch should fail
    try std.testing.expectError(error.PCOutOfBounds, cpu.step());
}

test "step: JAL beyond memory causes PCOutOfBounds on next fetch" {
    const h = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    const pc: u32 = MEMORY_SIZE - 4;
    cpu.pc = pc;
    // JAL x1, +8 → target = (MEMORY_SIZE - 4) + 8 = MEMORY_SIZE + 4 → out of bounds
    h.loadInst(&cpu, h.encodeJ(1, 8));
    _ = try cpu.step(); // JAL taken, link saved, next_pc beyond memory
    // Verify link register saved correctly
    try std.testing.expectEqual(pc + 4, cpu.readReg(1));
    // Next fetch should fail
    try std.testing.expectError(error.PCOutOfBounds, cpu.step());
}

test "step: cycle_count wrapping at u64 max" {
    var cpu = Cpu.init();
    cpu.cycle_count = std.math.maxInt(u64);
    // NOP
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u64, 0), cpu.cycle_count);
}

test "step: backward branch (negative offset)" {
    const h2 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // NOP at address 0
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0x00000013, .little);
    // NOP at address 4
    std.mem.writeInt(u32, cpu.memory[4..][0..4], 0x00000013, .little);
    // BEQ x0, x0, -4 at address 8 → target = 4
    cpu.pc = 8;
    std.mem.writeInt(u32, cpu.memory[8..][0..4], h2.encodeB(0b000, 0, 0, -4), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

// --- Error path tests through step() ---

test "step: illegal instruction 0xFFFFFFFF" {
    var cpu = Cpu.init();
    std.mem.writeInt(u32, cpu.memory[0..][0..4], 0xFFFFFFFF, .little);
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: OOB load via LW causes AddressOutOfBounds" {
    const h3 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, MEMORY_SIZE); // address out of bounds
    // LW x2, 0(x1) = encodeI(0b0000011, 0b010, 2, 1, 0)
    h3.loadInst(&cpu, h3.encodeI(0b0000011, 0b010, 2, 1, 0));
    try std.testing.expectError(error.AddressOutOfBounds, cpu.step());
}

test "step: misaligned LW causes MisalignedAccess" {
    const h4 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 3); // misaligned for word access
    // LW x2, 0(x1)
    h4.loadInst(&cpu, h4.encodeI(0b0000011, 0b010, 2, 1, 0));
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
}

test "determinism: two VMs with same program produce identical state" {
    var cpu1 = Cpu.init();
    var cpu2 = Cpu.init();

    // Same program: compute (5 + 10) * 3 via shifts and adds, store result, ECALL
    // ADDI x1, x0, 5
    std.mem.writeInt(u32, cpu1.memory[0..][0..4], 0x00500093, .little);
    std.mem.writeInt(u32, cpu2.memory[0..][0..4], 0x00500093, .little);
    // ADDI x2, x0, 10
    std.mem.writeInt(u32, cpu1.memory[4..][0..4], 0x00A00113, .little);
    std.mem.writeInt(u32, cpu2.memory[4..][0..4], 0x00A00113, .little);
    // ADD x3, x1, x2 (x3 = 15)
    std.mem.writeInt(u32, cpu1.memory[8..][0..4], 0x002081B3, .little);
    std.mem.writeInt(u32, cpu2.memory[8..][0..4], 0x002081B3, .little);
    // SLLI x4, x3, 1 (x4 = 30)
    std.mem.writeInt(u32, cpu1.memory[12..][0..4], 0x00119213, .little);
    std.mem.writeInt(u32, cpu2.memory[12..][0..4], 0x00119213, .little);
    // ADD x5, x4, x3 (x5 = 45)
    std.mem.writeInt(u32, cpu1.memory[16..][0..4], 0x003202B3, .little);
    std.mem.writeInt(u32, cpu2.memory[16..][0..4], 0x003202B3, .little);
    // SW x5, 256(x0)
    std.mem.writeInt(u32, cpu1.memory[20..][0..4], 0x10502023, .little);
    std.mem.writeInt(u32, cpu2.memory[20..][0..4], 0x10502023, .little);
    // ECALL
    std.mem.writeInt(u32, cpu1.memory[24..][0..4], 0x00000073, .little);
    std.mem.writeInt(u32, cpu2.memory[24..][0..4], 0x00000073, .little);

    const result1 = try cpu1.run(100);
    const result2 = try cpu2.run(100);

    // Identical results
    try std.testing.expectEqual(result1, result2);
    try std.testing.expectEqual(cpu1.pc, cpu2.pc);
    try std.testing.expectEqual(cpu1.cycle_count, cpu2.cycle_count);

    // Identical register state
    for (0..32) |i| {
        try std.testing.expectEqual(cpu1.readReg(@intCast(i)), cpu2.readReg(@intCast(i)));
    }

    // Identical memory at store target
    try std.testing.expectEqual(
        std.mem.readInt(u32, cpu1.memory[256..][0..4], .little),
        std.mem.readInt(u32, cpu2.memory[256..][0..4], .little),
    );

    // Verify expected values
    try std.testing.expectEqual(StepResult.Ecall, result1);
    try std.testing.expectEqual(@as(u32, 45), cpu1.readReg(5));
    try std.testing.expectEqual(@as(u32, 45), std.mem.readInt(u32, cpu1.memory[256..][0..4], .little));
}

// --- CSR cycle_count pipeline invariant test ---

test "step: CSR cycle_count sees pre-step value" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    // CSRRS x3, 0xC00, x0 — read cycle counter into x3
    h5.loadInst(&cpu, h5.encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    // cycle_count was 0 before step, so x3 should be 0 (not 1)
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 1), cpu.cycle_count);
}

// --- Extension dispatch through CPU tests ---

test "step: MUL dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 7);
    cpu.writeReg(2, 6);
    // MUL x3, x1, x2: opcode=0b0110011, funct3=000, funct7=0b0000001
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: SH1ADD dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    // SH1ADD x3, x1, x2: opcode=0b0110011, funct3=010, funct7=0b0010000
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3));
}

test "step: CLZ dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0F000000);
    // CLZ x2, x1: opcode=0b0010011, funct3=001, imm12=0b0110000_00000
    const imm12: u12 = (@as(u12, 0b0110000) << 5) | 0;
    h5.loadInst(&cpu, h5.encodeI(0b0010011, 0b001, 2, 1, imm12));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2));
}

test "step: BSET dispatch through CPU" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 5);
    // BSET x3, x1, x2: opcode=0b0110011, funct3=001, funct7=0b0010100
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}

// --- Boundary-value tests ---

test "step: ADD overflow wraps" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: SUB underflow wraps" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 1);
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b000, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: LB sign-extension bit 7" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LB x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(2));
}

test "step: LH sign-extension bit 15" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    std.mem.writeInt(u16, cpu.memory[200..][0..2], 0x8000, .little);
    cpu.writeReg(1, 200);
    // LH x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b001, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(2));
}

test "step: LBU zero-extension" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.memory[200] = 0x80;
    cpu.writeReg(1, 200);
    // LBU x2, 0(x1)
    h5.loadInst(&cpu, h5.encodeI(0b0000011, 0b100, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000080), cpu.readReg(2));
}

test "step: BLT SIGNED_MIN vs positive" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 1);
    // BLT x1, x2, +8
    h5.loadInst(&cpu, h5.encodeB(0b100, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: BGE SIGNED_MAX vs SIGNED_MIN" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x7FFFFFFF); // SIGNED_MAX
    cpu.writeReg(2, 0x80000000); // SIGNED_MIN
    // BGE x1, x2, +8
    h5.loadInst(&cpu, h5.encodeB(0b101, 1, 2, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 8), cpu.pc); // branch taken
}

test "step: JALR clears bit[0]" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x1001);
    // JALR x2, 0(x1) → target = 0x1001 & 0xFFFFFFFE = 0x1000
    h5.loadInst(&cpu, h5.encodeI(0b1100111, 0b000, 2, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1000), cpu.pc);
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // link = old_pc + 4
}

test "step: SLL shift masking rs2=32" {
    const h5 = @import("instructions/test_helpers.zig");
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF);
    cpu.writeReg(2, 32); // masked to 0
    // SLL x3, x1, x2
    h5.loadInst(&cpu, h5.encodeR(0b0110011, 0b001, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(3)); // shift by 0
}

// --- Phase 1: CPU integration tests for stores, LUI, AUIPC, atomics, CSR ---

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
