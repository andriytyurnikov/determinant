//! Zba address generation compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32uzba: sh1add" {
    try runner.expectPass("sh1add", @embedFile("bin/rv32uzba/sh1add.bin"));
}
test "rv32uzba: sh2add" {
    try runner.expectPass("sh2add", @embedFile("bin/rv32uzba/sh2add.bin"));
}
test "rv32uzba: sh3add" {
    try runner.expectPass("sh3add", @embedFile("bin/rv32uzba/sh3add.bin"));
}
