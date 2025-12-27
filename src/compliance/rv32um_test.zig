//! RV32M multiply/divide compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32um: div" {
    try runner.expectPass("div", @embedFile("bin/rv32um/div.bin"));
}
test "rv32um: divu" {
    try runner.expectPass("divu", @embedFile("bin/rv32um/divu.bin"));
}
test "rv32um: mul" {
    try runner.expectPass("mul", @embedFile("bin/rv32um/mul.bin"));
}
test "rv32um: mulh" {
    try runner.expectPass("mulh", @embedFile("bin/rv32um/mulh.bin"));
}
test "rv32um: mulhsu" {
    try runner.expectPass("mulhsu", @embedFile("bin/rv32um/mulhsu.bin"));
}
test "rv32um: mulhu" {
    try runner.expectPass("mulhu", @embedFile("bin/rv32um/mulhu.bin"));
}
test "rv32um: rem" {
    try runner.expectPass("rem", @embedFile("bin/rv32um/rem.bin"));
}
test "rv32um: remu" {
    try runner.expectPass("remu", @embedFile("bin/rv32um/remu.bin"));
}
