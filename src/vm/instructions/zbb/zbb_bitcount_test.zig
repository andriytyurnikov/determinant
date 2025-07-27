const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder/branch_decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const loadInst = h.loadInst;

fn encodeR(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return h.encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
}

fn encodeIShamt(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, shamt: u5) u32 {
    const imm12: u12 = (@as(u12, f7) << 5) | @as(u12, shamt);
    return h.encodeI(0b0010011, f3, rd_v, rs1_v, imm12);
}

// --- Decode tests ---

test "decode Zbb R-type ANDN ORN XNOR MIN MINU MAX MAXU ROL ROR" {
    const cases = .{
        .{ @as(u3, 0b111), @as(u7, 0b0100000), Opcode{ .zbb = .ANDN } },
        .{ @as(u3, 0b110), @as(u7, 0b0100000), Opcode{ .zbb = .ORN } },
        .{ @as(u3, 0b100), @as(u7, 0b0100000), Opcode{ .zbb = .XNOR } },
        .{ @as(u3, 0b100), @as(u7, 0b0000101), Opcode{ .zbb = .MIN } },
        .{ @as(u3, 0b101), @as(u7, 0b0000101), Opcode{ .zbb = .MINU } },
        .{ @as(u3, 0b110), @as(u7, 0b0000101), Opcode{ .zbb = .MAX } },
        .{ @as(u3, 0b111), @as(u7, 0b0000101), Opcode{ .zbb = .MAXU } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), Opcode{ .zbb = .ROL } },
        .{ @as(u3, 0b101), @as(u7, 0b0110000), Opcode{ .zbb = .ROR } },
    };
    inline for (cases) |c| {
        const raw = encodeR(c[0], c[1], 4, 5, 6);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
        try std.testing.expectEqual(@as(u5, 4), inst.rd);
        try std.testing.expectEqual(@as(u5, 5), inst.rs1);
        try std.testing.expectEqual(@as(u5, 6), inst.rs2);
    }
}

test "decode Zbb R-type ZEXT_H" {
    const raw = encodeR(0b100, 0b0000100, 4, 5, 0); // rs2=0 required
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .zbb = .ZEXT_H }, inst.op);
}

test "decode Zbb I-type CLZ CTZ CPOP SEXT_B SEXT_H RORI ORC_B REV8" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 0), Opcode{ .zbb = .CLZ } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 1), Opcode{ .zbb = .CTZ } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 2), Opcode{ .zbb = .CPOP } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 4), Opcode{ .zbb = .SEXT_B } },
        .{ @as(u3, 0b001), @as(u7, 0b0110000), @as(u5, 5), Opcode{ .zbb = .SEXT_H } },
        .{ @as(u3, 0b101), @as(u7, 0b0110000), @as(u5, 3), Opcode{ .zbb = .RORI } },
        .{ @as(u3, 0b101), @as(u7, 0b0010100), @as(u5, 7), Opcode{ .zbb = .ORC_B } },
        .{ @as(u3, 0b101), @as(u7, 0b0110100), @as(u5, 24), Opcode{ .zbb = .REV8 } },
    };
    inline for (cases) |c| {
        const raw = encodeIShamt(c[0], c[1], 4, 5, c[2]);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[3], inst.op);
    }
}

// --- CLZ/CTZ/CPOP execute tests ---

test "step: CLZ zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}

test "step: CLZ one" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 31), cpu.readReg(3));
}

test "step: CLZ high bit" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CLZ all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CTZ zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}

test "step: CTZ low bit" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 1);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CTZ trailing zeros" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 7), cpu.readReg(3));
}

test "step: CTZ all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CPOP zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CPOP all ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 32), cpu.readReg(3));
}

test "step: CPOP mixed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0F0F0F0F);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 16), cpu.readReg(3));
}

test "step: CPOP single bit low" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

test "step: CPOP single bit high" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

// SEXT_B/SEXT_H/ZEXT_H tests in split file
comptime {
    _ = @import("zbb_sext_test.zig");
}
