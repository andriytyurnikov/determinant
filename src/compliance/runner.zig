//! Compliance test runner — loads pre-compiled riscv-tests binaries and
//! validates pass/fail via the gp (x3) register convention.

const std = @import("std");
const det = @import("determinant");

/// 256KB memory — larger than default 64KB to accommodate test data sections.
const compliance_memory_size: u32 = 256 * 1024;

/// CPU type used for compliance tests — fixed 256KB memory, LUT decoder.
pub const ComplianceCpu = det.CpuType(compliance_memory_size, &det.decoders.lut.decode);

pub const TestResult = union(enum) {
    pass,
    fail: u32,
    timeout,
    runtime_error,
};

/// Run a compliance test binary. Returns the test result.
pub fn runTest(binary: []const u8) TestResult {
    var vm = ComplianceCpu.init();
    vm.loadProgram(binary, 0) catch return .runtime_error;

    const result = vm.run(1_000_000) catch return .runtime_error;

    return switch (result) {
        .ebreak => {
            const gp = vm.readReg(3);
            if (gp == 1) return .pass;
            return .{ .fail = gp >> 1 };
        },
        .ecall => {
            // Some tests use ecall for pass (with a0=0, a7=93 convention)
            const a0 = vm.readReg(10);
            if (a0 == 0) return .pass;
            const gp = vm.readReg(3);
            return .{ .fail = gp >> 1 };
        },
        .@"continue" => .timeout,
    };
}

/// Run a compliance test and assert it passes. Produces a clear error on failure.
pub fn expectPass(comptime name: []const u8, binary: []const u8) !void {
    const result = runTest(binary);
    switch (result) {
        .pass => {},
        .fail => |test_num| {
            std.debug.print("COMPLIANCE FAIL: {s} — test case #{d} failed\n", .{ name, test_num });
            return error.ComplianceTestFailed;
        },
        .timeout => {
            std.debug.print("COMPLIANCE FAIL: {s} — timed out (1M cycles)\n", .{name});
            return error.ComplianceTestTimeout;
        },
        .runtime_error => {
            std.debug.print("COMPLIANCE FAIL: {s} — runtime error\n", .{name});
            return error.ComplianceTestRuntimeError;
        },
    }
}
