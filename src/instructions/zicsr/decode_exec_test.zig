const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const h = @import("../test_helpers.zig");

const encodeCsr = h.encodeCsr;
const loadInst = h.loadInst;

// --- Decode tests ---

test "decode all 6 Zicsr funct3 values" {
    const cases = .{
        .{ @as(u3, 0b001), Opcode{ .csr = .CSRRW } },
        .{ @as(u3, 0b010), Opcode{ .csr = .CSRRS } },
        .{ @as(u3, 0b011), Opcode{ .csr = .CSRRC } },
        .{ @as(u3, 0b101), Opcode{ .csr = .CSRRWI } },
        .{ @as(u3, 0b110), Opcode{ .csr = .CSRRSI } },
        .{ @as(u3, 0b111), Opcode{ .csr = .CSRRCI } },
    };
    inline for (cases) |c| {
        const raw = encodeCsr(c[0], 5, 3, 0x340);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(u5, 5), inst.rd);
        try std.testing.expectEqual(@as(u5, 3), inst.rs1);
    }
}

test "decode funct3=0b000 still returns ECALL/EBREAK" {
    const ecall = try decode(0x00000073);
    try std.testing.expectEqual(Opcode{ .i = .ECALL }, ecall.op);
    const ebreak = try decode(0x00100073);
    try std.testing.expectEqual(Opcode{ .i = .EBREAK }, ebreak.op);
}

test "decode funct3=0b100 is illegal" {
    const raw = encodeCsr(0b100, 0, 0, 0);
    try std.testing.expectError(error.IllegalInstruction, decode(raw));
}

test "CSR address field extraction round-trip" {
    // CSR address 0xC00 = cycle (bits [31:20] of instruction word)
    const raw = encodeCsr(0b010, 1, 0, 0xC00); // CSRRS x1, 0xC00, x0
    const inst = try decode(raw);
    // immI sign-extends: 0xC00 in bits[31:20] -> sign-extended i32
    // csrAddr() truncates back to u12 to recover the original address
    try std.testing.expectEqual(@as(u12, 0xC00), inst.csrAddr());
}

// --- CSRRW execution tests ---

test "step: table (decode_exec)" {
    try h.expectSteps(&.{
        // CSRRW x2, 0x340, x1
        .{ .name = "CSRRW basic read-write to mscratch", .inst = encodeCsr(0b001, 2, 1, 0x340), .regs = &.{.{ 1, 0x11223344 }}, .mscratch = 0xAABBCCDD, .want = &.{.{ 2, 0xAABBCCDD }}, .want_mscratch = 0x11223344 },
        // CSRRW x0, 0x340, x1 -- write-only, no read
        .{ .name = "CSRRW with rd=x0 skips read", .inst = encodeCsr(0b001, 0, 1, 0x340), .regs = &.{.{ 1, 42 }}, .want_raw = &.{.{ 0, 0 }}, .want_mscratch = 42 },
        // CSRRS x2, 0x340, x1
        .{ .name = "CSRRS sets bits in mscratch", .inst = encodeCsr(0b010, 2, 1, 0x340), .regs = &.{.{ 1, 0x00FF }}, .mscratch = 0xFF00, .want = &.{.{ 2, 0xFF00 }}, .want_mscratch = 0xFFFF },
        // CSRRS x2, 0x340, x0 -- read-only, no write
        .{ .name = "CSRRS with rs1=x0 is read-only", .inst = encodeCsr(0b010, 2, 0, 0x340), .mscratch = 0xDEAD, .want = &.{.{ 2, 0xDEAD }}, .want_mscratch = 0xDEAD },
        // CSRRC x2, 0x340, x1
        .{ .name = "CSRRC clears bits in mscratch", .inst = encodeCsr(0b011, 2, 1, 0x340), .regs = &.{.{ 1, 0x0F0F }}, .mscratch = 0xFFFF, .want = &.{.{ 2, 0xFFFF }}, .want_mscratch = 0xF0F0 },
        // CSRRC x2, 0x340, x0
        .{ .name = "CSRRC with rs1=x0 is read-only", .inst = encodeCsr(0b011, 2, 0, 0x340), .mscratch = 0xBEEF, .want = &.{.{ 2, 0xBEEF }}, .want_mscratch = 0xBEEF },
        // CSRRWI x2, 0x340, 17 (zimm=17)
        .{ .name = "CSRRWI writes immediate", .inst = encodeCsr(0b101, 2, 17, 0x340), .mscratch = 0xAAAA, .want = &.{.{ 2, 0xAAAA }}, .want_mscratch = 17 },
        // CSRRWI x0, 0x340, 7
        .{ .name = "CSRRWI with rd=x0 skips read", .inst = encodeCsr(0b101, 0, 7, 0x340), .want_mscratch = 7 },
        // CSRRSI x2, 0x340, 0x0F (zimm=15)
        .{ .name = "CSRRSI sets bits with immediate", .inst = encodeCsr(0b110, 2, 15, 0x340), .mscratch = 0xF0, .want = &.{.{ 2, 0xF0 }}, .want_mscratch = 0xFF },
        // CSRRSI x2, 0x340, 0
        .{ .name = "CSRRSI with zimm=0 is read-only", .inst = encodeCsr(0b110, 2, 0, 0x340), .mscratch = 0x42, .want = &.{.{ 2, 0x42 }}, .want_mscratch = 0x42 },
        // CSRRCI x2, 0x340, 0x0F (zimm=15)
        .{ .name = "CSRRCI clears bits with immediate", .inst = encodeCsr(0b111, 2, 15, 0x340), .mscratch = 0xFF, .want = &.{.{ 2, 0xFF }}, .want_mscratch = 0xF0 },
        // CSRRCI x2, 0x340, 0
        .{ .name = "CSRRCI with zimm=0 is read-only", .inst = encodeCsr(0b111, 2, 0, 0x340), .mscratch = 0x99, .want = &.{.{ 2, 0x99 }}, .want_mscratch = 0x99 },
    });
}

// --- CSRRS execution tests ---

test "step: CSRRS with rs1=x0 succeeds on read-only CSR (cycle)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 12345;
    // CSRRS x3, 0xC00, x0 -- read cycle counter
    loadInst(&cpu, encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    // cycle_count was 12345 at read, then incremented to 12346 after step
    try std.testing.expectEqual(12345, cpu.readReg(3));
}
