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

// --- Decode tests ---

test "decode R-type M-extension MUL MULH MULHSU MULHU DIV DIVU REM REMU" {
    const cases = .{
        .{ @as(u3, 0b000), @as(u7, 0b0000001), Opcode{ .m = .MUL } },
        .{ @as(u3, 0b001), @as(u7, 0b0000001), Opcode{ .m = .MULH } },
        .{ @as(u3, 0b010), @as(u7, 0b0000001), Opcode{ .m = .MULHSU } },
        .{ @as(u3, 0b011), @as(u7, 0b0000001), Opcode{ .m = .MULHU } },
        .{ @as(u3, 0b100), @as(u7, 0b0000001), Opcode{ .m = .DIV } },
        .{ @as(u3, 0b101), @as(u7, 0b0000001), Opcode{ .m = .DIVU } },
        .{ @as(u3, 0b110), @as(u7, 0b0000001), Opcode{ .m = .REM } },
        .{ @as(u3, 0b111), @as(u7, 0b0000001), Opcode{ .m = .REMU } },
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

// --- MUL execute tests ---

test "step: MUL basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 7);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: MUL wrapping" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 2);
    loadInst(&cpu, encodeR(0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: MUL by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 12345);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b000, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

// --- MULH execute tests ---

test "step: MULH signed positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x10000);
    cpu.writeReg(2, 0x10000);
    loadInst(&cpu, encodeR(0b001, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

test "step: MULH signed negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b001, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: MULH large negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b001, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

// --- MULHSU execute tests ---

test "step: MULHSU signed*unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 2);
    loadInst(&cpu, encodeR(0b010, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: MULHSU positive" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x10000);
    cpu.writeReg(2, 0x10000);
    loadInst(&cpu, encodeR(0b010, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(3));
}

// --- MULHU execute tests ---

test "step: MULHU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b011, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(3));
}

test "step: MULHU with zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b011, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

// --- Multiply boundary-value tests ---

test "step: MULH SIGNED_MIN * SIGNED_MIN" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0x80000000);
    loadInst(&cpu, encodeR(0b001, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    // (-2^31) * (-2^31) = 2^62 = 0x4000000000000000, upper 32 = 0x40000000
    try std.testing.expectEqual(@as(u32, 0x40000000), cpu.readReg(3));
}

test "step: MULHSU SIGNED_MIN * unsigned max" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000); // -2^31 (signed)
    cpu.writeReg(2, 0xFFFFFFFF); // 2^32-1 (unsigned)
    loadInst(&cpu, encodeR(0b010, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    // (-2^31) * (2^32-1) = -9223372034707292160, as u64 = 0x8000000080000000
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: MULHU max times one" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeR(0b011, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3)); // upper 32 of 0xFFFFFFFF * 1 = 0
}
