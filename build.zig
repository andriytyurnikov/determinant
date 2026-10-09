const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const mod = b.addModule("determinant", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "determinant",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = mod },
            },
        }),
    });

    const cli_options = b.addOptions();
    cli_options.addOption([]const u8, "version", @import("build.zig.zon").version);
    exe.root_module.addOptions("cli_options", cli_options);

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    // Unit tests (library) and CLI tests (executable)
    const run_unit_tests = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
    const run_cli_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));
    const test_step = b.step("test", "Run unit and CLI tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_cli_tests.step);

    // Compliance tests: riscv-tests suite with pre-compiled binaries
    const compliance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/compliance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = mod },
            },
        }),
    });
    const run_compliance_tests = b.addRunArtifact(compliance_tests);
    const compliance_step = b.step("test-compliance", "Run RISC-V compliance tests");
    compliance_step.dependOn(&run_compliance_tests.step);

    // Corpus digests: compliance binaries and C programs, final state checked against
    // tests/digests.txt (and the C programs' results against native runs)
    const digests_exe = b.addExecutable(.{
        .name = "corpus-digests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/corpus_digests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = mod },
            },
        }),
    });
    const check_digests_step = b.step("test-digests", "Run the corpus (decode cache on and off, runtime memory) and check its final-state digests against tests/digests.txt");
    for ([_][]const u8{ "", "--no-decode-cache", "--runtime-memory" }) |flag| {
        const check_digests = b.addRunArtifact(digests_exe);
        addCorpusArgs(b, check_digests);
        if (flag.len != 0) check_digests.addArg(flag);
        check_digests.addArg("--check");
        check_digests.addFileArg(b.path("tests/digests.txt"));
        check_digests.has_side_effects = true;
        check_digests_step.dependOn(&check_digests.step);
    }

    // Print the corpus digest table (regenerate tests/digests.txt with it)
    const print_digests = b.addRunArtifact(digests_exe);
    addCorpusArgs(b, print_digests);
    const digests_step = b.step("digests", "Print the final-state digest of every corpus program");
    digests_step.dependOn(&print_digests.step);

    // A compliance suite rebuilt from source (CI rebuilds it with the distro's RISC-V
    // GCC): every binary must pass. Byte identity with src/compliance/bin is not
    // required, since other GCC/binutils versions encode a few tests differently.
    const rebuilt_dir = b.option([]const u8, "rebuilt_compliance", "Directory of riscv-tests binaries rebuilt with tests/riscv-tests/Makefile");
    const rebuilt_step = b.step("test-compliance-rebuild", "Check that every binary in -Drebuilt_compliance=DIR passes (riscv-tests convention)");
    if (rebuilt_dir) |dir| {
        const check_rebuilt = b.addRunArtifact(digests_exe);
        check_rebuilt.addArg(b.fmt("rebuilt={s}", .{dir}));
        check_rebuilt.addArgs(&.{ "--pass", "rebuilt" });
        check_rebuilt.has_side_effects = true;
        rebuilt_step.dependOn(&check_rebuilt.step);
    } else {
        rebuilt_step.dependOn(&b.addFail("test-compliance-rebuild needs -Drebuilt_compliance=DIR").step);
    }

    // Test-all step: unit, CLI, compliance and digest tests
    const test_all_step = b.step("test-all", "Run unit, CLI, compliance and digest tests");
    test_all_step.dependOn(&run_unit_tests.step);
    test_all_step.dependOn(&run_cli_tests.step);
    test_all_step.dependOn(&run_compliance_tests.step);
    test_all_step.dependOn(check_digests_step);

    // Tools that need speed are always built in fast mode.
    const release_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .fast,
    });

    // The decoder against its specification (decoders/registry.zig) on all 2^30
    // 32-bit encodings.
    const verify_exe = b.addExecutable(.{
        .name = "verify-decoder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/verify_decoder.zig"),
            .target = target,
            .optimize = .fast,
            .imports = &.{
                .{ .name = "determinant", .module = release_mod },
            },
        }),
    });
    const verify_step = b.step("verify-decoder", "Check the decoder against the opcode registry on all 2^30 32-bit encodings (optimize=fast)");
    verify_step.dependOn(&b.addRunArtifact(verify_exe).step);

    // Benchmark over the C program corpus.
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bench.zig"),
            .target = target,
            .optimize = .fast,
            .imports = &.{
                .{ .name = "determinant", .module = release_mod },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.addDirectoryArg2(b.path("tests/programs/bin"), .{});
    run_bench.addPassthruArgs();
    run_bench.has_side_effects = true;
    const bench_step = b.step("bench", "Benchmark the VM on the C program corpus (optimize=fast; pass -- --runs N)");
    bench_step.dependOn(&run_bench.step);

    // Opt-in verification tools that need software from outside this repository. They
    // are not part of test-all; see their READMEs.

    // The decoder against LLVM's RISC-V disassembler (tools/llvm_oracle), which is
    // loaded at run time from -Dllvm_lib.
    const llvm_lib = b.option([]const u8, "llvm_lib", "Absolute path of a shared libLLVM with the RISC-V target, for the llvm-oracle step");
    const llvm_oracle_step = b.step("llvm-oracle", "Compare the decoder with LLVM's RISC-V disassembler (optimize=fast; needs -Dllvm_lib; pass -- MODE ..., see tools/llvm_oracle)");
    if (llvm_lib) |lib| {
        const oracle_exe = b.addExecutable(.{
            .name = "llvm-oracle",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/llvm_oracle/oracle.zig"),
                .target = target,
                .optimize = .fast,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "determinant", .module = release_mod },
                },
            }),
        });
        const run_oracle = b.addRunArtifact(oracle_exe);
        run_oracle.addArg(lib);
        run_oracle.addPassthruArgs();
        run_oracle.has_side_effects = true;
        llvm_oracle_step.dependOn(&run_oracle.step);
    } else {
        llvm_oracle_step.dependOn(&b.addFail("llvm-oracle needs -Dllvm_lib=PATH, the absolute path of a shared libLLVM with the RISC-V target").step);
    }

    // The VM side of the Spike differential tests (tools/spike_diff): runs programs and
    // prints their final state. The tests themselves need Spike and a RISC-V GNU toolchain.
    const spike_runner = b.addExecutable(.{
        .name = "spike-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/spike_diff/runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "determinant", .module = mod },
            },
        }),
    });
    const spike_runner_step = b.step("spike-runner", "Build spike-runner for the Spike differential tests (see tools/spike_diff)");
    spike_runner_step.dependOn(&b.addInstallArtifact(spike_runner, .{}).step);

    addProgramsStep(b);
}

/// The corpus: the riscv-tests compliance binaries and the C programs, whose results
/// are also checked against a native run of the same C.
fn addCorpusArgs(b: *std.Build, run: *std.Build.Step.Run) void {
    run.addDirectoryArg2(b.path("src/compliance/bin"), .{ .prefix = "compliance=" });
    run.addDirectoryArg2(b.path("tests/programs/bin"), .{ .prefix = "programs=" });
    run.addArgs(&.{ "--pass", "compliance", "--expect" });
    run.addDirectoryArg2(b.path("tests/programs/expected"), .{ .prefix = "programs=" });
}

/// C programs of the corpus (tests/programs/src/<name>.c).
const corpus_programs = [_][]const u8{ "arith64", "atomics", "bitops", "crc32", "interp", "memops", "qsort", "recursion", "sha256", "sieve" };

/// The corpus is compiled twice, to cover both instruction mixes: with compressed
/// and bit-manipulation instructions at -O2, and without either at -Os.
const CorpusConfig = struct {
    name: []const u8,
    features: []const std.Target.riscv.Feature,
    optimize: std.lang.Optimize,
};
const corpus_configs = [_]CorpusConfig{
    .{ .name = "imac_zb-O2", .features = &.{ .m, .a, .c, .zba, .zbb, .zbs }, .optimize = .fast },
    .{ .name = "ima-Os", .features = &.{ .m, .a }, .optimize = .small },
};

/// `zig build programs`: rebuild the checked-in corpus binaries (tests/programs/bin)
/// with Zig's C compiler, and their expected results (tests/programs/expected) by
/// running the same C natively. Run it on a little-endian host.
fn addProgramsStep(b: *std.Build) void {
    const update = b.addUpdateSourceFiles();
    for (corpus_programs) |name| {
        for (corpus_configs) |cfg| {
            const target = b.resolveTargetQuery(.{
                .cpu_arch = .riscv32,
                .os_tag = .freestanding,
                .abi = .none,
                .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
                .cpu_features_add = std.Target.riscv.featureSet(cfg.features),
            });
            const exe = b.addExecutable(.{
                .name = name,
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = cfg.optimize,
                    .strip = true,
                }),
            });
            exe.root_module.addAssemblyFile(b.path("tests/programs/src/crt0.S"));
            exe.root_module.addCSourceFiles(.{
                .root = b.path("tests/programs/src"),
                .files = &.{ b.fmt("{s}.c", .{name}), "libmini.c" },
                .flags = &.{"-fno-builtin"},
            });
            exe.setLinkerScript(b.path("tests/programs/src/link.ld"));
            exe.entry = .{ .symbol_name = "_start" };
            const bin = b.addObjCopy(exe.getEmittedBin(), .{ .format = .binary });
            update.addCopyFileToSource(bin.getOutput(), b.fmt("tests/programs/bin/{s}/{s}.bin", .{ cfg.name, name }));
            // One ELF, for the CLI's ELF-loading test.
            if (std.mem.eql(u8, name, "crc32") and std.mem.eql(u8, cfg.name, "imac_zb-O2")) {
                update.addCopyFileToSource(exe.getEmittedBin(), "tests/programs/elf/crc32.elf");
            }
        }

        // Expected results: the same program built for the host and run natively
        // (debug, so the C undefined-behavior sanitizer would trap).
        const native = b.addExecutable(.{
            .name = b.fmt("{s}-native", .{name}),
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .debug,
                .link_libc = true,
            }),
        });
        native.root_module.addCSourceFiles(.{
            .root = b.path("tests/programs/src"),
            .files = &.{ b.fmt("{s}.c", .{name}), "native_main.c" },
        });
        const run_native = b.addRunArtifact(native);
        update.addCopyFileToSource(run_native.captureStdOut(.{}), b.fmt("tests/programs/expected/{s}.txt", .{name}));
    }
    const step = b.step("programs", "Rebuild the corpus binaries and expected results under tests/programs");
    step.dependOn(&update.step);
}
