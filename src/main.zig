const std = @import("std");
const det = @import("determinant");

pub fn main() !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = std.process.args();
    _ = args.next(); // skip program name
    const file_path = args.next();

    if (file_path) |path| {
        runBinary(path, stdout) catch |err| {
            try stdout.flush();
            var stderr_buffer: [4096]u8 = undefined;
            var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
            const stderr = &stderr_writer.interface;
            try stderr.print("determinant: error: {s}\n", .{@errorName(err)});
            try stderr.flush();
            std.process.exit(1);
        };
        try stdout.flush();
    } else {
        try runDemo(stdout);
        try stdout.flush();
    }
}

fn runBinary(path: []const u8, stdout: anytype) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const size: usize = @intCast(stat.size);

    if (size == 0) return error.EmptyFile;
    if (size > det.cpu.MEMORY_SIZE) return error.FileTooLarge;

    var vm = det.Cpu.init();
    const bytes_read = try file.readAll(vm.memory[0..size]);
    if (bytes_read != size) return error.IncompleteRead;

    const exit_code = try det.runWithSyscalls(&vm, 0, stdout);
    if (exit_code) |code| {
        if (code != 0) {
            try stdout.flush();
            std.process.exit(@truncate(code));
        }
    }
}

fn runDemo(stdout: anytype) !void {
    try stdout.print("Determinant — RV32I Executor Demo\n\n", .{});

    // Hardcoded 5-instruction RV32I program:
    //   ADDI x1, x0, 100    — x1 = 100
    //   ADDI x2, x0, 10     — x2 = 10
    //   ADD  x3, x1, x2     — x3 = x1 + x2 = 110
    //   SW   x3, 0(x1)      — mem[100] = 110
    //   ECALL                — system call
    const program = [_]u32{
        0x06400093, // ADDI x1, x0, 100
        0x00A00113, // ADDI x2, x0, 10
        0x002081B3, // ADD  x3, x1, x2
        0x0030A023, // SW   x3, 0(x1)
        0x00000073, // ECALL
    };

    // Load program into VM
    var vm = det.Cpu.init();
    const program_bytes = std.mem.sliceAsBytes(&program);
    try vm.loadProgram(program_bytes, 0);

    // Decode and display instructions
    try stdout.print("Program:\n", .{});
    for (program, 0..) |word, i| {
        const addr = i * 4;
        if (det.decode(word)) |inst| {
            try stdout.print("  0x{X:0>4}: ", .{addr});
            try printInstruction(stdout, inst);
            try stdout.print("\n", .{});
        } else |err| {
            try stdout.print("  0x{X:0>4}: ??? (error: {s})\n", .{ addr, @errorName(err) });
        }
    }

    // Execute
    try stdout.print("\nExecuting...\n", .{});
    const result = try vm.run(0);

    // Print result
    try stdout.print("\nExecution complete ({s} after {d} cycles)\n", .{ @tagName(result), vm.cycle_count });
    try stdout.print("\nRegisters:\n", .{});
    for (0..32) |i| {
        const val = vm.readReg(@intCast(i));
        if (val != 0) {
            try stdout.print("  x{d} = {d} (0x{X:0>8})\n", .{ i, val, val });
        }
    }

    // Show memory at store target
    const mem_val = std.mem.readInt(u32, vm.memory[100..104], .little);
    try stdout.print("\nMemory[100] = {d} (0x{X:0>8})\n", .{ mem_val, mem_val });
}

fn printInstruction(stdout: anytype, inst: det.Instruction) !void {
    const op_name = @tagName(inst.op);
    switch (inst.op.format()) {
        .R => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
        .I => switch (inst.op) {
            .LB, .LH, .LW, .LBU, .LHU, .JALR => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rd, inst.imm, inst.rs1 }),
            .ECALL, .EBREAK => try stdout.print("{s}", .{op_name}),
            else => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rd, inst.rs1, inst.imm }),
        },
        .S => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rs2, inst.imm, inst.rs1 }),
        .B => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rs1, inst.rs2, inst.imm }),
        .U => try stdout.print("{s} x{d}, 0x{X}", .{ op_name, inst.rd, @as(u32, @bitCast(inst.imm)) >> 12 }),
        .J => try stdout.print("{s} x{d}, {d}", .{ op_name, inst.rd, inst.imm }),
    }
}
