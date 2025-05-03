const std = @import("std");
const instructions = @import("../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const StepResult = cpu_mod.StepResult;
const h = @import("test_helpers.zig");

const encodeR = h.encodeR;
const encodeI = h.encodeI;
const encodeS = h.encodeS;
const encodeB = h.encodeB;
const encodeU = h.encodeU;
const encodeJ = h.encodeJ;
const loadInst = h.loadInst;

// === Decode tests (from decoder_test.zig) ===

test "decode R-type ADD" {
    const raw = encodeR(0b0110011, 0b000, 0b0000000, 1, 2, 3);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .ADD }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(u5, 3), inst.rs2);
}

test "decode R-type SUB" {
    const raw = encodeR(0b0110011, 0b000, 0b0100000, 5, 6, 7);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .SUB }, inst.op);
    try std.testing.expectEqual(@as(u5, 5), inst.rd);
    try std.testing.expectEqual(@as(u5, 6), inst.rs1);
    try std.testing.expectEqual(@as(u5, 7), inst.rs2);
}

test "decode R-type SLL SLT SLTU XOR SRL SRA OR AND" {
    const cases = .{
        .{ 0b001, 0b0000000, Opcode{ .i = .SLL } },
        .{ 0b010, 0b0000000, Opcode{ .i = .SLT } },
        .{ 0b011, 0b0000000, Opcode{ .i = .SLTU } },
        .{ 0b100, 0b0000000, Opcode{ .i = .XOR } },
        .{ 0b101, 0b0000000, Opcode{ .i = .SRL } },
        .{ 0b101, 0b0100000, Opcode{ .i = .SRA } },
        .{ 0b110, 0b0000000, Opcode{ .i = .OR } },
        .{ 0b111, 0b0000000, Opcode{ .i = .AND } },
    };
    inline for (cases) |c| {
        const raw = encodeR(0b0110011, c[0], c[1], 1, 2, 3);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
    }
}

test "decode I-type ADDI positive" {
    const raw = encodeI(0b0010011, 0b000, 1, 2, 42);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(i32, 42), inst.imm);
}

test "decode I-type ADDI negative" {
    // -1 as 12-bit = 0xFFF
    const raw = encodeI(0b0010011, 0b000, 1, 2, 0xFFF);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(i32, -1), inst.imm);
}

test "decode I-type SLTI SLTIU XORI ORI ANDI" {
    const cases = .{
        .{ @as(u3, 0b010), Opcode{ .i = .SLTI } },
        .{ @as(u3, 0b011), Opcode{ .i = .SLTIU } },
        .{ @as(u3, 0b100), Opcode{ .i = .XORI } },
        .{ @as(u3, 0b110), Opcode{ .i = .ORI } },
        .{ @as(u3, 0b111), Opcode{ .i = .ANDI } },
    };
    inline for (cases) |c| {
        const raw = encodeI(0b0010011, c[0], 1, 2, 100);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
    }
}

test "decode I-type shifts SLLI SRLI SRAI" {
    // SLLI: funct7=0000000, shamt=5
    const slli = encodeI(0b0010011, 0b001, 1, 2, 5); // imm[11:0] = 0b0000000_00101
    const inst_slli = try decode(slli);
    try std.testing.expectEqual(Opcode{ .i = .SLLI }, inst_slli.op);
    try std.testing.expectEqual(@as(i32, 5), inst_slli.imm);

    // SRLI: funct7=0000000, shamt=3
    const srli = encodeI(0b0010011, 0b101, 1, 2, 3);
    const inst_srli = try decode(srli);
    try std.testing.expectEqual(Opcode{ .i = .SRLI }, inst_srli.op);
    try std.testing.expectEqual(@as(i32, 3), inst_srli.imm);

    // SRAI: funct7=0100000, shamt=7 → imm[11:0] = 0b0100000_00111 = 0x407
    const srai = encodeI(0b0010011, 0b101, 1, 2, 0b010000000111);
    const inst_srai = try decode(srai);
    try std.testing.expectEqual(Opcode{ .i = .SRAI }, inst_srai.op);
    try std.testing.expectEqual(@as(i32, 7), inst_srai.imm);
}

test "decode loads LB LH LW LBU LHU" {
    const cases = .{
        .{ @as(u3, 0b000), Opcode{ .i = .LB } },
        .{ @as(u3, 0b001), Opcode{ .i = .LH } },
        .{ @as(u3, 0b010), Opcode{ .i = .LW } },
        .{ @as(u3, 0b100), Opcode{ .i = .LBU } },
        .{ @as(u3, 0b101), Opcode{ .i = .LHU } },
    };
    inline for (cases) |c| {
        const raw = encodeI(0b0000011, c[0], 1, 2, 8);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(i32, 8), inst.imm);
    }
}

test "decode stores SB SH SW" {
    const cases = .{
        .{ @as(u3, 0b000), Opcode{ .i = .SB } },
        .{ @as(u3, 0b001), Opcode{ .i = .SH } },
        .{ @as(u3, 0b010), Opcode{ .i = .SW } },
    };
    inline for (cases) |c| {
        const raw = encodeS(c[0], 2, 3, 16);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(u5, 2), inst.rs1);
        try std.testing.expectEqual(@as(u5, 3), inst.rs2);
        try std.testing.expectEqual(@as(i32, 16), inst.imm);
    }
}

test "decode S-type negative immediate" {
    // -4 as 12-bit = 0xFFC
    const raw = encodeS(0b010, 2, 3, 0xFFC);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .SW }, inst.op);
    try std.testing.expectEqual(@as(i32, -4), inst.imm);
}

test "decode branches BEQ BNE BLT BGE BLTU BGEU" {
    const cases = .{
        .{ @as(u3, 0b000), Opcode{ .i = .BEQ } },
        .{ @as(u3, 0b001), Opcode{ .i = .BNE } },
        .{ @as(u3, 0b100), Opcode{ .i = .BLT } },
        .{ @as(u3, 0b101), Opcode{ .i = .BGE } },
        .{ @as(u3, 0b110), Opcode{ .i = .BLTU } },
        .{ @as(u3, 0b111), Opcode{ .i = .BGEU } },
    };
    inline for (cases) |c| {
        const raw = encodeB(c[0], 1, 2, 8);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(i32, 8), inst.imm);
    }
}

test "decode B-type negative offset" {
    // -16 as i13
    const raw = encodeB(0b000, 1, 2, -16);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .BEQ }, inst.op);
    try std.testing.expectEqual(@as(i32, -16), inst.imm);
}

test "decode LUI" {
    const raw = encodeU(0b0110111, 1, 0xDEAD);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .LUI }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0xDEAD) << 12)), inst.imm);
}

test "decode AUIPC" {
    const raw = encodeU(0b0010111, 2, 0x12345);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .AUIPC }, inst.op);
    try std.testing.expectEqual(@as(u5, 2), inst.rd);
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0x12345) << 12)), inst.imm);
}

test "decode JAL" {
    const raw = encodeJ(1, 100);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(i32, 100), inst.imm);
}

test "decode JAL negative" {
    const raw = encodeJ(1, -20);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
    try std.testing.expectEqual(@as(i32, -20), inst.imm);
}

test "decode JALR" {
    const raw = encodeI(0b1100111, 0b000, 1, 2, 4);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .JALR }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(i32, 4), inst.imm);
}

test "decode ECALL" {
    // ECALL: all zeros except opcode = 0b1110011
    const raw: u32 = 0b1110011;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .ECALL }, inst.op);
}

test "decode EBREAK" {
    // EBREAK: bit 20 set, rest zeros except opcode
    const raw: u32 = (1 << 20) | 0b1110011;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .EBREAK }, inst.op);
}

test "illegal instruction returns error" {
    // All zeros is not a valid RISC-V instruction (opcode 0b0000000)
    try std.testing.expectError(error.IllegalInstruction, decode(0));
    // Invalid funct7 for R-type ADD
    try std.testing.expectError(error.IllegalInstruction, decode(encodeR(0b0110011, 0b000, 0b1111111, 0, 0, 0)));
}

// === Execute tests (I-extension step tests from cpu_test.zig) ===

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
    const jal_word: u32 = (0b0000000100 << 21) | (0b00001 << 7) | 0b1101111;
    std.mem.writeInt(u32, cpu.memory[0x100..][0..4], jal_word, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x104), cpu.readReg(1)); // return address
    try std.testing.expectEqual(@as(u32, 0x108), cpu.pc); // jumped to pc+8
}

test "step: JALR clears LSB" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x103); // odd address
    const jalr_word: u32 = (0b00001 << 15) | (0b00010 << 7) | 0b1100111;
    loadInst(&cpu, jalr_word);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(2)); // return address = pc + 4
    try std.testing.expectEqual(@as(u32, 0x102), cpu.pc); // (0x103 + 0) & ~1
}

test "step: JALR rd == rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x200);
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
