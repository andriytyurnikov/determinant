const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const h = @import("../test_helpers.zig");

const encodeR = h.encodeR;
const encodeI = h.encodeI;
const encodeS = h.encodeS;
const encodeB = h.encodeB;
const encodeU = h.encodeU;
const encodeJ = h.encodeJ;

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

test "decode FENCE" {
    // Standard FENCE iorw, iorw = 0x0FF0000F
    const raw: u32 = 0x0FF0000F;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
}
