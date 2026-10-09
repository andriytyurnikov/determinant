//! Compliance test runner — loads pre-compiled riscv-tests binaries and
//! validates pass/fail via the gp (x3) register convention.

const std = @import("std");
const det = @import("determinant");

/// 256KB memory — larger than default 64KB to accommodate test data sections.
const compliance_memory_size: u32 = 256 * 1024;

/// CPU type used for compliance tests — fixed 256KB memory, default decoder.
pub const ComplianceCpu = det.CpuType(compliance_memory_size, det.Cpu.decode);

pub const TestResult = union(enum) {
    pass,
    fail: u32,
    timeout,
    runtime_error,
    /// The test stopped at an ECALL. Our riscv_test.h ends every test with EBREAK
    /// (some tests execute ECALL themselves), so this is never a pass.
    unexpected_ecall,
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
        .ecall => .unexpected_ecall,
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
        .unexpected_ecall => {
            std.debug.print("COMPLIANCE FAIL: {s} — stopped at ECALL instead of the EBREAK that ends a test\n", .{name});
            return error.ComplianceTestUnexpectedEcall;
        },
    }
}

test "runTest: an ECALL stop is not a pass, even with gp == 1" {
    // li gp, 1; ecall
    const program = [_]u8{
        0x93, 0x01, 0x10, 0x00, // ADDI x3, x0, 1
        0x73, 0x00, 0x00, 0x00, // ECALL
    };
    try std.testing.expectEqual(TestResult.unexpected_ecall, runTest(&program));
}

test "runTest: EBREAK with gp == 1 passes; gp == (N << 1 | 1) fails test N" {
    const pass = [_]u8{
        0x93, 0x01, 0x10, 0x00, // ADDI x3, x0, 1
        0x73, 0x00, 0x10, 0x00, // EBREAK
    };
    try std.testing.expectEqual(TestResult.pass, runTest(&pass));
    const fail = [_]u8{
        0x93, 0x01, 0x70, 0x00, // ADDI x3, x0, 7  (test case 3 failed)
        0x73, 0x00, 0x10, 0x00, // EBREAK
    };
    try std.testing.expectEqual(TestResult{ .fail = 3 }, runTest(&fail));
}
