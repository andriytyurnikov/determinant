const std = @import("std");
const cpu_mod = @import("cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("instructions/test_helpers.zig");

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
