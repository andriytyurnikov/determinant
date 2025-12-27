//! RV32C compressed instruction compliance test from riscv-tests.

const runner = @import("runner.zig");

test "rv32uc: rvc" {
    try runner.expectPass("rvc", @embedFile("bin/rv32uc/rvc.bin"));
}
