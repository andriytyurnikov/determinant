//! RISC-V compliance tests — validates the VM against the riscv-tests suite.
//!
//! Pre-compiled flat binaries from riscv-software-src/riscv-tests are loaded
//! via @embedFile and executed on a 256KB ComplianceCpu instance. Pass/fail
//! is determined by the gp (x3) register convention: 1 = pass, (N<<1|1) = fail.

test {
    _ = @import("compliance/tests.zig");
}
