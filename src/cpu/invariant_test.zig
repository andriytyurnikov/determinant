const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../instructions/test_helpers.zig");

// --- Combined invariant tests ---

test "step: LB x0 with sign-extension — x0 stays zero" {
    var cpu = Cpu.init();
    // Store 0x80 at address 256 (high bit set → sign-extends to 0xFFFFFF80)
    cpu.memory[256] = 0x80;
    cpu.writeReg(1, 256); // base address
    // LB x0, 0(x1): opcode=0000011, funct3=000, rd=0, rs1=1, imm=0
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b000, 0, 1, 0));
    _ = try cpu.step();
    // x0 must remain 0 despite sign-extension of loaded byte
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "step: wrapping ADD then CSR read sees correct cycle count" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 0xFFFFFFFF);
    cpu.writeReg(2, 1);
    cpu.cycle_count = 10;

    // ADD x3, x1, x2 — wraps to 0
    h.loadInst(&cpu, h.encodeR(0b0110011, 0b000, 0b0000000, 3, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(3)); // wrapped result
    try std.testing.expectEqual(@as(u64, 11), cpu.cycle_count);

    // CSRRS x4, 0xC00, x0 — read cycle counter
    h.loadInst(&cpu, h.encodeCsr(0b010, 4, 0, 0xC00));
    _ = try cpu.step();
    // CSR read sees pre-step value (pipeline invariant): cycle_count was 11 before this step
    try std.testing.expectEqual(@as(u32, 11), cpu.readReg(4));
    try std.testing.expectEqual(@as(u64, 12), cpu.cycle_count);
}

test "step: C.NOP advances PC by 2 with no side effects" {
    var cpu = Cpu.init();
    // C.NOP = 0x0001 (quadrant 01, funct3=000, rd=0, imm=0)
    std.mem.writeInt(u16, cpu.memory[0..][0..2], 0x0001, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
    // All registers remain 0
    var i: u5 = 0;
    while (true) : (i +%= 1) {
        try std.testing.expectEqual(@as(u32, 0), cpu.readReg(i));
        if (i == 31) break;
    }
}

// --- x0 hardwired-zero write protection tests ---

test "step: LUI x0 — x0 stays zero" {
    var cpu = Cpu.init();
    h.loadInst(&cpu, h.encodeU(0b0110111, 0, 0xABCDE));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
}

test "step: JAL x0 — link discarded, x0 stays zero" {
    var cpu = Cpu.init();
    h.loadInst(&cpu, h.encodeJ(0, 8));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "step: JALR x0 — link discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    // JALR x0, x1, 0: opcode=1100111, funct3=000, rd=0, rs1=1, imm=0
    h.loadInst(&cpu, h.encodeI(0b1100111, 0b000, 0, 1, 0));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 100), cpu.pc);
}

test "step: AMOSWAP.W x0 — old value discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 256); // address
    cpu.writeReg(2, 0xBEEF); // new value
    h.storeWordAt(&cpu, 256, 0xDEAD);
    // AMOSWAP.W x0, x2, (x1): funct5=00001
    h.loadInst(&cpu, h.encodeAtomic(0b00001, 0, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xBEEF), h.readWordAt(&cpu, 256));
}

test "step: SC.W x0 — success code discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 256); // address
    cpu.writeReg(2, 0xCAFE); // value to store
    h.storeWordAt(&cpu, 256, 0x1234);
    // LR.W x3, (x1): funct5=00010, rs2=0
    h.loadInst(&cpu, h.encodeAtomic(0b00010, 3, 1, 0));
    _ = try cpu.step();
    // SC.W x0, x2, (x1): funct5=00011
    h.loadInst(&cpu, h.encodeAtomic(0b00011, 0, 1, 2));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xCAFE), h.readWordAt(&cpu, 256));
}

test "step: CSRRS x0 — old CSR value discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xF0;
    cpu.writeReg(1, 0x0F);
    // CSRRS x0, mscratch, x1
    h.loadInst(&cpu, h.encodeCsr(0b010, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.csrs.mscratch);
}

test "step: CSRRC x0 — old CSR value discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xFF;
    cpu.writeReg(1, 0x0F);
    // CSRRC x0, mscratch, x1
    h.loadInst(&cpu, h.encodeCsr(0b011, 0, 1, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.csrs.mscratch);
}

test "step: CSRRSI x0 — old CSR value discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xF0;
    // CSRRSI x0, mscratch, 15 (zimm=15 in rs1 field)
    h.loadInst(&cpu, h.encodeCsr(0b110, 0, 15, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xFF), cpu.csrs.mscratch);
}

test "step: CSRRCI x0 — old CSR value discarded, x0 stays zero" {
    var cpu = Cpu.init();
    cpu.csrs.mscratch = 0xFF;
    // CSRRCI x0, mscratch, 15 (zimm=15 in rs1 field)
    h.loadInst(&cpu, h.encodeCsr(0b111, 0, 15, 0x340));
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 0), cpu.readReg(0));
    try std.testing.expectEqual(@as(u32, 0xF0), cpu.csrs.mscratch);
}

test "step: compressed C.ADDI dispatches through CPU" {
    var cpu = Cpu.init();
    cpu.writeReg(1, 100);
    // C.ADDI x1, 5 — encoding: [15:13]=000, [12]=0, [11:7]=00001, [6:2]=00101, [1:0]=01
    // imm[5]=bit12=0, imm[4:0]=bits[6:2]=00101 → imm=5
    const c_addi: u16 = 0b000_0_00001_00101_01;
    std.mem.writeInt(u16, cpu.memory[0..][0..2], c_addi, .little);
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 105), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc); // PC advances by 2
}
