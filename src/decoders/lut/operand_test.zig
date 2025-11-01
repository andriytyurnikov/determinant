const std = @import("std");
const h = @import("test_helpers.zig");
const Opcode = h.Opcode;

// --- R-format ---

test "R-format: ADD x7, x15, x20" {
    const raw = h.encodeRBase(0b000, 0b0000000, 7, 15, 20);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .ADD }, inst.op);
    try std.testing.expectEqual(@as(u5, 7), inst.rd);
    try std.testing.expectEqual(@as(u5, 15), inst.rs1);
    try std.testing.expectEqual(@as(u5, 20), inst.rs2);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

// --- I-format (non-shift) ---

test "I-format: ADDI x5, x10, -1" {
    const raw = h.encodeI(0b0010011, 0b000, 5, 10, 0xFFF);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 5), inst.rd);
    try std.testing.expectEqual(@as(u5, 10), inst.rs1);
    try std.testing.expectEqual(@as(i32, -1), inst.imm);
}

// --- I-format (shift) ---

test "I-format shift: SLLI x3, x7, 17" {
    const raw = h.encodeI(0b0010011, 0b001, 3, 7, 17);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .SLLI }, inst.op);
    try std.testing.expectEqual(@as(u5, 3), inst.rd);
    try std.testing.expectEqual(@as(u5, 7), inst.rs1);
    try std.testing.expectEqual(@as(i32, 17), inst.imm);
}

// --- I-format (load) ---

test "I-format load: LW x4, -100(x8)" {
    const raw = h.encodeLoad(0b010, 4, 8, @bitCast(@as(i12, -100)));
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .LW }, inst.op);
    try std.testing.expectEqual(@as(u5, 4), inst.rd);
    try std.testing.expectEqual(@as(u5, 8), inst.rs1);
    try std.testing.expectEqual(@as(i32, -100), inst.imm);
}

// --- S-format ---

test "S-format: SW x9, -1(x3)" {
    const raw = h.encodeStore(0b010, 3, 9, 0xFFF);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .SW }, inst.op);
    try std.testing.expectEqual(@as(u5, 3), inst.rs1);
    try std.testing.expectEqual(@as(u5, 9), inst.rs2);
    try std.testing.expectEqual(@as(i32, -1), inst.imm);
}

// --- B-format ---

test "B-format: BEQ x5, x12, -128" {
    const raw = h.encodeBranchFull(0b000, 5, 12, -128);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .BEQ }, inst.op);
    try std.testing.expectEqual(@as(u5, 5), inst.rs1);
    try std.testing.expectEqual(@as(u5, 12), inst.rs2);
    try std.testing.expectEqual(@as(i32, -128), inst.imm);
}

// --- U-format ---

test "U-format: LUI x8, 0xDEADB" {
    const raw = h.encodeU(0b0110111, 8, 0xDEADB);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .LUI }, inst.op);
    try std.testing.expectEqual(@as(u5, 8), inst.rd);
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0xDEADB000))), inst.imm);
}

// --- J-format ---

test "J-format: JAL x1, -2" {
    const raw = h.encodeJFull(1, -2);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .JAL }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(i32, -2), inst.imm);
}

// --- Specials ---

test "Special: ECALL" {
    const raw = h.encodeSystem(0b000, 0, 0, 0x000);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .ECALL }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(u5, 0), inst.rs2);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

test "Special: FENCE" {
    const raw = h.encodeFence();
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .FENCE }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
    try std.testing.expectEqual(@as(u5, 0), inst.rs1);
    try std.testing.expectEqual(@as(u5, 0), inst.rs2);
    try std.testing.expectEqual(@as(i32, 0), inst.imm);
}

// --- JALR ---

test "I-format: JALR x1, x10, 200" {
    const raw = h.encodeJalr(1, 10, 200);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .i = .JALR }, inst.op);
    try std.testing.expectEqual(@as(u5, 1), inst.rd);
    try std.testing.expectEqual(@as(u5, 10), inst.rs1);
    try std.testing.expectEqual(@as(i32, 200), inst.imm);
}

// --- CSR ---

test "I-format CSR: CSRRW x5, 0x340, x10" {
    const raw = h.encodeSystem(0b001, 5, 10, 0x340);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .csr = .CSRRW }, inst.op);
    try std.testing.expectEqual(@as(u5, 5), inst.rd);
    try std.testing.expectEqual(@as(u5, 10), inst.rs1);
    try std.testing.expectEqual(@as(i32, 0x340), inst.imm);
}

// --- Atomic ---

test "R-format atomic: AMOADD.W x3, x5, (x8)" {
    const raw = h.encodeAtomic(0b00000, 3, 8, 5);
    const inst = try h.decodeFull(raw);
    try std.testing.expectEqual(Opcode{ .a = .AMOADD_W }, inst.op);
    try std.testing.expectEqual(@as(u5, 3), inst.rd);
    try std.testing.expectEqual(@as(u5, 8), inst.rs1);
    try std.testing.expectEqual(@as(u5, 5), inst.rs2);
}
