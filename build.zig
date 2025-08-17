const std = @import("std");

const Decoder = enum { lut, branch };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const decoder_choice = b.option(Decoder, "decoder",
        "Instruction decoder backend (default: lut)") orelse .lut;

    const options = b.addOptions();
    options.addOption(bool, "use_branch_decoder", decoder_choice == .branch);

    // Library module
    const mod = b.addModule("determinant", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

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

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Test-all step: runs library tests with both decoder backends
    const alt_options = b.addOptions();
    alt_options.addOption(bool, "use_branch_decoder", decoder_choice != .branch);

    const alt_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    alt_mod.addOptions("build_options", alt_options);

    const alt_mod_tests = b.addTest(.{ .root_module = alt_mod });

    const test_all_step = b.step("test-all", "Run tests with both decoder backends");
    test_all_step.dependOn(&run_mod_tests.step);
    test_all_step.dependOn(&run_exe_tests.step);
    test_all_step.dependOn(&b.addRunArtifact(alt_mod_tests).step);
}
