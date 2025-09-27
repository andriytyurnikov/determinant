/// Shared test helpers for branch decoder round-trip tests.
pub const std = @import("std");
const decoder = @import("../branch.zig");
const instructions = @import("../../instructions.zig");
pub const Opcode = instructions.Opcode;
pub const h = @import("../../instructions/test_helpers.zig");

pub const decode = decoder.decode;

pub fn expectRoundTripI(opcode: u7, f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // Test various immediate values including sign-extension boundary cases
    const test_imms = [_]u12{ 0, 1, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeI(opcode, f3, rd_v, rs1_v, imm12);
                const inst = try decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                // Verify immediate: sign-extend u12 → i32
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

pub fn expectRoundTripS(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u12{ 0, 1, 0x1F, 0x7E0, 0x7FF, 0x800, 0xFFF };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm12| {
                const raw = h.encodeS(f3, rs1_v, rs2_v, imm12);
                const inst = try decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = @as(i12, @bitCast(imm12));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

pub fn expectRoundTripB(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // B-type immediates have bit 0 always 0, range -4096..4094 (13-bit signed, even)
    const test_imms = [_]i13{ 0, 2, 4, -2, -4, 0x7FE, -0x1000, 0xE };
    for (test_regs) |rs1_v| {
        for (test_regs) |rs2_v| {
            for (test_imms) |imm_val| {
                const raw = h.encodeB(f3, rs1_v, rs2_v, imm_val);
                const inst = try decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                try std.testing.expectEqual(rs2_v, inst.rs2);
                const expected_imm: i32 = imm_val;
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}

pub fn expectRoundTripU(opcode: u7, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u20{ 0, 1, 0x7FFFF, 0x80000, 0xFFFFF };
    for (test_regs) |rd_v| {
        for (test_imms) |imm20| {
            const raw = h.encodeU(opcode, rd_v, imm20);
            const inst = try decode(raw);
            try std.testing.expectEqual(expected_op, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            // U-type immediate is stored as the upper 20 bits (shifted left 12)
            const expected_imm: i32 = @bitCast(@as(u32, imm20) << 12);
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

pub fn expectRoundTripCsr(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_addrs = [_]u12{ 0x000, 0xC00, 0xC80, 0x340, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_addrs) |csr_addr| {
                const raw = h.encodeCsr(f3, rd_v, rs1_v, csr_addr);
                const inst = try decode(raw);
                try std.testing.expectEqual(expected_op, inst.op);
                try std.testing.expectEqual(rd_v, inst.rd);
                try std.testing.expectEqual(rs1_v, inst.rs1);
                // CSR address is in upper 12 bits, decoded as sign-extended I-type immediate
                const expected_imm: i32 = @as(i12, @bitCast(csr_addr));
                try std.testing.expectEqual(expected_imm, inst.imm);
            }
        }
    }
}
