const std = @import("std");
const instruction = @import("instruction.zig");
const Opcode = instruction.Opcode;
const decoder = @import("decoder.zig");
const decode = decoder.decode;

// --- Helper to assemble instruction words for tests ---

fn encodeR(op: u7, f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

fn encodeI(op: u7, f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, imm12) << 20);
}

fn encodeS(f3: u3, rs1_v: u5, rs2_v: u5, imm12: u12) u32 {
    const imm: u32 = @intCast(imm12);
    const imm_4_0: u32 = imm & 0x1F;
    const imm_11_5: u32 = (imm >> 5) & 0x7F;
    return 0b0100011 |
        (imm_4_0 << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (imm_11_5 << 25);
}

fn encodeB(f3: u3, rs1_v: u5, rs2_v: u5, imm_val: i13) u32 {
    const imm: u13 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_12: u32 = (bits >> 12) & 1;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_10_5: u32 = (bits >> 5) & 0x3F;
    const bits_4_1: u32 = (bits >> 1) & 0xF;
    return 0b1100011 |
        (bit_11 << 7) |
        (bits_4_1 << 8) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (bits_10_5 << 25) |
        (bit_12 << 31);
}

fn encodeU(op: u7, rd_v: u5, imm20: u20) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, imm20) << 12);
}

fn encodeJ(rd_v: u5, imm_val: i21) u32 {
    const imm: u21 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_20: u32 = (bits >> 20) & 1;
    const bits_10_1: u32 = (bits >> 1) & 0x3FF;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_19_12: u32 = (bits >> 12) & 0xFF;
    return 0b1101111 |
        (@as(u32, rd_v) << 7) |
        (bits_19_12 << 12) |
        (bit_11 << 20) |
        (bits_10_1 << 21) |
        (bit_20 << 31);
}

// --- Tests ---

test "decode R-type ADD" {
    const raw = encodeR(0b0110011, 0b000, 0b0000000, 1, 2, 3);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.ADD, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(u5, 3), inst.rs2);
}

test "decode R-type SUB" {
    const raw = encodeR(0b0110011, 0b000, 0b0100000, 5, 6, 7);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.SUB, inst.op);
    try std.testing.expectEqual(@as(u5, 5), inst.rd);
    try std.testing.expectEqual(@as(u5, 6), inst.rs1);
    try std.testing.expectEqual(@as(u5, 7), inst.rs2);
}

test "decode R-type SLL SLT SLTU XOR SRL SRA OR AND" {
    const cases = .{
        .{ 0b001, 0b0000000, Opcode.SLL },
        .{ 0b010, 0b0000000, Opcode.SLT },
        .{ 0b011, 0b0000000, Opcode.SLTU },
        .{ 0b100, 0b0000000, Opcode.XOR },
        .{ 0b101, 0b0000000, Opcode.SRL },
        .{ 0b101, 0b0100000, Opcode.SRA },
        .{ 0b110, 0b0000000, Opcode.OR },
        .{ 0b111, 0b0000000, Opcode.AND },
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
    try std.testing.expectEqual(Opcode.ADDI, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(i32, 42), inst.imm);
}

test "decode I-type ADDI negative" {
    // -1 as 12-bit = 0xFFF
    const raw = encodeI(0b0010011, 0b000, 1, 2, 0xFFF);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.ADDI, inst.op);
    try std.testing.expectEqual(@as(i32, -1), inst.imm);
}

test "decode I-type SLTI SLTIU XORI ORI ANDI" {
    const cases = .{
        .{ @as(u3, 0b010), Opcode.SLTI },
        .{ @as(u3, 0b011), Opcode.SLTIU },
        .{ @as(u3, 0b100), Opcode.XORI },
        .{ @as(u3, 0b110), Opcode.ORI },
        .{ @as(u3, 0b111), Opcode.ANDI },
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
    try std.testing.expectEqual(Opcode.SLLI, inst_slli.op);
    try std.testing.expectEqual(@as(i32, 5), inst_slli.imm);

    // SRLI: funct7=0000000, shamt=3
    const srli = encodeI(0b0010011, 0b101, 1, 2, 3);
    const inst_srli = try decode(srli);
    try std.testing.expectEqual(Opcode.SRLI, inst_srli.op);
    try std.testing.expectEqual(@as(i32, 3), inst_srli.imm);

    // SRAI: funct7=0100000, shamt=7 → imm[11:0] = 0b0100000_00111 = 0x407
    const srai = encodeI(0b0010011, 0b101, 1, 2, 0b010000000111);
    const inst_srai = try decode(srai);
    try std.testing.expectEqual(Opcode.SRAI, inst_srai.op);
    try std.testing.expectEqual(@as(i32, 7), inst_srai.imm);
}

test "decode loads LB LH LW LBU LHU" {
    const cases = .{
        .{ @as(u3, 0b000), Opcode.LB },
        .{ @as(u3, 0b001), Opcode.LH },
        .{ @as(u3, 0b010), Opcode.LW },
        .{ @as(u3, 0b100), Opcode.LBU },
        .{ @as(u3, 0b101), Opcode.LHU },
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
        .{ @as(u3, 0b000), Opcode.SB },
        .{ @as(u3, 0b001), Opcode.SH },
        .{ @as(u3, 0b010), Opcode.SW },
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
    try std.testing.expectEqual(Opcode.SW, inst.op);
    try std.testing.expectEqual(@as(i32, -4), inst.imm);
}

test "decode branches BEQ BNE BLT BGE BLTU BGEU" {
    const cases = .{
        .{ @as(u3, 0b000), Opcode.BEQ },
        .{ @as(u3, 0b001), Opcode.BNE },
        .{ @as(u3, 0b100), Opcode.BLT },
        .{ @as(u3, 0b101), Opcode.BGE },
        .{ @as(u3, 0b110), Opcode.BLTU },
        .{ @as(u3, 0b111), Opcode.BGEU },
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
    try std.testing.expectEqual(Opcode.BEQ, inst.op);
    try std.testing.expectEqual(@as(i32, -16), inst.imm);
}

test "decode LUI" {
    const raw = encodeU(0b0110111, 1, 0xDEAD);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.LUI, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0xDEAD) << 12)), inst.imm);
}

test "decode AUIPC" {
    const raw = encodeU(0b0010111, 2, 0x12345);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.AUIPC, inst.op);
    try std.testing.expectEqual(@as(u5, 2), inst.rd);
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0x12345) << 12)), inst.imm);
}

test "decode JAL" {
    const raw = encodeJ(1, 100);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.JAL, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(i32, 100), inst.imm);
}

test "decode JAL negative" {
    const raw = encodeJ(1, -20);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.JAL, inst.op);
    try std.testing.expectEqual(@as(i32, -20), inst.imm);
}

test "decode JALR" {
    const raw = encodeI(0b1100111, 0b000, 1, 2, 4);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.JALR, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 2), inst.rs1);
    try std.testing.expectEqual(@as(i32, 4), inst.imm);
}

test "decode ECALL" {
    // ECALL: all zeros except opcode = 0b1110011
    const raw: u32 = 0b1110011;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.ECALL, inst.op);
}

test "decode EBREAK" {
    // EBREAK: bit 20 set, rest zeros except opcode
    const raw: u32 = (1 << 20) | 0b1110011;
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode.EBREAK, inst.op);
}

test "decode R-type M-extension MUL MULH MULHSU MULHU DIV DIVU REM REMU" {
    const cases = .{
        .{ @as(u3, 0b000), @as(u7, 0b0000001), Opcode.MUL },
        .{ @as(u3, 0b001), @as(u7, 0b0000001), Opcode.MULH },
        .{ @as(u3, 0b010), @as(u7, 0b0000001), Opcode.MULHSU },
        .{ @as(u3, 0b011), @as(u7, 0b0000001), Opcode.MULHU },
        .{ @as(u3, 0b100), @as(u7, 0b0000001), Opcode.DIV },
        .{ @as(u3, 0b101), @as(u7, 0b0000001), Opcode.DIVU },
        .{ @as(u3, 0b110), @as(u7, 0b0000001), Opcode.REM },
        .{ @as(u3, 0b111), @as(u7, 0b0000001), Opcode.REMU },
    };
    inline for (cases) |c| {
        const raw = encodeR(0b0110011, c[0], c[1], 4, 5, 6);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
        try std.testing.expectEqual(@as(u5, 4), inst.rd);
        try std.testing.expectEqual(@as(u5, 5), inst.rs1);
        try std.testing.expectEqual(@as(u5, 6), inst.rs2);
    }
}

test "illegal instruction returns error" {
    // All zeros is not a valid RISC-V instruction (opcode 0b0000000)
    try std.testing.expectError(error.IllegalInstruction, decode(0));
    // Invalid funct7 for R-type ADD
    try std.testing.expectError(error.IllegalInstruction, decode(encodeR(0b0110011, 0b000, 0b1111111, 0, 0, 0)));
}
