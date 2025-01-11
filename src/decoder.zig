const std = @import("std");
const instruction = @import("instruction.zig");
const Opcode = instruction.Opcode;
const Instruction = instruction.Instruction;

pub const DecodeError = error{IllegalInstruction};

/// Decode a 32-bit RISC-V instruction word into an Instruction.
pub fn decode(raw: u32) DecodeError!Instruction {
    const opcode_bits: u7 = @truncate(raw);
    return switch (opcode_bits) {
        0b0110011 => decodeR(raw),
        0b0010011 => decodeIAlu(raw),
        0b0000011 => decodeLoad(raw),
        0b0100011 => decodeS(raw),
        0b1100011 => decodeB(raw),
        0b0110111 => decodeU(raw, .LUI),
        0b0010111 => decodeU(raw, .AUIPC),
        0b1101111 => decodeJ(raw),
        0b1100111 => decodeJalr(raw),
        0b1110011 => decodeSystem(raw),
        else => error.IllegalInstruction,
    };
}

// --- Bit field extraction ---

fn rd(raw: u32) u5 {
    return @truncate(raw >> 7);
}

fn funct3(raw: u32) u3 {
    return @truncate(raw >> 12);
}

fn rs1(raw: u32) u5 {
    return @truncate(raw >> 15);
}

fn rs2(raw: u32) u5 {
    return @truncate(raw >> 20);
}

fn funct7(raw: u32) u7 {
    return @truncate(raw >> 25);
}

// --- Immediate extraction ---

fn immI(raw: u32) i32 {
    const bits: i32 = @bitCast(raw);
    return bits >> 20; // arithmetic right shift sign-extends
}

fn immS(raw: u32) i32 {
    const imm_11_5: u32 = (raw >> 25) & 0x7F;
    const imm_4_0: u32 = (raw >> 7) & 0x1F;
    const imm_raw: u32 = (imm_11_5 << 5) | imm_4_0;
    // Sign extend from bit 11
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 20)) >> 20;
    return shifted;
}

fn immB(raw: u32) i32 {
    // imm[12|10:5|4:1|11]
    const imm_12: u32 = (raw >> 31) & 1;
    const imm_11: u32 = (raw >> 7) & 1;
    const imm_10_5: u32 = (raw >> 25) & 0x3F;
    const imm_4_1: u32 = (raw >> 8) & 0xF;
    const imm_raw: u32 = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1);
    // Sign extend from bit 12
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 19)) >> 19;
    return shifted;
}

fn immU(raw: u32) i32 {
    return @bitCast(raw & 0xFFFFF000);
}

fn immJ(raw: u32) i32 {
    // imm[20|10:1|11|19:12]
    const imm_20: u32 = (raw >> 31) & 1;
    const imm_19_12: u32 = (raw >> 12) & 0xFF;
    const imm_11: u32 = (raw >> 20) & 1;
    const imm_10_1: u32 = (raw >> 21) & 0x3FF;
    const imm_raw: u32 = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1);
    // Sign extend from bit 20
    const shifted: i32 = @as(i32, @bitCast(imm_raw << 11)) >> 11;
    return shifted;
}

// --- Sub-decoders ---

fn decodeR(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);
    const op: Opcode = switch (f3) {
        0b000 => switch (f7) {
            0b0000000 => .ADD,
            0b0100000 => .SUB,
            else => return error.IllegalInstruction,
        },
        0b001 => if (f7 == 0b0000000) .SLL else return error.IllegalInstruction,
        0b010 => if (f7 == 0b0000000) .SLT else return error.IllegalInstruction,
        0b011 => if (f7 == 0b0000000) .SLTU else return error.IllegalInstruction,
        0b100 => if (f7 == 0b0000000) .XOR else return error.IllegalInstruction,
        0b101 => switch (f7) {
            0b0000000 => .SRL,
            0b0100000 => .SRA,
            else => return error.IllegalInstruction,
        },
        0b110 => if (f7 == 0b0000000) .OR else return error.IllegalInstruction,
        0b111 => if (f7 == 0b0000000) .AND else return error.IllegalInstruction,
    };
    return .{ .op = op, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };
}

fn decodeIAlu(raw: u32) DecodeError!Instruction {
    const f3 = funct3(raw);
    const f7 = funct7(raw);
    const op: Opcode = switch (f3) {
        0b000 => .ADDI,
        0b010 => .SLTI,
        0b011 => .SLTIU,
        0b100 => .XORI,
        0b110 => .ORI,
        0b111 => .ANDI,
        0b001 => if (f7 == 0b0000000) .SLLI else return error.IllegalInstruction,
        0b101 => switch (f7) {
            0b0000000 => .SRLI,
            0b0100000 => .SRAI,
            else => return error.IllegalInstruction,
        },
    };
    // For shift instructions, immediate is the shamt (rs2 field = bits [24:20])
    const imm_val: i32 = if (f3 == 0b001 or f3 == 0b101)
        @as(i32, @intCast(rs2(raw)))
    else
        immI(raw);
    return .{ .op = op, .rd = rd(raw), .rs1 = rs1(raw), .imm = imm_val, .raw = raw };
}

fn decodeLoad(raw: u32) DecodeError!Instruction {
    const op: Opcode = switch (funct3(raw)) {
        0b000 => .LB,
        0b001 => .LH,
        0b010 => .LW,
        0b100 => .LBU,
        0b101 => .LHU,
        else => return error.IllegalInstruction,
    };
    return .{ .op = op, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

fn decodeS(raw: u32) DecodeError!Instruction {
    const op: Opcode = switch (funct3(raw)) {
        0b000 => .SB,
        0b001 => .SH,
        0b010 => .SW,
        else => return error.IllegalInstruction,
    };
    return .{ .op = op, .rs1 = rs1(raw), .rs2 = rs2(raw), .imm = immS(raw), .raw = raw };
}

fn decodeB(raw: u32) DecodeError!Instruction {
    const op: Opcode = switch (funct3(raw)) {
        0b000 => .BEQ,
        0b001 => .BNE,
        0b100 => .BLT,
        0b101 => .BGE,
        0b110 => .BLTU,
        0b111 => .BGEU,
        else => return error.IllegalInstruction,
    };
    return .{ .op = op, .rs1 = rs1(raw), .rs2 = rs2(raw), .imm = immB(raw), .raw = raw };
}

fn decodeU(raw: u32, op: Opcode) DecodeError!Instruction {
    return .{ .op = op, .rd = rd(raw), .imm = immU(raw), .raw = raw };
}

fn decodeJ(raw: u32) DecodeError!Instruction {
    return .{ .op = .JAL, .rd = rd(raw), .imm = immJ(raw), .raw = raw };
}

fn decodeJalr(raw: u32) DecodeError!Instruction {
    if (funct3(raw) != 0b000) return error.IllegalInstruction;
    return .{ .op = .JALR, .rd = rd(raw), .rs1 = rs1(raw), .imm = immI(raw), .raw = raw };
}

fn decodeSystem(raw: u32) DecodeError!Instruction {
    return switch (raw) {
        0x00000073 => .{ .op = .ECALL, .raw = raw },
        0x00100073 => .{ .op = .EBREAK, .raw = raw },
        else => error.IllegalInstruction,
    };
}

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

test "illegal instruction returns error" {
    // All zeros is not a valid RISC-V instruction (opcode 0b0000000)
    try std.testing.expectError(error.IllegalInstruction, decode(0));
    // Invalid funct7 for R-type ADD
    try std.testing.expectError(error.IllegalInstruction, decode(encodeR(0b0110011, 0b000, 0b1111111, 0, 0, 0)));
}
