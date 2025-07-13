const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder.zig");
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

// --- Execute tests ---

test "step: ANDN basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b111, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF000F000), cpu.readReg(3));
}

test "step: ORN basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b110, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFF0FFF0), cpu.readReg(3));
}

test "step: XNOR basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFF00FF00);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeR(0b100, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0FF00FF0), cpu.readReg(3));
}

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

test "step: MAX signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -5))));
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: MAXU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b111, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: MIN signed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -5))));
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -5))), cpu.readReg(3));
}

test "step: MINU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeR(0b101, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: SEXT_B positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0000007F);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000007F), cpu.readReg(3));
}

test "step: SEXT_B negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000080);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(3));
}

test "step: SEXT_H positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00007FFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00007FFF), cpu.readReg(3));
}

test "step: SEXT_H negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00008000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(3));
}

test "step: ZEXT_H basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000BEEF), cpu.readReg(3));
}

test "step: ROL basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000003), cpu.readReg(3));
}

test "step: ROL by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: ROR basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: ROR by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: RORI basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: ORC_B mixed" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00010200);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00FFFF00), cpu.readReg(3));
}

test "step: ORC_B all zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: ORC_B all nonzero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x01010101);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: REV8 basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x01020304);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x04030201), cpu.readReg(3));
}

test "step: ROL with high rs2 (shift amount masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 0x21); // 33 & 0x1F = 1
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000003), cpu.readReg(3));
}

test "step: ROR with high rs2 (shift amount masking)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000001);
    cpu.writeReg(2, 0x21); // 33 & 0x1F = 1
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xC0000000), cpu.readReg(3));
}

test "step: RORI by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
}

test "step: SEXT_B with upper bits set" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEAD0080);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), cpu.readReg(3));
}

test "step: SEXT_H with upper bits set" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEAD8000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF8000), cpu.readReg(3));
}

test "step: SEXT_B boundary 0xFF" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x000000FF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // 0xFF as i8 = -1
}

test "step: RORI shamt=31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110000, 3, 1, 31));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(3)); // rotate right 31 = rotate left 1
}

test "step: MIN SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: MAX SIGNED_MIN vs SIGNED_MAX" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // SIGNED_MIN
    cpu.writeReg(2, 0x7FFFFFFF); // SIGNED_MAX
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3));
}

test "step: ROL by 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b001, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: ROR by 31" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000001);
    cpu.writeReg(2, 31);
    loadInst(&cpu, encodeR(0b101, 0b0110000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000002), cpu.readReg(3)); // rotate right 31 = rotate left 1
}

test "step: ORC_B single byte in each position" {
    var cpu = Cpu.init();
    // Byte 0 only
    cpu.writeReg(1, 0x00000001);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x000000FF), cpu.readReg(3));

    // Byte 1 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00000100);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x0000FF00), cpu.readReg(3));

    // Byte 2 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x00010000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), cpu.readReg(3));

    // Byte 3 only
    cpu.pc = 0;
    cpu.writeReg(1, 0x01000000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0010100, 3, 1, 7));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF000000), cpu.readReg(3));
}

test "step: REV8 palindrome" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xAAAAAAAA);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAAAAAA), cpu.readReg(3));
}

test "step: MINU with zero operand" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: MAXU equal values" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b111, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

// --- Boundary-value tests ---

test "step: CLZ all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: CTZ all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: REV8 zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: REV8 all-ones" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b101, 0b0110100, 3, 1, 24));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
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

test "step: SEXT_B zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 4));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: SEXT_H zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110000, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: ZEXT_H zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: ZEXT_H max halfword" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x0000FFFF);
    loadInst(&cpu, encodeR(0b100, 0b0000100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF), cpu.readReg(3));
}

test "step: ANDN identity (mask=0)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b111, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3)); // x & ~0 = x
}

test "step: ORN identity (mask=all-ones)" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b110, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3)); // x | ~0xFFFFFFFF = x | 0 = x
}

test "step: XNOR self" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xDEADBEEF);
    cpu.writeReg(2, 0xDEADBEEF);
    loadInst(&cpu, encodeR(0b100, 0b0100000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3)); // ~(x ^ x) = ~0
}

test "step: MIN equal operands" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b100, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: MAX equal operands" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b110, 0b0000101, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}
