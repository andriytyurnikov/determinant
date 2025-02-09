const std = @import("std");
const instruction = @import("../instruction.zig");
const Opcode = instruction.Opcode;
const decoder = @import("../decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;

// --- Helpers ---

fn encodeR(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, 0b0110011) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

fn loadInst(cpu: *Cpu, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[cpu.pc..][0..4], word, .little);
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

// --- Execute tests ---

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

test "step: MULHU unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b011, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(3));
}

test "step: DIV basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: DIV signed negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -20))));
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -3))), cpu.readReg(3));
}

test "step: DIV by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: DIV overflow INT_MIN / -1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b100, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), cpu.readReg(3));
}

test "step: DIVU basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
}

test "step: DIVU by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
}

test "step: DIVU large unsigned" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 2);
    loadInst(&cpu, encodeR(0b101, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x7FFFFFFF), cpu.readReg(3));
}

test "step: REM basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(3));
}

test "step: REM signed negative" {
    var cpu = Cpu.init();
    cpu.writeReg(1, @as(u32, @bitCast(@as(i32, -20))));
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -2))), cpu.readReg(3));
}

test "step: REM by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}

test "step: REM overflow INT_MIN / -1" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x80000000);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeR(0b110, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3));
}

test "step: REMU basic" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 20);
    cpu.writeReg(2, 6);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(3));
}

test "step: REMU by zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    cpu.writeReg(2, 0);
    loadInst(&cpu, encodeR(0b111, 0b0000001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3));
}
