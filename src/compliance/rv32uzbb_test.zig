//! Zbb bit manipulation compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32uzbb: andn" {
    try runner.expectPass("andn", @embedFile("bin/rv32uzbb/andn.bin"));
}
test "rv32uzbb: clz" {
    try runner.expectPass("clz", @embedFile("bin/rv32uzbb/clz.bin"));
}
test "rv32uzbb: cpop" {
    try runner.expectPass("cpop", @embedFile("bin/rv32uzbb/cpop.bin"));
}
test "rv32uzbb: ctz" {
    try runner.expectPass("ctz", @embedFile("bin/rv32uzbb/ctz.bin"));
}
test "rv32uzbb: max" {
    try runner.expectPass("max", @embedFile("bin/rv32uzbb/max.bin"));
}
test "rv32uzbb: maxu" {
    try runner.expectPass("maxu", @embedFile("bin/rv32uzbb/maxu.bin"));
}
test "rv32uzbb: min" {
    try runner.expectPass("min", @embedFile("bin/rv32uzbb/min.bin"));
}
test "rv32uzbb: minu" {
    try runner.expectPass("minu", @embedFile("bin/rv32uzbb/minu.bin"));
}
test "rv32uzbb: orc_b" {
    try runner.expectPass("orc_b", @embedFile("bin/rv32uzbb/orc_b.bin"));
}
test "rv32uzbb: orn" {
    try runner.expectPass("orn", @embedFile("bin/rv32uzbb/orn.bin"));
}
test "rv32uzbb: rev8" {
    try runner.expectPass("rev8", @embedFile("bin/rv32uzbb/rev8.bin"));
}
test "rv32uzbb: rol" {
    try runner.expectPass("rol", @embedFile("bin/rv32uzbb/rol.bin"));
}
test "rv32uzbb: ror" {
    try runner.expectPass("ror", @embedFile("bin/rv32uzbb/ror.bin"));
}
test "rv32uzbb: rori" {
    try runner.expectPass("rori", @embedFile("bin/rv32uzbb/rori.bin"));
}
test "rv32uzbb: sext_b" {
    try runner.expectPass("sext_b", @embedFile("bin/rv32uzbb/sext_b.bin"));
}
test "rv32uzbb: sext_h" {
    try runner.expectPass("sext_h", @embedFile("bin/rv32uzbb/sext_h.bin"));
}
test "rv32uzbb: xnor" {
    try runner.expectPass("xnor", @embedFile("bin/rv32uzbb/xnor.bin"));
}
test "rv32uzbb: zext_h" {
    try runner.expectPass("zext_h", @embedFile("bin/rv32uzbb/zext_h.bin"));
}
