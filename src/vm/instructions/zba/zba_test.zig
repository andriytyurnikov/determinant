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

// --- Decode tests ---

test "decode Zba SH1ADD SH2ADD SH3ADD" {
    const cases = .{
        .{ @as(u3, 0b010), Opcode{ .zba = .SH1ADD } },
        .{ @as(u3, 0b100), Opcode{ .zba = .SH2ADD } },
        .{ @as(u3, 0b110), Opcode{ .zba = .SH3ADD } },
    };
    inline for (cases) |c| {
        const raw = encodeR(c[0], 0b0010000, 4, 5, 6);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(u5, 4), inst.rd);
        try std.testing.expectEqual(@as(u5, 5), inst.rs1);
        try std.testing.expectEqual(@as(u5, 6), inst.rs2);
    }
}

// --- Execute tests ---

test "step: SH1ADD basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    loadInst(&cpu, encodeR(0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 110), cpu.readReg(3)); // (5 << 1) + 100
}

test "step: SH2ADD basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    loadInst(&cpu, encodeR(0b100, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 120), cpu.readReg(3)); // (5 << 2) + 100
}

test "step: SH3ADD basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 5);
    cpu.writeReg(2, 100);
    loadInst(&cpu, encodeR(0b110, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 140), cpu.readReg(3)); // (5 << 3) + 100
}

test "step: SH1ADD wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // (0x80000000 << 1) +% 1 = 1
}

test "step: SH2ADD wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xC0000000);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b100, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // (0xC0000000 << 2) +% 1 = 1
}

test "step: SH3ADD wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xE0000000);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b110, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3)); // (0xE0000000 << 3) +% 1 = 1
}

test "step: SH1ADD double-wrapping both operands near max" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    // (0xFFFFFFFF << 1) +% 0xFFFFFFFF = 0xFFFFFFFE +% 0xFFFFFFFF = 0xFFFFFFFD
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFD), cpu.readReg(3));
}

test "step: SH3ADD double-wrapping both operands near max" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b110, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    // (0xFFFFFFFF << 3) +% 0xFFFFFFFF = 0xFFFFFFF8 +% 0xFFFFFFFF = 0xFFFFFFF7
    try std.testing.expectEqual(@as(u32, 0xFFFFFFF7), cpu.readReg(3));
}

test "step: SH2ADD double-wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b100, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    // (0xFFFFFFFF << 2) +% 0xFFFFFFFF = 0xFFFFFFFC +% 0xFFFFFFFF = 0xFFFFFFFB
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFB), cpu.readReg(3));
}

// --- Boundary-value tests ---

test "step: SH1ADD zero rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b010, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // (0 << 1) + 42 = 42
}

test "step: SH2ADD zero rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b100, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // (0 << 2) + 42 = 42
}

test "step: SH3ADD zero rs1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    cpu.writeReg(2, 42);
    loadInst(&cpu, encodeR(0b110, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // (0 << 3) + 42 = 42
}
