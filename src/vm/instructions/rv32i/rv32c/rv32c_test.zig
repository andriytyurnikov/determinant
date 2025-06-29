const std = @import("std");
const rv32c = @import("rv32c.zig");
const rv32i = @import("../rv32i.zig");
const instructions = @import("../../../instructions.zig");
const Opcode = instructions.Opcode;
const decoder = @import("../../../decoders/branch_decoder.zig");
const cpu_mod = @import("../../../cpu.zig");
const Cpu = cpu_mod.Cpu;
const h = @import("../../test_helpers.zig");

fn expectExpand(half: u16, expected_op: rv32i.Opcode, expected_rd: u5, expected_rs1: u5, expected_rs2: u5, expected_imm: i32) !void {
    const exp = try rv32c.expand(half);
    try std.testing.expectEqual(expected_op, exp.op);
    try std.testing.expectEqual(expected_rd, exp.rd);
    try std.testing.expectEqual(expected_rs1, exp.rs1);
    try std.testing.expectEqual(expected_rs2, exp.rs2);
    try std.testing.expectEqual(expected_imm, exp.imm);
    try std.testing.expectEqual(@as(u32, half), exp.raw);
}

// ============================================================
// Quadrant 0 tests
// ============================================================

test "C.ADDI4SPN: addi rd', x2, nzuimm" {
    // C.ADDI4SPN x8, x2, 8
    // nzuimm=8 → nzuimm[3]=1 → bit[5]=1
    // rd'=0 → bits[4:2]=000, op=00, funct3=000
    // Encoding: 000 0 0000 1 000 00 = 0x0020
    // nzuimm[3] at bit[5]: bit5=1 → 0x0020
    // Let me construct: funct3=000(bits15:13), nzuimm bits in [12:5], rd' in [4:2], op=00 in [1:0]
    // nzuimm=8: bit3=1 → need bit[5]=1 in encoding
    // All other nzuimm bits 0
    // rd'=0 (x8)
    // = 0b000_00000_10_000_00 = 0x0020
    try expectExpand(0x0020, .ADDI, 8, 2, 0, 8);
}

test "C.ADDI4SPN: nzuimm=0 is illegal" {
    // funct3=000, all imm bits zero, rd'=0, op=00
    // = 0x0000
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x0000));
}

test "C.LW: lw rd', offset(rs1')" {
    // C.LW x8, 0(x8)
    // funct3=010, rs1'=0(x8), rd'=0(x8), all offset bits=0
    // = 0b010_000_000_00_000_00 = 0x4000
    try expectExpand(0x4000, .LW, 8, 8, 0, 0);
}

test "C.LW with offset" {
    // C.LW x9, 4(x10)
    // offset=4: offset[2]=1 → bit[6]=1
    // rs1'=2(x10) → bits[9:7]=010, rd'=1(x9) → bits[4:2]=001
    // funct3=010
    // = 0b010_010_000_01_001_00 = 0x4144 → wait, let me be more careful
    // bit[15:13]=010, bit[12:10]=010 (rs1'=2), bit[9:7]=... wait
    // Actually: bits[12:10] are part of offset and rs1' is in bits[9:7]
    // Format: [15:13]=funct3, [12:10]=offset[5:3], [9:7]=rs1', [6]=offset[2], [5]=offset[6], [4:2]=rd', [1:0]=op
    // offset=4: bit[2]=1 → bit[6]=1, rest=0
    // rs1'=2 (x10) → bits[9:7]=010
    // rd'=1 (x9) → bits[4:2]=001
    // = 0b010_000_010_1_0_001_00 = 0x4144
    try expectExpand(0x4144, .LW, 9, 10, 0, 4);
}

test "C.SW: sw rs2', offset(rs1')" {
    // C.SW x8, 0(x8)
    // funct3=110, rs1'=0(x8), rs2'=0(x8), offset=0
    // = 0b110_000_000_00_000_00 = 0xC000
    try expectExpand(0xC000, .SW, 0, 8, 8, 0);
}

// ============================================================
// Quadrant 1 tests
// ============================================================

test "C.NOP" {
    // C.NOP: funct3=000, rd=0, imm=0, op=01
    // = 0b000_0_00000_00000_01 = 0x0001
    try expectExpand(0x0001, .ADDI, 0, 0, 0, 0);
}

test "C.ADDI: addi rd, rd, nzimm" {
    // C.ADDI x1, x1, 1
    // funct3=000, bit[12]=0 (imm[5]=0), rd=1 in bits[11:7], bits[6:2]=00001 (imm[4:0]=1), op=01
    // = 0b000_0_00001_00001_01 = 0x0085
    try expectExpand(0x0085, .ADDI, 1, 1, 0, 1);
}

test "C.ADDI negative" {
    // C.ADDI x1, x1, -1
    // imm = -1 = 0b111111 (6-bit signed)
    // bit[12]=1 (imm[5]), bits[6:2]=11111 (imm[4:0])
    // rd=1 → bits[11:7]=00001
    // funct3=000, op=01
    // = 0b000_1_00001_11111_01 = 0x10FD
    try expectExpand(0x10FD, .ADDI, 1, 1, 0, -1);
}

test "C.JAL: jal x1, offset" {
    // C.JAL with offset=0: all bits zero except funct3=001 and op=01
    // = 0b001_00000000000_01 = 0x2001
    try expectExpand(0x2001, .JAL, 1, 0, 0, 0);
}

test "C.LI: addi rd, x0, imm" {
    // C.LI x1, 5
    // funct3=010, bit[12]=0, rd=1 → bits[11:7]=00001, bits[6:2]=00101, op=01
    // = 0b010_0_00001_00101_01 = 0x4095
    try expectExpand(0x4095, .ADDI, 1, 0, 0, 5);
}

test "C.LI negative" {
    // C.LI x1, -1
    // funct3=010, bit[12]=1, rd=1, bits[6:2]=11111, op=01
    // = 0b010_1_00001_11111_01 = 0x50FD
    try expectExpand(0x50FD, .ADDI, 1, 0, 0, -1);
}

test "C.ADDI16SP: addi x2, x2, nzimm" {
    // C.ADDI16SP x2, 16
    // nzimm=16 → nzimm[4]=1
    // bit[12]=sign(0), bits[6:2] encode rest
    // nzimm[4] comes from bit[6]
    // bit[6]=1 → 0x0040 at that position
    // funct3=011, rd=2, op=01
    // = 0b011_0_00010_01000_01 = 0x6141 → let me compute:
    // funct3=011 → bits[15:13] = 011
    // bit[12] = 0 (sign)
    // bits[11:7] = 00010 (rd=2)
    // bits[6:2] = 01000: bit[6]=0, bit[5]=1, bit[4]=0, bit[3]=0, bit[2]=0
    // Wait, nzimm[4] from bit[6], nzimm[6] from bit[5], nzimm[8:7] from bits[4:3], nzimm[5] from bit[2]
    // nzimm=16: bit4=1 → bit[6]=1
    // bits[6:2] = 10000
    // = 0b011_0_00010_10000_01 = 0x6141
    try expectExpand(0x6141, .ADDI, 2, 2, 0, 16);
}

test "C.ADDI16SP negative" {
    // C.ADDI16SP x2, -16
    // nzimm=-16 in 10-bit = 0b1111110000
    // imm[9]=1 → bit[12]=1
    // imm[4]=1 → bit[6]=1
    // imm[6]=1 → bit[5]=1
    // imm[8:7]=11 → bits[4:3]=11
    // imm[5]=1 → bit[2]=1
    // bits[6:2]=11111
    // = 0b011_1_00010_11111_01 = 0x717D
    try expectExpand(0x717D, .ADDI, 2, 2, 0, -16);
}

test "C.ADDI16SP: nzimm=0 is illegal" {
    // funct3=011, rd=2, all imm=0, op=01
    // = 0b011_0_00010_00000_01 = 0x6101
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6101));
}

test "C.LUI: lui rd, nzimm" {
    // C.LUI x1, imm=0x1000 (nzimm[17:12] with bit[16:12]=1 and sign=0)
    // This means the 6-bit field is 0b000001
    // bit[12]=0, bits[6:2]=00001
    // funct3=011, rd=1, op=01
    // = 0b011_0_00001_00001_01 = 0x6085
    // The resulting immediate should be 0x1000 = 4096
    try expectExpand(0x6085, .LUI, 1, 0, 0, 4096);
}

test "C.LUI negative" {
    // C.LUI x1, nzimm with sign bit set → upper immediate is negative
    // 6-bit field = 0b111111 → as i6 = -1, then (-1) << 12 = -4096 = 0xFFFFF000
    // bit[12]=1, bits[6:2]=11111
    // funct3=011, rd=1, op=01
    // = 0b011_1_00001_11111_01 = 0x70FD
    try expectExpand(0x70FD, .LUI, 1, 0, 0, @bitCast(@as(u32, 0xFFFFF000)));
}

test "C.LUI: nzimm=0 is illegal" {
    // funct3=011, rd=1 (not 2, so not ADDI16SP), all imm=0, op=01
    // = 0b011_0_00001_00000_01 = 0x6081
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x6081));
}

test "C.SRLI" {
    // C.SRLI x8, x8, 1
    // funct3=100, funct2=00 (bits[11:10]), bit[12]=0 (shamt[5]), rd'=0(x8) bits[9:7], bits[6:2]=00001 (shamt[4:0]=1), op=01
    // = 0b100_0_00_000_00001_01 = 0x8005
    try expectExpand(0x8005, .SRLI, 8, 8, 0, 1);
}

test "C.SRLI: shamt[5]=1 illegal on RV32" {
    // bit[12]=1 → shamt[5]=1
    // = 0b100_1_00_000_00001_01 = 0x9005
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x9005));
}

test "C.SRAI" {
    // C.SRAI x8, x8, 1
    // funct3=100, funct2=01 (bits[11:10]), bit[12]=0, rd'=0(x8), bits[6:2]=00001, op=01
    // = 0b100_0_01_000_00001_01 = 0x8405
    try expectExpand(0x8405, .SRAI, 8, 8, 0, 1);
}

test "C.ANDI" {
    // C.ANDI x8, x8, 3
    // funct3=100, funct2=10 (bits[11:10]), bit[12]=0, rd'=0(x8), bits[6:2]=00011, op=01
    // = 0b100_0_10_000_00011_01 = 0x880D
    try expectExpand(0x880D, .ANDI, 8, 8, 0, 3);
}

test "C.ANDI negative" {
    // C.ANDI x8, x8, -1
    // funct3=100, funct2=10, bit[12]=1 (sign), rd'=0(x8), bits[6:2]=11111, op=01
    // = 0b100_1_10_000_11111_01 = 0x987D
    try expectExpand(0x987D, .ANDI, 8, 8, 0, -1);
}

test "C.SUB" {
    // C.SUB x8, x8, x9
    // funct3=100, bit[12]=0, funct2=11 (bits[11:10]), rd'/rs1'=0(x8) bits[9:7], funct2b=00 (bits[6:5]), rs2'=1(x9) bits[4:2], op=01
    // = 0b100_0_11_000_00_001_01 = 0x8C05
    try expectExpand(0x8C05, .SUB, 8, 8, 9, 0);
}

test "C.XOR" {
    // C.XOR x8, x8, x9
    // Same as SUB but funct2b=01 (bits[6:5])
    // = 0b100_0_11_000_01_001_01 = 0x8C25
    try expectExpand(0x8C25, .XOR, 8, 8, 9, 0);
}

test "C.OR" {
    // C.OR x8, x8, x9
    // funct2b=10
    // = 0b100_0_11_000_10_001_01 = 0x8C45
    try expectExpand(0x8C45, .OR, 8, 8, 9, 0);
}

test "C.AND" {
    // C.AND x8, x8, x9
    // funct2b=11
    // = 0b100_0_11_000_11_001_01 = 0x8C65
    try expectExpand(0x8C65, .AND, 8, 8, 9, 0);
}

test "C.J: jal x0, offset" {
    // C.J with offset=0
    // funct3=101, all offset bits=0, op=01
    // = 0b101_00000000000_01 = 0xA001
    try expectExpand(0xA001, .JAL, 0, 0, 0, 0);
}

test "C.BEQZ: beq rs1', x0, offset" {
    // C.BEQZ x8, 0
    // funct3=110, rs1'=0(x8), all offset=0, op=01
    // = 0b110_000_000_00000_01 = 0xC001
    try expectExpand(0xC001, .BEQ, 0, 8, 0, 0);
}

test "C.BNEZ: bne rs1', x0, offset" {
    // C.BNEZ x8, 0
    // funct3=111, rs1'=0(x8), all offset=0, op=01
    // = 0b111_000_000_00000_01 = 0xE001
    try expectExpand(0xE001, .BNE, 0, 8, 0, 0);
}

// ============================================================
// Quadrant 2 tests
// ============================================================

test "C.SLLI" {
    // C.SLLI x1, x1, 1
    // funct3=000, bit[12]=0, rd=1 bits[11:7], bits[6:2]=00001, op=10
    // = 0b000_0_00001_00001_10 = 0x0086
    try expectExpand(0x0086, .SLLI, 1, 1, 0, 1);
}

test "C.SLLI: shamt[5]=1 illegal on RV32" {
    // bit[12]=1, rd=1, bits[6:2]=00001, op=10
    // = 0b000_1_00001_00001_10 = 0x1086
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x1086));
}

test "C.LWSP: lw rd, offset(x2)" {
    // C.LWSP x1, 0(x2)
    // funct3=010, bit[12]=0, rd=1, bits[6:2]=00000, op=10
    // = 0b010_0_00001_00000_10 = 0x4082
    try expectExpand(0x4082, .LW, 1, 2, 0, 0);
}

test "C.LWSP with offset" {
    // C.LWSP x1, 4(x2)
    // offset=4: offset[2]=1 → bit[4]=1
    // funct3=010, bit[12]=0, rd=1, bits[6:2]=00100, op=10
    // = 0b010_0_00001_00100_10 = 0x4092
    try expectExpand(0x4092, .LW, 1, 2, 0, 4);
}

test "C.LWSP: rd=0 is illegal" {
    // funct3=010, rd=0, op=10
    // = 0b010_0_00000_00000_10 = 0x4002
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x4002));
}

test "C.JR: jalr x0, 0(rs1)" {
    // C.JR x1
    // funct3=100, bit[12]=0, rd/rs1=1, rs2=0, op=10
    // = 0b100_0_00001_00000_10 = 0x8082
    try expectExpand(0x8082, .JALR, 0, 1, 0, 0);
}

test "C.JR: rs1=0 is illegal" {
    // funct3=100, bit[12]=0, rd/rs1=0, rs2=0, op=10
    // = 0b100_0_00000_00000_10 = 0x8002
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x8002));
}

test "C.MV: add rd, x0, rs2" {
    // C.MV x1, x2
    // funct3=100, bit[12]=0, rd=1, rs2=2, op=10
    // = 0b100_0_00001_00010_10 = 0x808A
    try expectExpand(0x808A, .ADD, 1, 0, 2, 0);
}

test "C.EBREAK" {
    // funct3=100, bit[12]=1, rd=0, rs2=0, op=10
    // = 0b100_1_00000_00000_10 = 0x9002
    try expectExpand(0x9002, .EBREAK, 0, 0, 0, 0);
}

test "C.JALR: jalr x1, 0(rs1)" {
    // C.JALR x1
    // funct3=100, bit[12]=1, rd/rs1=1, rs2=0, op=10
    // = 0b100_1_00001_00000_10 = 0x9082
    try expectExpand(0x9082, .JALR, 1, 1, 0, 0);
}

test "C.ADD: add rd, rd, rs2" {
    // C.ADD x1, x2
    // funct3=100, bit[12]=1, rd=1, rs2=2, op=10
    // = 0b100_1_00001_00010_10 = 0x908A
    try expectExpand(0x908A, .ADD, 1, 1, 2, 0);
}

test "C.SWSP: sw rs2, offset(x2)" {
    // C.SWSP x1, 0(x2)
    // funct3=110, bits[12:7]=000000 (offset), rs2=1 bits[6:2], op=10
    // = 0b110_000000_00001_10 = 0xC006
    try expectExpand(0xC006, .SW, 0, 2, 1, 0);
}

test "C.SWSP with offset" {
    // C.SWSP x1, 4(x2)
    // offset=4: offset[2]=1 → bit[9]=1
    // funct3=110, bits[12:7]=000100, rs2=1, op=10
    // = 0b110_000100_00001_10 = 0xC206
    try expectExpand(0xC206, .SW, 0, 2, 1, 4);
}

// ============================================================
// Decoder routing test
// ============================================================

test "decoder routes 16-bit instructions" {
    // C.NOP = 0x0001, low 2 bits = 01 (not 11) → should route to rv32c
    const inst = try decoder.decode(0x0001);
    try std.testing.expectEqual(Opcode{ .i = .ADDI }, inst.op);
    try std.testing.expectEqual(@as(u5, 0), inst.rd);
}

// ============================================================
// CPU step tests for compressed instructions
// ============================================================

test "CPU step: C.LI sets register, PC advances by 2" {
    var cpu = Cpu.init();
    // C.LI x1, 5 = 0x4095
    h.storeHalfAt(&cpu, 0, 0x4095);
    // NOP at offset 2 to avoid illegal instruction
    h.storeWordAt(&cpu, 2, 0x00000013);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 5), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
}

test "CPU step: C.ADDI modifies register" {
    var cpu = Cpu.init();
    // First set x1=10 via C.LI x1, 10
    // C.LI x1, 10: funct3=010, bit12=0, rd=1, bits[6:2]=01010, op=01
    // = 0b010_0_00001_01010_01 = 0x40A9
    h.storeHalfAt(&cpu, 0, 0x40A9);
    // C.ADDI x1, 3: funct3=000, bit12=0, rd=1, bits[6:2]=00011, op=01
    // = 0b000_0_00001_00011_01 = 0x008D
    h.storeHalfAt(&cpu, 2, 0x008D);
    // ECALL at offset 4
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 13), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "CPU step: C.JAL links PC+2" {
    var cpu = Cpu.init();
    // C.JAL offset=4: jump to pc+4=4
    // offset=4: offset[2]=1, offset[1]=0
    // CJ encoding: [12]→[11], [11]→[4], [10:9]→[9:8], [8]→[10], [7]→[6], [6]→[7], [5:3]→[3:1], [2]→[5]
    // offset=4 = 0b000000000100
    // offset[2]=1 → need to find which bit in half encodes offset[2]
    // offset[3:1] come from bits[5:3], so offset[2] → offset val bit 2 is at position... wait
    // offset[3:1] from bits[5:3]: this means bit[3]→offset[1], bit[4]→offset[2], bit[5]→offset[3]
    // offset=4: offset[2]=1 → bit[4]=1
    // All other offset bits zero, funct3=001, op=01
    // = 0b001_0_0000_0_0_0_10_0_01 = 0x2011
    // Let me compute more carefully: bits = 0b001_00000_0_10_00_01
    // bit15:13=001, bit12=0, bit11=0, bit10:9=00, bit8=0, bit7=0, bit6=0, bit5:3=010 (offset[3:1]), bit2=0 (offset[5]), bit1:0=01
    // Wait, bit[5:3] encode offset[3:1]. offset=4 means offset[2]=1.
    // offset[3:1] = 010 (that's offset bit3=0, bit2=1, bit1=0) → bits[5:3]=010
    // = 0b001_0_0000_0_0_0_010_0_01
    // bit15=0,bit14=0,bit13=1,bit12=0,bit11=0,bit10=0,bit9=0,bit8=0,bit7=0,bit6=0,bit5=0,bit4=1,bit3=0,bit2=0,bit1=0,bit0=1
    // = 0x2011
    h.storeHalfAt(&cpu, 0, 0x2011);
    // ECALL at target (offset 4)
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    // JAL links ra with PC+2 (compressed instruction)
    try std.testing.expectEqual(@as(u32, 2), cpu.readReg(1)); // ra = old_pc + 2
    try std.testing.expectEqual(@as(u32, 4), cpu.pc); // jumped to pc+4
}

test "CPU step: mixed 16-bit and 32-bit sequence" {
    var cpu = Cpu.init();
    // C.LI x1, 7 at offset 0 (2 bytes)
    // funct3=010, bit12=0, rd=1, bits[6:2]=00111, op=01
    // = 0b010_0_00001_00111_01 = 0x409D
    h.storeHalfAt(&cpu, 0, 0x409D);
    // ADDI x2, x0, 3 = 0x00300113 at offset 2 (4 bytes)
    h.storeWordAt(&cpu, 2, 0x00300113);
    // C.ADD x1, x2 at offset 6 (2 bytes): add x1, x1, x2
    // funct3=100, bit12=1, rd=1, rs2=2, op=10
    // = 0b100_1_00001_00010_10 = 0x908A
    h.storeHalfAt(&cpu, 6, 0x908A);
    // ECALL at offset 8
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step(); // C.LI x1, 7 → pc=2
    try std.testing.expectEqual(@as(u32, 7), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);

    _ = try cpu.step(); // ADDI x2, x0, 3 → pc=6
    try std.testing.expectEqual(@as(u32, 3), cpu.readReg(2));
    try std.testing.expectEqual(@as(u32, 6), cpu.pc);

    _ = try cpu.step(); // C.ADD x1, x2 → x1=10, pc=8
    try std.testing.expectEqual(@as(u32, 10), cpu.readReg(1));
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);

    const result = try cpu.step(); // ECALL → pc=12
    try std.testing.expectEqual(cpu_mod.StepResult.Ecall, result);
}

test "CPU step: C.JALR links PC+2" {
    var cpu = Cpu.init();
    // Set x1 = 8 via C.LI
    // C.LI x1, 8: funct3=010, bit12=0, rd=1, bits[6:2]=01000, op=01
    // = 0b010_0_00001_01000_01 = 0x40A1
    h.storeHalfAt(&cpu, 0, 0x40A1);
    // C.JALR x1 at offset 2: jalr ra, 0(x1)
    // = 0x9082
    h.storeHalfAt(&cpu, 2, 0x9082);
    // ECALL at offset 8 (the jump target)
    h.storeWordAt(&cpu, 8, 0x00000073);

    _ = try cpu.step(); // C.LI x1, 8 → pc=2
    _ = try cpu.step(); // C.JALR x1 → pc=8, ra=4

    try std.testing.expectEqual(@as(u32, 4), cpu.readReg(1)); // ra = old_pc(2) + 2
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "CPU step: C.LW and C.SW" {
    var cpu = Cpu.init();
    // Set x2 (sp) = 256 via 32-bit ADDI
    // ADDI x2, x0, 256 = 0x10000113
    h.storeWordAt(&cpu, 0, 0x10000113);
    // Set x8 = 42 via C.LI x8, 0
    // Actually, we need full reg x8, so use 32-bit: ADDI x8, x0, 42 = 0x02A00413
    h.storeWordAt(&cpu, 4, 0x02A00413);
    // C.SWSP x8, 0(x2): sw x8, 0(x2)
    // funct3=110, offset=0 → bits[12:7]=000000, rs2=8 → bits[6:2]=01000, op=10
    // = 0b110_000000_01000_10 = 0xC022
    h.storeHalfAt(&cpu, 8, 0xC022);
    // C.LWSP x9, 0(x2): lw x9, 0(x2)
    // funct3=010, bit12=0, rd=9, bits[6:2]=00000, op=10
    // = 0b010_0_01001_00000_10 = 0x4482
    h.storeHalfAt(&cpu, 10, 0x4482);
    // ECALL
    h.storeWordAt(&cpu, 12, 0x00000073);

    _ = try cpu.step(); // ADDI x2, x0, 256
    _ = try cpu.step(); // ADDI x8, x0, 42
    _ = try cpu.step(); // C.SWSP x8, 0(x2) → mem[256]=42
    _ = try cpu.step(); // C.LWSP x9, 0(x2) → x9=42

    try std.testing.expectEqual(@as(u32, 42), cpu.readReg(9));
    try std.testing.expectEqual(@as(u32, 42), try cpu.readWord(256));
}

test "C.SRAI: shamt[5]=1 illegal on RV32" {
    // funct3=100, funct2=01 (bits[11:10]), bit[12]=1 (shamt[5]), rd'=0(x8), bits[6:2]=00001, op=01
    // = 0b100_1_01_000_00001_01 = 0x9405
    try std.testing.expectError(error.IllegalInstruction, rv32c.expand(0x9405));
}

// ============================================================
// Max-range bit extraction tests
// ============================================================

test "C.ADDI4SPN max nzuimm=1020" {
    // nzuimm=1020 = 0b1111111100
    // Bits: [12:11]→[5:4]=11, [10:7]→[9:6]=1111, [6]→[2]=1, [5]→[3]=1
    // rd'=0 (x8), funct3=000, op=00
    // = 0b000_11_1111_1_1_000_00 = 0x1FE0
    try expectExpand(0x1FE0, .ADDI, 8, 2, 0, 1020);
}

test "C.LW/SW max offset=124" {
    // clsw_offset max = 124 = 0b1111100
    // Bits: [12:10]→offset[5:3]=111, [6]→offset[2]=1, [5]→offset[6]=1
    // rs1'=0 (x8), rd'=0 (x8), funct3=010, op=00
    // = 0b010_111_000_1_1_000_00 = 0x5C60
    try expectExpand(0x5C60, .LW, 8, 8, 0, 124);
}

test "C.ADDI imm=+31" {
    // ci_imm: bit[12]→imm[5]=0, bits[6:2]→imm[4:0]=11111
    // rd=1, funct3=000, op=01
    // = 0b000_0_00001_11111_01 = 0x00FD
    try expectExpand(0x00FD, .ADDI, 1, 1, 0, 31);
}

test "C.ADDI imm=-32" {
    // ci_imm: bit[12]→imm[5]=1, bits[6:2]→imm[4:0]=00000
    // -32 as 6-bit = 0b100000
    // rd=1, funct3=000, op=01
    // = 0b000_1_00001_00000_01 = 0x1081
    try expectExpand(0x1081, .ADDI, 1, 1, 0, -32);
}

test "C.SLLI/SRLI max shamt=31" {
    // ci_shamt: bit[12]=0, bits[6:2]=11111 → shamt=31
    // C.SLLI rd=1: funct3=000, op=10
    // = 0b000_0_00001_11111_10 = 0x00FE
    try expectExpand(0x00FE, .SLLI, 1, 1, 0, 31);
}

test "C.ADDI16SP imm=+496" {
    // ci_addi16sp_imm max positive: 496 = 0b0111110000
    // bit[12]→imm[9]=0, bit[6]→imm[4]=1, bit[5]→imm[6]=1, bits[4:3]→imm[8:7]=11, bit[2]→imm[5]=1
    // rd=2, funct3=011, op=01
    // bits[6:2] = 11111
    // = 0b011_0_00010_11111_01 = 0x617D
    try expectExpand(0x617D, .ADDI, 2, 2, 0, 496);
}

test "C.ADDI16SP imm=-512" {
    // ci_addi16sp_imm min: -512 = 0b1000000000 (10-bit signed)
    // bit[12]→imm[9]=1, all others 0
    // rd=2, funct3=011, op=01
    // bits[6:2] = 00000
    // = 0b011_1_00010_00000_01 = 0x7101
    try expectExpand(0x7101, .ADDI, 2, 2, 0, -512);
}

test "C.J max positive offset=+2046" {
    // cj_offset max positive: 2046 = 0b011111111110
    // bit[12]→offset[11]=0, bit[11]→offset[4]=1, bits[10:9]→offset[9:8]=11,
    // bit[8]→offset[10]=1, bit[7]→offset[6]=1, bit[6]→offset[7]=1,
    // bits[5:3]→offset[3:1]=111, bit[2]→offset[5]=1
    // funct3=101, op=01
    // = 0b101_0_1111_1_1_1_111_1_01 = 0xAFFD
    try expectExpand(0xAFFD, .JAL, 0, 0, 0, 2046);
}

test "C.J max negative offset=-2048" {
    // cj_offset min: -2048 = 0b100000000000 (12-bit signed)
    // bit[12]→offset[11]=1, all other offset bits 0
    // funct3=101, op=01
    // = 0b101_1_0000_0_0_0_000_0_01 = 0xB001
    try expectExpand(0xB001, .JAL, 0, 0, 0, -2048);
}

test "C.BEQZ max positive offset=+254" {
    // cb_offset max positive: 254 = 0b011111110
    // bit[12]→offset[8]=0, bits[11:10]→offset[4:3]=11, bits[6:5]→offset[7:6]=11,
    // bit[2]→offset[5]=1, bits[4:3]→offset[2:1]=11
    // rs1'=0 (x8), funct3=110, op=01
    // = 0b110_0_11_000_11_111_01 = 0xCC7D
    try expectExpand(0xCC7D, .BEQ, 0, 8, 0, 254);
}

test "C.BNEZ max negative offset=-256" {
    // cb_offset min: -256 = 0b100000000 (9-bit signed)
    // bit[12]→offset[8]=1, all other offset bits 0
    // rs1'=0 (x8), funct3=111, op=01
    // = 0b111_1_00_000_00_000_01 = 0xF001
    try expectExpand(0xF001, .BNE, 0, 8, 0, -256);
}

test "C.LWSP max offset=252" {
    // ci_lwsp_offset max: 252 = 0b11111100
    // bit[12]→offset[5]=1, bits[6:4]→offset[4:2]=111, bits[3:2]→offset[7:6]=11
    // rd=1, funct3=010, op=10
    // = 0b010_1_00001_11111_10 = 0x50FE
    try expectExpand(0x50FE, .LW, 1, 2, 0, 252);
}

test "C.SWSP max offset=252" {
    // css_swsp_offset max: 252 = 0b11111100
    // bits[12:9]→offset[5:2]=1111, bits[8:7]→offset[7:6]=11
    // rs2=1, funct3=110, op=10
    // = 0b110_111111_00001_10 = 0xDF86
    try expectExpand(0xDF86, .SW, 0, 2, 1, 252);
}

test "CPU step: C.BEQZ taken" {
    var cpu = Cpu.init();
    // x8 = 0 by default
    // C.BEQZ x8, 4: beq x8, x0, 4
    // offset=4: offset[2]=1 → bit[4] in CB-format
    // CB: [12]→[8], [11:10]→[4:3], [6:5]→[7:6], [4:3]→[2:1], [2]→[5]
    // offset=4: bit[2]=1 → bits[4:3] encode offset[2:1], offset[2]=1 → bit[4]=1, offset[1]=0 → bit[3]=0
    // funct3=110, bit[12]=0, bits[11:10]=00, rs1'=0(x8), bit[6:5]=00, bit[4]=1, bit[3]=0, bit[2]=0, op=01
    // = 0b110_000_000_00_010_01 = 0xC009
    // Wait: bit4=1,bit3=0 → bits[4:3] = 10
    // = 0b110_0_00_000_00_100_01
    // bits: 15=1,14=1,13=0,12=0,11=0,10=0,9=0,8=0,7=0,6=0,5=0,4=1,3=0,2=0,1=0,0=1
    // = 0xC011
    h.storeHalfAt(&cpu, 0, 0xC011);
    // ECALL at offset 4
    h.storeWordAt(&cpu, 4, 0x00000073);

    _ = try cpu.step();
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}
