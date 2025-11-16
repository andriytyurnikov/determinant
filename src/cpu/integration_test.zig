const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;
const h = @import("../instructions/test_helpers.zig");

fn writeProgram(memory: []u8, program: []const u32) void {
    for (program, 0..) |word, i| {
        const offset = i * 4;
        std.mem.writeInt(u32, memory[offset..][0..4], word, .little);
    }
}

// --- Multi-extension programs ---

test "run: multi-extension M + Zba + Zbb + Zbs" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 1, 0, 7), // ADDI x1, x0, 7
        h.encodeI(0b0010011, 0b000, 2, 0, 6), // ADDI x2, x0, 6
        h.encodeR(0b0110011, 0b000, 0b0000001, 3, 1, 2), // MUL x3, x1, x2 → 42
        h.encodeR(0b0110011, 0b010, 0b0010000, 4, 3, 1), // SH1ADD x4, x3, x1 → 42*2+7=91
        h.encodeI(0b0010011, 0b001, 5, 4, 0x600), // CLZ x5, x4 → 25
        h.encodeR(0b0110011, 0b001, 0b0010100, 6, 0, 5), // BSET x6, x0, x5 → 0x02000000
        h.encodeI(0b0010011, 0b101, 7, 6, 0x698), // REV8 x7, x6 → 0x00000002
        h.encodeCsr(0b010, 8, 0, 0xC00), // CSRRS x8, cycle, x0
        0x00000073, // ECALL
    };
    writeProgram(&cpu.memory, &program);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 91), cpu.readReg(4));
    try std.testing.expectEqual(@as(u32, 25), cpu.readReg(5));
    try std.testing.expectEqual(@as(u32, 0x02000000), cpu.readReg(6));
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(7));
    try std.testing.expectEqual(@as(u32, 7), cpu.readReg(8)); // pre-step cycle
    try std.testing.expectEqual(@as(u64, 9), cpu.cycle_count);
}

test "run: multi-extension M + A with atomics" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 1, 0, 10), // ADDI x1, x0, 10
        h.encodeI(0b0010011, 0b000, 2, 0, 3), // ADDI x2, x0, 3
        h.encodeR(0b0110011, 0b000, 0b0000001, 3, 1, 2), // MUL x3, x1, x2 → 30
        h.encodeS(0b010, 0, 3, 256), // SW x3, 256(x0) → mem[256]=30
        h.encodeI(0b0010011, 0b000, 4, 0, 256), // ADDI x4, x0, 256
        h.encodeAtomic(0b00000, 5, 4, 2), // AMOADD x5, x2, (x4) → x5=30, mem[256]=33
        h.encodeAtomic(0b00001, 6, 4, 1), // AMOSWAP x6, x1, (x4) → x6=33, mem[256]=10
        0x00000073, // ECALL
    };
    writeProgram(&cpu.memory, &program);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 30), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 30), cpu.readReg(5));
    try std.testing.expectEqual(@as(u32, 33), cpu.readReg(6));
    try std.testing.expectEqual(@as(u32, 10), h.readWordAt(&cpu, 256));
    try std.testing.expectEqual(@as(u64, 8), cpu.cycle_count);
}

// --- Realistic patterns ---

test "run: counted loop sums 1 to 10" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 1, 0, 10), // ADDI x1, x0, 10
        h.encodeI(0b0010011, 0b000, 2, 0, 0), // ADDI x2, x0, 0
        h.encodeR(0b0110011, 0b000, 0b0000000, 2, 2, 1), // ADD x2, x2, x1
        h.encodeI(0b0010011, 0b000, 1, 1, 0xFFF), // ADDI x1, x1, -1
        h.encodeB(0b001, 1, 0, -8), // BNE x1, x0, -8
        0x00000073, // ECALL
    };
    writeProgram(&cpu.memory, &program);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 55), cpu.readReg(2));
    try std.testing.expectEqual(@as(u64, 33), cpu.cycle_count);
}

test "run: function call and return via JAL and JALR" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 10, 0, 5), // 0: ADDI x10, x0, 5
        h.encodeJ(1, 12), // 4: JAL x1, +12 → pc=16, x1=8
        h.encodeR(0b0110011, 0b000, 0b0000000, 11, 10, 0), // 8: ADD x11, x10, x0
        0x00000073, // 12: ECALL
        h.encodeR(0b0110011, 0b000, 0b0000000, 10, 10, 10), // 16: ADD x10, x10, x10 → x10=10
        h.encodeI(0b1100111, 0b000, 0, 1, 0), // 20: JALR x0, x1, 0 → pc=8
    };
    writeProgram(&cpu.memory, &program);

    // Execution: 0→4→16→20→8→12
    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 8), cpu.readReg(1)); // link address
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(10)); // doubled
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(11)); // copied
    try std.testing.expectEqual(@as(u64, 6), cpu.cycle_count);
}

test "run: stack frame push and pop" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeU(0b0110111, 2, 1), // LUI x2, 1 → sp=0x1000
        h.encodeI(0b0010011, 0b000, 10, 0, 42), // ADDI x10, x0, 42
        h.encodeI(0b0010011, 0b000, 11, 0, 99), // ADDI x11, x0, 99
        h.encodeI(0b0010011, 0b000, 2, 2, 0xFF8), // ADDI x2, x2, -8 → sp=4088
        h.encodeS(0b010, 2, 10, 0), // SW x10, 0(x2)
        h.encodeS(0b010, 2, 11, 4), // SW x11, 4(x2)
        h.encodeI(0b0010011, 0b000, 10, 0, 0), // ADDI x10, x0, 0 — clobber
        h.encodeI(0b0010011, 0b000, 11, 0, 0), // ADDI x11, x0, 0 — clobber
        h.encodeI(0b0000011, 0b010, 10, 2, 0), // LW x10, 0(x2)
        h.encodeI(0b0000011, 0b010, 11, 2, 4), // LW x11, 4(x2)
        h.encodeI(0b0010011, 0b000, 2, 2, 8), // ADDI x2, x2, 8 → sp=4096
        0x00000073, // ECALL
    };
    writeProgram(&cpu.memory, &program);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 4096), cpu.readReg(2)); // sp restored
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(10)); // restored from stack
    try std.testing.expectEqual(@as(u32, 99), cpu.readReg(11)); // restored from stack
    try std.testing.expectEqual(@as(u64, 12), cpu.cycle_count);
}

// --- Stress tests ---

test "run: 200-iteration loop with SH1ADD" {
    var cpu = Cpu.init();
    const program = [_]u32{
        h.encodeI(0b0010011, 0b000, 1, 0, 200), // ADDI x1, x0, 200
        h.encodeI(0b0010011, 0b000, 2, 0, 0), // ADDI x2, x0, 0 — sum
        h.encodeI(0b0010011, 0b000, 3, 0, 0), // ADDI x3, x0, 0 — i
        h.encodeI(0b0010011, 0b000, 4, 0, 1), // ADDI x4, x0, 1
        h.encodeR(0b0110011, 0b010, 0b0010000, 5, 3, 4), // SH1ADD x5, x3, x4 → i*2+1
        h.encodeR(0b0110011, 0b000, 0b0000000, 2, 2, 5), // ADD x2, x2, x5
        h.encodeI(0b0010011, 0b000, 3, 3, 1), // ADDI x3, x3, 1
        h.encodeB(0b001, 3, 1, -12), // BNE x3, x1, -12
        0x00000073, // ECALL
    };
    writeProgram(&cpu.memory, &program);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 40000), cpu.readReg(2)); // 200^2
    try std.testing.expectEqual(@as(u32, 200), cpu.readReg(3));
    try std.testing.expectEqual(@as(u64, 805), cpu.cycle_count);
}

test "run: 1000 NOPs then ECALL" {
    var cpu = Cpu.init();
    // Write 1000 NOPs
    for (0..1000) |i| {
        const offset = i * 4;
        std.mem.writeInt(u32, cpu.memory[offset..][0..4], 0x00000013, .little);
    }
    // ECALL at offset 4000
    std.mem.writeInt(u32, cpu.memory[4000..][0..4], 0x00000073, .little);

    const result = try cpu.run(0);

    try std.testing.expectEqual(StepResult.ecall, result);
    try std.testing.expectEqual(@as(u32, 4004), cpu.pc);
    try std.testing.expectEqual(@as(u64, 1001), cpu.cycle_count);
    // All registers should be 0 (NOPs don't modify registers)
    for (1..32) |r| {
        try std.testing.expectEqual(@as(u32, 0), cpu.readReg(@intCast(r)));
    }
}
