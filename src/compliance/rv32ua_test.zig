//! RV32A atomic compliance tests from riscv-tests.

const runner = @import("runner.zig");

test "rv32ua: amoadd_w" {
    try runner.expectPass("amoadd_w", @embedFile("bin/rv32ua/amoadd_w.bin"));
}
test "rv32ua: amoand_w" {
    try runner.expectPass("amoand_w", @embedFile("bin/rv32ua/amoand_w.bin"));
}
test "rv32ua: amomax_w" {
    try runner.expectPass("amomax_w", @embedFile("bin/rv32ua/amomax_w.bin"));
}
test "rv32ua: amomaxu_w" {
    try runner.expectPass("amomaxu_w", @embedFile("bin/rv32ua/amomaxu_w.bin"));
}
test "rv32ua: amomin_w" {
    try runner.expectPass("amomin_w", @embedFile("bin/rv32ua/amomin_w.bin"));
}
test "rv32ua: amominu_w" {
    try runner.expectPass("amominu_w", @embedFile("bin/rv32ua/amominu_w.bin"));
}
test "rv32ua: amoor_w" {
    try runner.expectPass("amoor_w", @embedFile("bin/rv32ua/amoor_w.bin"));
}
test "rv32ua: amoswap_w" {
    try runner.expectPass("amoswap_w", @embedFile("bin/rv32ua/amoswap_w.bin"));
}
test "rv32ua: amoxor_w" {
    try runner.expectPass("amoxor_w", @embedFile("bin/rv32ua/amoxor_w.bin"));
}
test "rv32ua: lrsc" {
    try runner.expectPass("lrsc", @embedFile("bin/rv32ua/lrsc.bin"));
}
