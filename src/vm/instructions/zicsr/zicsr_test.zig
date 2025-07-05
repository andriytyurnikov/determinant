const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
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
    // immI sign-extends: 0xC00 in bits[31:20] → sign-extended i32
    // Truncating back to u12 should recover the original address
    const recovered: u12 = @truncate(@as(u32, @bitCast(inst.imm)));
    try std.testing.expectEqual(@as(u12, 0xC00), recovered);
}

// --- CSRRW execution tests ---

test "step: CSRRW basic read-write to mscratch" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xAABBCCDD;
    cpu.writeReg(1, 0x11223344); // rs1 = new value
    // CSRRW x2, 0x340, x1
    loadInst(&cpu, encodeCsr(0b001, 2, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), cpu.readReg(2)); // old value in rd
    try std.testing.expectEqual(@as(u32, 0x11223344), cpu.csrs.mscratch); // new value written
}

test "step: CSRRW with rd=x0 skips read" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    // CSRRW x0, 0x340, x1 — write-only, no read
    loadInst(&cpu, encodeCsr(0b001, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.csrs.mscratch);
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0)); // x0 still 0
}

// --- CSRRS execution tests ---

test "step: CSRRS sets bits in mscratch" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xFF00;
    cpu.writeReg(1, 0x00FF);
    // CSRRS x2, 0x340, x1
    loadInst(&cpu, encodeCsr(0b010, 2, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00), cpu.readReg(2)); // old value
    try std.testing.expectEqual(@as(u32, 0xFFFF), cpu.csrs.mscratch); // OR'd
}

test "step: CSRRS with rs1=x0 is read-only" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xDEAD;
    // CSRRS x2, 0x340, x0 — read-only, no write
    loadInst(&cpu, encodeCsr(0b010, 2, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEAD), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0xDEAD), cpu.csrs.mscratch); // unchanged
}

test "step: CSRRS with rs1=x0 succeeds on read-only CSR (cycle)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 12345;
    // CSRRS x3, 0xC00, x0 — read cycle counter
    loadInst(&cpu, encodeCsr(0b010, 3, 0, 0xC00));
    _ = try cpu.step();
    // cycle_count was 12345 at read, then incremented to 12346 after step
    try std.testing.expectEqual(@as(u32, 12345), cpu.readReg(3));
}

// --- CSRRC execution tests ---

test "step: CSRRC clears bits in mscratch" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xFFFF;
    cpu.writeReg(1, 0x0F0F);
    // CSRRC x2, 0x340, x1
    loadInst(&cpu, encodeCsr(0b011, 2, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFF), cpu.readReg(2)); // old value
    try std.testing.expectEqual(@as(u32, 0xF0F0), cpu.csrs.mscratch); // cleared
}

test "step: CSRRC with rs1=x0 is read-only" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xBEEF;
    // CSRRC x2, 0x340, x0
    loadInst(&cpu, encodeCsr(0b011, 2, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xBEEF), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0xBEEF), cpu.csrs.mscratch); // unchanged
}

// --- CSRRWI execution tests ---

test "step: CSRRWI writes immediate" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xAAAA;
    // CSRRWI x2, 0x340, 17 (zimm=17)
    loadInst(&cpu, encodeCsr(0b101, 2, 17, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 17), cpu.csrs.mscratch);
}

test "step: CSRRWI with rd=x0 skips read" {
    var cpu = Cpu.init();
    // CSRRWI x0, 0x340, 7
    loadInst(&cpu, encodeCsr(0b101, 0, 7, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 7), cpu.csrs.mscratch);
}

// --- CSRRSI execution tests ---

test "step: CSRRSI sets bits with immediate" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xF0;
    // CSRRSI x2, 0x340, 0x0F (zimm=15)
    loadInst(&cpu, encodeCsr(0b110, 2, 15, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.csrs.mscratch);
}

test "step: CSRRSI with zimm=0 is read-only" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0x42;
    // CSRRSI x2, 0x340, 0
    loadInst(&cpu, encodeCsr(0b110, 2, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x42), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0x42), cpu.csrs.mscratch); // unchanged
}

// --- CSRRCI execution tests ---

test "step: CSRRCI clears bits with immediate" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xFF;
    // CSRRCI x2, 0x340, 0x0F (zimm=15)
    loadInst(&cpu, encodeCsr(0b111, 2, 15, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.csrs.mscratch);
}

test "step: CSRRCI with zimm=0 is read-only" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0x99;
    // CSRRCI x2, 0x340, 0
    loadInst(&cpu, encodeCsr(0b111, 2, 0, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0x99), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 0x99), cpu.csrs.mscratch); // unchanged
}

// --- Performance counter tests ---

test "step: read cycle counter (0xC00)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0001_FFFF_FFFE;
    // CSRRS x1, 0xC00, x0 — read cycle low 32
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), cpu.readReg(1));
}

test "step: read cycleh (0xC80)" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0005_0000_0000;
    // CSRRS x1, 0xC80, x0 — read cycle high 32
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC80));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
}

test "step: read instret (0xC02) same as cycle" {
    var cpu = Cpu.init();
    cpu.cycle_count = 999;
    // CSRRS x1, 0xC02, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC02));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 999), cpu.readReg(1));
}

test "step: read instreth (0xC82) same as cycleh" {
    var cpu = Cpu.init();
    cpu.cycle_count = 0x0000_0003_0000_0000;
    // CSRRS x1, 0xC82, x0
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC82));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(1));
}

// --- Error tests ---

test "step: write to read-only CSR (cycle) is illegal" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 42);
    // CSRRW x2, 0xC00, x1 — attempt to write cycle counter
    loadInst(&cpu, encodeCsr(0b001, 2, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRS to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 77;
    // CSRRS x1, 0xC00, x0 — read-only access to read-only CSR is fine
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 77), cpu.readReg(1));
}

test "step: CSRRC to read-only CSR with rs1=x0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 88;
    // CSRRC x1, 0xC00, x0
    loadInst(&cpu, encodeCsr(0b011, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 88), cpu.readReg(1));
}

test "step: CSRRSI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 55;
    // CSRRSI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b110, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 55), cpu.readReg(1));
}

test "step: CSRRCI to read-only CSR with zimm=0 succeeds" {
    var cpu = Cpu.init();
    cpu.cycle_count = 66;
    // CSRRCI x1, 0xC00, 0
    loadInst(&cpu, encodeCsr(0b111, 1, 0, 0xC00));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 66), cpu.readReg(1));
}

test "step: unknown CSR address is illegal" {
    var cpu = Cpu.init();
    // CSRRS x1, 0x001, x0 — unknown CSR
    loadInst(&cpu, encodeCsr(0b010, 1, 0, 0x001));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRS with rs1!=x0 to read-only CSR is illegal" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0);
    // CSRRS x2, 0xC00, x1 — rs1!=x0, attempts write to read-only
    loadInst(&cpu, encodeCsr(0b010, 2, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRWI with rd=x0 to read-only CSR still fails (write attempted)" {
    var cpu = Cpu.init();
    // CSRRWI x0, 0xC00, 5 — rd=x0 skips read, but write still attempted
    loadInst(&cpu, encodeCsr(0b101, 0, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRCI with zimm!=0 to read-only CSR fails" {
    var cpu = Cpu.init();
    // CSRRCI x2, 0xC00, 5 — zimm=5 (!=0), attempts clear on read-only CSR
    loadInst(&cpu, encodeCsr(0b111, 2, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRW x0 to read-only CSR still fails (write attempted)" {
    var cpu = Cpu.init();
    // CSRRW x0, 0xC00, x1 — rd=x0, but write still attempted
    cpu.writeReg(1, 42);
    loadInst(&cpu, encodeCsr(0b001, 0, 1, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}

test "step: CSRRSI with zimm!=0 to read-only CSR fails" {
    var cpu = Cpu.init();
    // CSRRSI x2, 0xC00, 5 — zimm=5 (!=0), attempts set on read-only CSR
    loadInst(&cpu, encodeCsr(0b110, 2, 5, 0xC00));
    try std.testing.expectError(error.IllegalInstruction, cpu.step());
}
