//! RV32I base integer compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32ui: add" {
    try runner.expectPass("add", @embedFile("bin/rv32ui/add.bin"));
}
test "rv32ui: addi" {
    try runner.expectPass("addi", @embedFile("bin/rv32ui/addi.bin"));
}
test "rv32ui: and" {
    try runner.expectPass("and", @embedFile("bin/rv32ui/and.bin"));
}
test "rv32ui: andi" {
    try runner.expectPass("andi", @embedFile("bin/rv32ui/andi.bin"));
}
test "rv32ui: auipc" {
    try runner.expectPass("auipc", @embedFile("bin/rv32ui/auipc.bin"));
}
test "rv32ui: beq" {
    try runner.expectPass("beq", @embedFile("bin/rv32ui/beq.bin"));
}
test "rv32ui: bge" {
    try runner.expectPass("bge", @embedFile("bin/rv32ui/bge.bin"));
}
test "rv32ui: bgeu" {
    try runner.expectPass("bgeu", @embedFile("bin/rv32ui/bgeu.bin"));
}
test "rv32ui: blt" {
    try runner.expectPass("blt", @embedFile("bin/rv32ui/blt.bin"));
}
test "rv32ui: bltu" {
    try runner.expectPass("bltu", @embedFile("bin/rv32ui/bltu.bin"));
}
test "rv32ui: bne" {
    try runner.expectPass("bne", @embedFile("bin/rv32ui/bne.bin"));
}
test "rv32ui: jal" {
    try runner.expectPass("jal", @embedFile("bin/rv32ui/jal.bin"));
}
test "rv32ui: jalr" {
    try runner.expectPass("jalr", @embedFile("bin/rv32ui/jalr.bin"));
}
test "rv32ui: lb" {
    try runner.expectPass("lb", @embedFile("bin/rv32ui/lb.bin"));
}
test "rv32ui: lbu" {
    try runner.expectPass("lbu", @embedFile("bin/rv32ui/lbu.bin"));
}
test "rv32ui: lh" {
    try runner.expectPass("lh", @embedFile("bin/rv32ui/lh.bin"));
}
test "rv32ui: lhu" {
    try runner.expectPass("lhu", @embedFile("bin/rv32ui/lhu.bin"));
}
test "rv32ui: lui" {
    try runner.expectPass("lui", @embedFile("bin/rv32ui/lui.bin"));
}
test "rv32ui: lw" {
    try runner.expectPass("lw", @embedFile("bin/rv32ui/lw.bin"));
}
test "rv32ui: or" {
    try runner.expectPass("or", @embedFile("bin/rv32ui/or.bin"));
}
test "rv32ui: ori" {
    try runner.expectPass("ori", @embedFile("bin/rv32ui/ori.bin"));
}
test "rv32ui: sb" {
    try runner.expectPass("sb", @embedFile("bin/rv32ui/sb.bin"));
}
test "rv32ui: sh" {
    try runner.expectPass("sh", @embedFile("bin/rv32ui/sh.bin"));
}
test "rv32ui: simple" {
    try runner.expectPass("simple", @embedFile("bin/rv32ui/simple.bin"));
}
test "rv32ui: sll" {
    try runner.expectPass("sll", @embedFile("bin/rv32ui/sll.bin"));
}
test "rv32ui: slli" {
    try runner.expectPass("slli", @embedFile("bin/rv32ui/slli.bin"));
}
test "rv32ui: slt" {
    try runner.expectPass("slt", @embedFile("bin/rv32ui/slt.bin"));
}
test "rv32ui: slti" {
    try runner.expectPass("slti", @embedFile("bin/rv32ui/slti.bin"));
}
test "rv32ui: sltiu" {
    try runner.expectPass("sltiu", @embedFile("bin/rv32ui/sltiu.bin"));
}
test "rv32ui: sltu" {
    try runner.expectPass("sltu", @embedFile("bin/rv32ui/sltu.bin"));
}
test "rv32ui: sra" {
    try runner.expectPass("sra", @embedFile("bin/rv32ui/sra.bin"));
}
test "rv32ui: srai" {
    try runner.expectPass("srai", @embedFile("bin/rv32ui/srai.bin"));
}
test "rv32ui: srl" {
    try runner.expectPass("srl", @embedFile("bin/rv32ui/srl.bin"));
}
test "rv32ui: srli" {
    try runner.expectPass("srli", @embedFile("bin/rv32ui/srli.bin"));
}
test "rv32ui: sub" {
    try runner.expectPass("sub", @embedFile("bin/rv32ui/sub.bin"));
}
test "rv32ui: sw" {
    try runner.expectPass("sw", @embedFile("bin/rv32ui/sw.bin"));
}
test "rv32ui: xor" {
    try runner.expectPass("xor", @embedFile("bin/rv32ui/xor.bin"));
}
test "rv32ui: xori" {
    try runner.expectPass("xori", @embedFile("bin/rv32ui/xori.bin"));
}
test "rv32ui: ld_st" {
    try runner.expectPass("ld_st", @embedFile("bin/rv32ui/ld_st.bin"));
}
test "rv32ui: st_ld" {
    try runner.expectPass("st_ld", @embedFile("bin/rv32ui/st_ld.bin"));
}
// Skipped: fence_i (self-modifying code), ma_data (misaligned traps — spec-valid)
