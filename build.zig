const std = @import("std");

const Decoder = enum { lut, branch };
const default_memory_size: u32 = 64 * 1024;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const decoder_choice = b.option(Decoder, "decoder", "Instruction decoder backend (default: lut)") orelse .lut;
    const memory_size: u32 = b.option(u32, "memory_size", "VM memory size in bytes (default: 65536, must be >= 4 and divisible by 4)") orelse default_memory_size;
    if (memory_size < 4 or memory_size % 4 != 0) {
        std.log.err("invalid -Dmemory_size={d}: it must be at least 4 and a multiple of 4", .{memory_size});
        b.invalid_user_input = true;
    }

    // Library module
    const mod = b.addModule("determinant", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", buildOptions(b, decoder_choice, memory_size));

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "determinant",
        .root_module = cliModule(b, mod, target, optimize),
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test suites for the selected decoder, and for the other one (test-all).
    const main_suites = addTestSuites(b, mod, exe.root_module, target, optimize);

    const other_decoder: Decoder = if (decoder_choice == .lut) .branch else .lut;
    const alt_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    alt_mod.addOptions("build_options", buildOptions(b, other_decoder, memory_size));
    const alt_suites = addTestSuites(b, alt_mod, cliModule(b, alt_mod, target, optimize), target, optimize);

    const test_step = b.step("test", "Run unit and CLI tests");
    test_step.dependOn(main_suites.unit);
    test_step.dependOn(main_suites.cli);

    const compliance_step = b.step("test-compliance", "Run RISC-V compliance tests");
    compliance_step.dependOn(main_suites.compliance);

    // Print the corpus digest table (regenerate tests/digests.txt with it)
    const digests_step = b.step("digests", "Print the final-state digest of every corpus program");
    const print_digests = b.addRunArtifact(main_suites.digests_exe);
    print_digests.addDirectoryArg(b.path("src/compliance/bin"));
    digests_step.dependOn(&print_digests.step);

    const check_digests_step = b.step("test-digests", "Check corpus final-state digests against tests/digests.txt (both decoders)");
    check_digests_step.dependOn(main_suites.digests);
    check_digests_step.dependOn(alt_suites.digests);

    // Test-all step: unit, CLI, compliance and digest tests, once per decoder
    const test_all_step = b.step("test-all", "Run unit, CLI, compliance and digest tests with both decoder backends");
    for ([_]TestSuites{ main_suites, alt_suites }) |suites| {
        test_all_step.dependOn(suites.unit);
        test_all_step.dependOn(suites.cli);
        test_all_step.dependOn(suites.compliance);
        test_all_step.dependOn(suites.digests);
    }

    // Exhaustive decoder equivalence over all 2^32 inputs. Always ReleaseFast:
    // in Debug it would take hours.
    const release_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    release_mod.addOptions("build_options", buildOptions(b, decoder_choice, memory_size));
    const verify_exe = b.addExecutable(.{
        .name = "verify-decoders",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/verify_decoders.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "determinant", .module = release_mod },
            },
        }),
    });
    const verify_step = b.step("verify-decoders", "Compare the LUT and branch decoders on all 2^32 inputs (ReleaseFast)");
    verify_step.dependOn(&b.addRunArtifact(verify_exe).step);
}

fn buildOptions(b: *std.Build, decoder: Decoder, memory_size: u32) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption(bool, "use_branch_decoder", decoder == .branch);
    options.addOption(u32, "memory_size", memory_size);
    return options;
}

fn cliModule(b: *std.Build, lib: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "determinant", .module = lib },
        },
    });
}

const TestSuites = struct {
    unit: *std.Build.Step,
    cli: *std.Build.Step,
    compliance: *std.Build.Step,
    /// Checks the corpus final-state digests against tests/digests.txt.
    digests: *std.Build.Step,
    digests_exe: *std.Build.Step.Compile,
};

/// Unit tests of the library, tests of the CLI, the riscv-tests compliance suite
/// (pre-compiled binaries) and the corpus digest check, all against one library module.
fn addTestSuites(
    b: *std.Build,
    lib: *std.Build.Module,
    cli: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) TestSuites {
    const unit_tests = b.addTest(.{ .root_module = lib });
    const cli_tests = b.addTest(.{ .root_module = cli });
    const compliance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/compliance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = lib },
            },
        }),
    });
    const digests_exe = b.addExecutable(.{
        .name = "corpus-digests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/corpus_digests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = lib },
            },
        }),
    });
    const check_digests = b.addRunArtifact(digests_exe);
    check_digests.addDirectoryArg(b.path("src/compliance/bin"));
    check_digests.addArg("--check");
    check_digests.addFileArg(b.path("tests/digests.txt"));
    check_digests.has_side_effects = true;
    return .{
        .unit = &b.addRunArtifact(unit_tests).step,
        .cli = &b.addRunArtifact(cli_tests).step,
        .compliance = &b.addRunArtifact(compliance_tests).step,
        .digests = &check_digests.step,
        .digests_exe = digests_exe,
    };
}
