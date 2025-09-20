/// U/J-type + Atomic + CSR + FENCE round-trip tests.
const std = @import("std");
const decoder = @import("../branch.zig");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const h = @import("../../instructions/test_helpers.zig");

// --- U-type round-trip ---

test "U-type round-trip: LUI" {
    try expectRoundTripU(0b0110111, .{ .i = .LUI });
}

test "U-type round-trip: AUIPC" {
    try expectRoundTripU(0b0010111, .{ .i = .AUIPC });
}

fn expectRoundTripU(opcode: u7, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_imms = [_]u20{ 0, 1, 0x7FFFF, 0x80000, 0xFFFFF };
    for (test_regs) |rd_v| {
        for (test_imms) |imm20| {
            const raw = h.encodeU(opcode, rd_v, imm20);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(expected_op, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            // U-type immediate is stored as the upper 20 bits (shifted left 12)
            const expected_imm: i32 = @bitCast(@as(u32, imm20) << 12);
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

// --- J-type round-trip ---

test "J-type round-trip: JAL" {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    // J-type immediates have bit 0 always 0, range ±1 MiB (21-bit signed, even)
    const test_imms = [_]i21{ 0, 2, 4, -2, -4, 0x7FE, -0x100000, 0xFFFFE };
    for (test_regs) |rd_v| {
        for (test_imms) |imm_val| {
            const raw = h.encodeJ(rd_v, imm_val);
            const inst = try decoder.decode(raw);
            try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
            try std.testing.expectEqual(rd_v, inst.rd);
            const expected_imm: i32 = imm_val;
            try std.testing.expectEqual(expected_imm, inst.imm);
        }
    }
}

// --- Atomic round-trip ---

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
                    const inst = try decoder.decode(raw);
                    try std.testing.expectEqual(c[1], inst.op);
                    try std.testing.expectEqual(rd_v, inst.rd);
                    try std.testing.expectEqual(rs1_v, inst.rs1);
                    try std.testing.expectEqual(rs2_v, inst.rs2);
                }
            }
        }
    }
}

// --- CSR round-trip ---

test "CSR round-trip: CSRRW" {
    try expectRoundTripCsr(0b001, .{ .csr = .CSRRW });
}

test "CSR round-trip: CSRRS" {
    try expectRoundTripCsr(0b010, .{ .csr = .CSRRS });
}

test "CSR round-trip: CSRRC" {
    try expectRoundTripCsr(0b011, .{ .csr = .CSRRC });
}

test "CSR round-trip: CSRRWI" {
    try expectRoundTripCsr(0b101, .{ .csr = .CSRRWI });
}

test "CSR round-trip: CSRRSI" {
    try expectRoundTripCsr(0b110, .{ .csr = .CSRRSI });
}

test "CSR round-trip: CSRRCI" {
    try expectRoundTripCsr(0b111, .{ .csr = .CSRRCI });
}

fn expectRoundTripCsr(f3: u3, expected_op: Opcode) !void {
    const test_regs = [_]u5{ 0, 1, 15, 31 };
    const test_addrs = [_]u12{ 0x000, 0xC00, 0xC80, 0x340, 0xFFF };
    for (test_regs) |rd_v| {
        for (test_regs) |rs1_v| {
            for (test_addrs) |csr_addr| {
                const raw = h.encodeCsr(f3, rd_v, rs1_v, csr_addr);
                const inst = try decoder.decode(raw);
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

// --- FENCE ---

test "FENCE round-trip" {
    // Standard FENCE iorw,iorw = 0x0FF0000F
    const inst = try decoder.decode(0x0FF0000F);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
}

test "FENCE.I round-trip" {
    // opcode=0b0001111, funct3=001 (Zifencei)
    const raw: u32 = (0b001 << 12) | 0b0001111;
    const inst = try decoder.decode(raw);
    try std.testing.expectEqual(Opcode{ .i = .FENCE_I }, inst.op);
}

test "FENCE with invalid funct3 is illegal" {
    // opcode=0b0001111, funct3=010 (undefined)
    const raw: u32 = (0b010 << 12) | 0b0001111;
    try std.testing.expectError(error.IllegalInstruction, decoder.decode(raw));
}
