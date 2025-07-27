const std = @import("std");
const instructions = @import("../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../decoders/branch_decoder/branch_decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../test_helpers.zig");

const encodeAtomic = h.encodeAtomic;
const loadInst = h.loadInst;
const storeWordAt = h.storeWordAt;
const readWordAt = h.readWordAt;

// --- Decode tests ---

test "decode all RV32A opcodes" {
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
    inline for (cases) |c| {
        const raw = encodeAtomic(c[0], 4, 5, 6);
        const inst = try decode(raw);
        try std.testing.expectEqual(c[1], inst.op);
        try std.testing.expectEqual(@as(u5, 4), inst.rd);
        try std.testing.expectEqual(@as(u5, 5), inst.rs1);
        try std.testing.expectEqual(@as(u5, 6), inst.rs2);
    }
}

test "decode RV32A with aq/rl bits set" {
    // aq=1, rl=1 should still decode correctly
    const funct5: u5 = 0b00001; // AMOSWAP
    const f7: u7 = (@as(u7, funct5) << 2) | 0b11;
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 4) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, 5) << 15) |
        (@as(u32, 6) << 20) |
        (@as(u32, f7) << 25);
    const inst = try decode(raw);
    try std.testing.expectEqual(Opcode{ .a = .AMOSWAP_W }, inst.op);
}

test "decode RV32A invalid funct5" {
    const raw = encodeAtomic(0b11111, 4, 5, 6);
    try std.testing.expectError(error.IllegalInstruction, decode(raw));
}

test "decode RV32A invalid funct3" {
    // funct3 = 001 instead of 010
    const f7: u7 = @as(u7, 0b00001) << 2;
    const raw = @as(u32, 0b0101111) |
        (@as(u32, 4) << 7) |
        (@as(u32, 0b001) << 12) |
        (@as(u32, 5) << 15) |
        (@as(u32, 6) << 20) |
        (@as(u32, f7) << 25);
    try std.testing.expectError(error.IllegalInstruction, decode(raw));
}

// --- LR.W / SC.W tests ---

test "step: LR.W loads word and sets reservation" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr); // rs1 = address
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.readReg(3));
    try std.testing.expectEqual(@as(?u32, addr), cpu.reservation);
}

test "step: SC.W succeeds after LR.W to same address" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x1)
    cpu.writeReg(2, 0xCAFEBABE);
    cpu.pc = 4;
    loadInst(&cpu, encodeAtomic(0b00011, 4, 1, 2));
    _ = try cpu.step();

    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(4)); // success
    try std.testing.expectEqual(@as(u32, 0xCAFEBABE), readWordAt(&cpu, addr));
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation);
}

test "step: SC.W failure clears reservation" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expect(cpu.reservation != null);

    // SC.W x4, x2, (x5) -- different address -> failure
    cpu.writeReg(5, 0x200);
    cpu.writeReg(2, 0xCAFEBABE);
    cpu.pc = 4;
    std.mem.writeInt(u32, cpu.memory[4..][0..4], encodeAtomic(0b00011, 4, 5, 2), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation); // reservation cleared even on failure
}

test "step: SC.W fails without prior LR.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0xCAFEBABE);
    loadInst(&cpu, encodeAtomic(0b00011, 4, 1, 2)); // SC.W x4, x2, (x1)
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), readWordAt(&cpu, addr)); // unchanged
}

test "step: SC.W fails after intervening store" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SW x2, 0(x1) -- intervening store to same address
    cpu.writeReg(2, 0x11111111);
    cpu.pc = 4;
    // Encode SW: opcode=0100011, funct3=010, rs1=1, rs2=2, imm=0
    const sw_inst: u32 = 0b0100011 | (@as(u32, 0b010) << 12) | (@as(u32, 1) << 15) | (@as(u32, 2) << 20);
    std.mem.writeInt(u32, cpu.memory[4..][0..4], sw_inst, .little);
    _ = try cpu.step();

    // SC.W x4, x5, (x1)
    cpu.writeReg(5, 0xCAFEBABE);
    cpu.pc = 8;
    std.mem.writeInt(u32, cpu.memory[8..][0..4], encodeAtomic(0b00011, 4, 1, 5), .little);
    _ = try cpu.step();

    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
}

test "step: SC.W fails when address differs from LR.W" {
    var cpu = Cpu.init();
    const lr_addr: u32 = 0x100;
    const sc_addr: u32 = 0x200;
    storeWordAt(&cpu, lr_addr, 0xDEADBEEF);
    storeWordAt(&cpu, sc_addr, 0x12345678);
    cpu.writeReg(1, lr_addr);
    cpu.writeReg(5, sc_addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();

    // SC.W x4, x2, (x5) -- different address
    cpu.writeReg(2, 0xCAFEBABE);
    cpu.pc = 4;
    std.mem.writeInt(u32, cpu.memory[4..][0..4], encodeAtomic(0b00011, 4, 5, 2), .little);
    _ = try cpu.step();

    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 0x12345678), readWordAt(&cpu, sc_addr)); // unchanged
}

test "step: SC.W fails after intervening AMO to same address" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 10);
    cpu.writeReg(1, addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expect(cpu.reservation != null);

    // AMOADD.W x6, x2, (x1) -- intervening AMO to same address
    cpu.writeReg(2, 5);
    cpu.pc = 4;
    std.mem.writeInt(u32, cpu.memory[4..][0..4], encodeAtomic(0b00000, 6, 1, 2), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 15), readWordAt(&cpu, addr));
    try std.testing.expectEqual(@as(?u32, null), cpu.reservation); // reservation invalidated by AMO

    // SC.W x4, x5, (x1) -- should fail
    cpu.writeReg(5, 0xCAFEBABE);
    cpu.pc = 8;
    std.mem.writeInt(u32, cpu.memory[8..][0..4], encodeAtomic(0b00011, 4, 1, 5), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 15), readWordAt(&cpu, addr)); // unchanged
}
