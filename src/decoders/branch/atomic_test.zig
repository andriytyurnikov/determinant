/// Atomic (RV32A) round-trip tests.
const std = @import("std");
const t = @import("test_helpers.zig");
const Opcode = t.Opcode;
const decode = t.decode;
const h = t.h;

test "Atomic round-trip: all RV32A opcodes" {
    const cases = .{
        .{ @as(u5, 0b00010), Opcode{ .a = .LR_W } },
        .{ @as(u5, 0b00011), Opcode{ .a = .SC_W } },
        .{ @as(u5, 0b00001), Opcode{ .a = .AMOSWAP_W } },
        .{ @as(u5, 0b00000), Opcode{ .a = .AMOADD_W } },
        .{ @as(u5, 0b00100), Opcode{ .a = .AMOXOR_W } },
        .{ @as(u5, 0b01100), Opcode{ .a = .AMOAND_W } },
        .{ @as(u5, 0b01000), Opcode{ .a = .AMOOR_W } },
        .{ @as(u5, 0b10000), Opcode{ .a = .AMOMIN_W } },
        .{ @as(u5, 0b10100), Opcode{ .a = .AMOMAX_W } },
        .{ @as(u5, 0b11000), Opcode{ .a = .AMOMINU_W } },
        .{ @as(u5, 0b11100), Opcode{ .a = .AMOMAXU_W } },
    };
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    inline for (cases) |c| {
        for (test_regs) |rd_v| {
            for (test_regs) |rs1_v| {
                for (test_regs) |rs2_v| {
                    const raw = h.encodeAtomic(c[0], rd_v, rs1_v, rs2_v);
                    const inst = try decode(raw);
                    try std.testing.expectEqual(c[1], inst.op);
                    try std.testing.expectEqual(rd_v, inst.rd);
                    try std.testing.expectEqual(rs1_v, inst.rs1);
                    try std.testing.expectEqual(rs2_v, inst.rs2);
                }
            }
        }
    }
}
