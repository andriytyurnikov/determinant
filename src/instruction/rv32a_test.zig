const std = @import("std");
const instruction = @import("../instruction.zig");
const Opcode = instruction.Opcode;
const decoder = @import("../decoder.zig");
const decode = decoder.decode;
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("test_helpers.zig");

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
    try std.testing.expect(cpu.reservation_set);
    try std.testing.expectEqual(addr, cpu.reservation_addr);
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
    try std.testing.expect(!cpu.reservation_set);
}

test "step: SC.W failure clears reservation" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xDEADBEEF);
    cpu.writeReg(1, addr);

    // LR.W x3, (x1)
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    try std.testing.expect(cpu.reservation_set);

    // SC.W x4, x2, (x5) — different address → failure
    cpu.writeReg(5, 0x200);
    cpu.writeReg(2, 0xCAFEBABE);
    cpu.pc = 4;
    std.mem.writeInt(u32, cpu.memory[4..][0..4], encodeAtomic(0b00011, 4, 5, 2), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expect(!cpu.reservation_set); // reservation cleared even on failure
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

    // SW x2, 0(x1) — intervening store to same address
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

    // SC.W x4, x2, (x5) — different address
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
    try std.testing.expect(cpu.reservation_set);

    // AMOADD.W x6, x2, (x1) — intervening AMO to same address
    cpu.writeReg(2, 5);
    cpu.pc = 4;
    std.mem.writeInt(u32, cpu.memory[4..][0..4], encodeAtomic(0b00000, 6, 1, 2), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 15), readWordAt(&cpu, addr));
    try std.testing.expect(!cpu.reservation_set); // reservation invalidated by AMO

    // SC.W x4, x5, (x1) — should fail
    cpu.writeReg(5, 0xCAFEBABE);
    cpu.pc = 8;
    std.mem.writeInt(u32, cpu.memory[8..][0..4], encodeAtomic(0b00011, 4, 1, 5), .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 1), cpu.readReg(4)); // failure
    try std.testing.expectEqual(@as(u32, 15), readWordAt(&cpu, addr)); // unchanged
}

// --- AMO tests ---

test "step: AMOSWAP.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 42);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 99);
    loadInst(&cpu, encodeAtomic(0b00001, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(3)); // old value
    try std.testing.expectEqual(@as(u32, 99), readWordAt(&cpu, addr)); // new value
}

test "step: AMOADD.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 10);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 32);
    loadInst(&cpu, encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 42), readWordAt(&cpu, addr));
}

test "step: AMOXOR.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b00100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xF00FF00F), readWordAt(&cpu, addr));
}

test "step: AMOAND.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b01100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0x0F000F00), readWordAt(&cpu, addr));
}

test "step: AMOOR.W" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFF00FF00);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0x0F0F0F0F);
    loadInst(&cpu, encodeAtomic(0b01000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xFF0FFF0F), readWordAt(&cpu, addr));
}

test "step: AMOMIN.W signed" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 3), readWordAt(&cpu, addr));
}

test "step: AMOMIN.W with negative" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    const neg5: u32 = @bitCast(@as(i32, -5));
    storeWordAt(&cpu, addr, 3);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, neg5);
    loadInst(&cpu, encodeAtomic(0b10000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(3));
    try std.testing.expectEqual(neg5, readWordAt(&cpu, addr)); // -5 < 3
}

test "step: AMOMAX.W signed" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 5), readWordAt(&cpu, addr));
}

test "step: AMOMAX.W with negative" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    const neg5: u32 = @bitCast(@as(i32, -5));
    storeWordAt(&cpu, addr, neg5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 3);
    loadInst(&cpu, encodeAtomic(0b10100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(neg5, cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 3), readWordAt(&cpu, addr)); // 3 > -5
}

test "step: AMOMINU.W unsigned" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFFFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 5);
    loadInst(&cpu, encodeAtomic(0b11000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 5), readWordAt(&cpu, addr));
}

test "step: AMOMAXU.W unsigned" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 5);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 0xFFFFFFFF);
    loadInst(&cpu, encodeAtomic(0b11100, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), readWordAt(&cpu, addr));
}

test "step: atomic misaligned address" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0x101); // misaligned
    loadInst(&cpu, encodeAtomic(0b00010, 3, 1, 0)); // LR.W x3, (x1)
    try std.testing.expectError(error.MisalignedAccess, cpu.step());
}

test "step: AMOADD.W wrapping" {
    var cpu = Cpu.init();
    const addr: u32 = 0x100;
    storeWordAt(&cpu, addr, 0xFFFFFFFF);
    cpu.writeReg(1, addr);
    cpu.writeReg(2, 1);
    loadInst(&cpu, encodeAtomic(0b00000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), cpu.readReg(3));
    try std.testing.expectEqual(@as(u32, 0), readWordAt(&cpu, addr));
}
