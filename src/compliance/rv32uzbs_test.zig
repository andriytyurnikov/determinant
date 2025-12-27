//! Zbs single-bit compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32uzbs: bclr" {
    try runner.expectPass("bclr", @embedFile("bin/rv32uzbs/bclr.bin"));
}
test "rv32uzbs: bclri" {
    try runner.expectPass("bclri", @embedFile("bin/rv32uzbs/bclri.bin"));
}
test "rv32uzbs: bext" {
    try runner.expectPass("bext", @embedFile("bin/rv32uzbs/bext.bin"));
}
test "rv32uzbs: bexti" {
    try runner.expectPass("bexti", @embedFile("bin/rv32uzbs/bexti.bin"));
}
test "rv32uzbs: binv" {
    try runner.expectPass("binv", @embedFile("bin/rv32uzbs/binv.bin"));
}
test "rv32uzbs: binvi" {
    try runner.expectPass("binvi", @embedFile("bin/rv32uzbs/binvi.bin"));
}
test "rv32uzbs: bset" {
    try runner.expectPass("bset", @embedFile("bin/rv32uzbs/bset.bin"));
}
test "rv32uzbs: bseti" {
    try runner.expectPass("bseti", @embedFile("bin/rv32uzbs/bseti.bin"));
}
