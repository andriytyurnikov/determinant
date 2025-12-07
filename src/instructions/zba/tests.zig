const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
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

test "step: SH1ADD/SH2ADD/SH3ADD zero rs2 is pure shift" {
    const cases = .{
        .{ @as(u3, 0b010), @as(u32, 84) }, // SH1ADD: 42 << 1 = 84
        .{ @as(u3, 0b100), @as(u32, 168) }, // SH2ADD: 42 << 2 = 168
        .{ @as(u3, 0b110), @as(u32, 336) }, // SH3ADD: 42 << 3 = 336
    };
    inline for (cases) |c| {
        var cpu = Cpu.init();
        cpu.writeReg(1, 42);
        cpu.writeReg(2, 0);
        loadInst(&cpu, encodeR(c[0], 0b0010000, 3, 1, 2));
        _ = try cpu.step();
        try std.testing.expectEqual(c[1], cpu.readReg(3));
    }
}

test "step: SH1ADD/SH2ADD/SH3ADD both operands zero" {
    const funct3s = [_]u3{ 0b010, 0b100, 0b110 };
    inline for (funct3s) |f3| {
        var cpu = Cpu.init();
        // x1 and x2 are already 0 after init
        loadInst(&cpu, encodeR(f3, 0b0010000, 3, 1, 2));
        _ = try cpu.step();
        try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
    }
}

test "step: SH1ADD/SH2ADD/SH3ADD equal operands give multiplier" {
    const cases = .{
        .{ @as(u3, 0b010), @as(u32, 21) }, // SH1ADD(7,7) = 14+7 = 21 = 7*3
        .{ @as(u3, 0b100), @as(u32, 35) }, // SH2ADD(7,7) = 28+7 = 35 = 7*5
        .{ @as(u3, 0b110), @as(u32, 63) }, // SH3ADD(7,7) = 56+7 = 63 = 7*9
    };
    inline for (cases) |c| {
        var cpu = Cpu.init();
        cpu.writeReg(1, 7);
        cpu.writeReg(2, 7);
        loadInst(&cpu, encodeR(c[0], 0b0010000, 3, 1, 2));
        _ = try cpu.step();
        try std.testing.expectEqual(c[1], cpu.readReg(3));
    }
}

test "step: SH1ADD rd equals rs1 overwrites correctly" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 10);
    cpu.writeReg(2, 5);
    // SH1ADD x1, x1, x2 → x1 = (10 << 1) + 5 = 25
    loadInst(&cpu, encodeR(0b010, 0b0010000, 1, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 25), cpu.readReg(1));
}

test "step: SH2ADD rd equals rs2 overwrites correctly" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 3);
    cpu.writeReg(2, 100);
    // SH2ADD x2, x1, x2 → x2 = (3 << 2) + 100 = 112
    loadInst(&cpu, encodeR(0b100, 0b0010000, 2, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 112), cpu.readReg(2));
}

test "step: SH3ADD rs1 equals rs2 same register" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 4);
    // SH3ADD x2, x1, x1 → x2 = (4 << 3) + 4 = 36
    loadInst(&cpu, encodeR(0b110, 0b0010000, 2, 1, 1));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 36), cpu.readReg(2));
}

test "step: SH1ADD/SH2ADD/SH3ADD sign-bit rs2 wraps" {
    const cases = .{
        .{ @as(u3, 0b010), @as(u32, 0x80000002) }, // (1 << 1) + 0x80000000
        .{ @as(u3, 0b100), @as(u32, 0x80000004) }, // (1 << 2) + 0x80000000
        .{ @as(u3, 0b110), @as(u32, 0x80000008) }, // (1 << 3) + 0x80000000
    };
    inline for (cases) |c| {
        var cpu = Cpu.init();
        cpu.writeReg(1, 1);
        cpu.writeReg(2, 0x80000000);
        loadInst(&cpu, encodeR(c[0], 0b0010000, 3, 1, 2));
        _ = try cpu.step();
        try std.testing.expectEqual(c[1], cpu.readReg(3));
    }
}

test "step: SH2ADD realistic array indexing pattern" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 10); // index
    cpu.writeReg(2, 0x1000); // base address
    // SH2ADD x3, x1, x2 → x3 = (10 << 2) + 0x1000 = 40 + 4096 = 0x1028
    loadInst(&cpu, encodeR(0b100, 0b0010000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x1028), cpu.readReg(3));
}
