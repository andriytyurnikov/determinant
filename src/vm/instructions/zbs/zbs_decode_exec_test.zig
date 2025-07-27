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

test "decode Zbs R-type BCLR BEXT BINV BSET" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0100100), Opcode{ .zbs = .BCLR } },
        .{ @as(u3, 0b101), @as(u7, 0b0100100), Opcode{ .zbs = .BEXT } },
        .{ @as(u3, 0b001), @as(u7, 0b0110100), Opcode{ .zbs = .BINV } },
        .{ @as(u3, 0b001), @as(u7, 0b0010100), Opcode{ .zbs = .BSET } },
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

test "decode Zbs I-type BCLRI BEXTI BINVI BSETI" {
    const cases = .{
        .{ @as(u3, 0b001), @as(u7, 0b0100100), Opcode{ .zbs = .BCLRI } },
        .{ @as(u3, 0b101), @as(u7, 0b0100100), Opcode{ .zbs = .BEXTI } },
        .{ @as(u3, 0b001), @as(u7, 0b0110100), Opcode{ .zbs = .BINVI } },
        .{ @as(u3, 0b001), @as(u7, 0b0010100), Opcode{ .zbs = .BSETI } },
    };
    inline for (cases) |c| {
        const raw = encodeIShamt(c[0], c[1], 4, 5, 3); // shamt=3
        const inst = try decode(raw);
        try std.testing.expectEqual(c[2], inst.op);
    }
}

// --- Execute tests ---

test "step: BCLR basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeR(0b001, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFDF), cpu.readReg(3)); // bit 5 cleared
}

test "step: BCLRI basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    loadInst(&cpu, encodeIShamt(0b001, 0b0100100, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(3)); // bit 0 cleared
}

test "step: BEXT basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000020);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeR(0b101, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // bit 5 is set
}

test "step: BEXT zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000020);
    cpu.writeReg(2, 4);
    loadInst(&cpu, encodeR(0b101, 0b0100100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3)); // bit 4 is not set
}

test "step: BEXTI basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    loadInst(&cpu, encodeIShamt(0b101, 0b0100100, 3, 1, 31));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // bit 31 is set
}

test "step: BINV basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeR(0b001, 0b0110100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000020), cpu.readReg(3)); // bit 5 inverted (0→1)
}

test "step: BINVI toggle" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000020);
    loadInst(&cpu, encodeIShamt(0b001, 0b0110100, 3, 1, 5));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000000), cpu.readReg(3)); // bit 5 inverted (1→0)
}

test "step: BSET basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeR(0b001, 0b0010100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x00000020), cpu.readReg(3)); // bit 5 set
}

test "step: BSETI basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x00000000);
    loadInst(&cpu, encodeIShamt(0b001, 0b0010100, 3, 1, 31));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3)); // bit 31 set
}
