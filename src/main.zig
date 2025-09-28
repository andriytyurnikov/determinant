//! CLI executable: loads flat binary, runs VM, prints disassembly and register dump.

const std = @import("std");
const det = @import("determinant");

const unlimited_cycles: u64 = 0;

pub fn main() !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var args = std.process.args();
    mainInner(stdout, stderr, &args) catch |err| switch (err) {
        error.UserError => {
            stdout.flush() catch {};
            stderr.flush() catch {};
            std.process.exit(1);
        },
        else => return err,
    };
}

pub fn mainInner(stdout: anytype, stderr: anytype, args: anytype) !void {
    _ = args.next(); // skip program name

    if (args.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
            try stdout.print("Usage: determinant [<file> [--max-cycles N]]\n\n", .{});
            try stdout.print("  <file>           RISC-V binary to load and execute\n", .{});
            try stdout.print("  --max-cycles N   Maximum execution cycles (default: unlimited, 0 = unlimited)\n", .{});
            try stdout.print("\nWith no arguments, runs a built-in demo program.\n", .{});
            try stdout.print("Compiled with {d} KB VM memory.\n", .{det.Cpu.mem_size / 1024});
            return;
        }

        // Detect flags used before file path
        if (first_arg.len >= 2 and first_arg[0] == '-') {
            try stderr.print("Error: unexpected option '{s}'. File path must come before options.\n", .{first_arg});
            try stderr.print("Usage: determinant [<file> [--max-cycles N]]\n", .{});
            return error.UserError;
        }

        const path = first_arg;
        var max_cycles: u64 = unlimited_cycles;
        // Check for --max-cycles N
        if (args.next()) |flag| {
            if (std.mem.eql(u8, flag, "--max-cycles")) {
                if (args.next()) |val| {
                    max_cycles = std.fmt.parseInt(u64, val, 10) catch {
                        try stderr.print("Error: invalid --max-cycles value\n", .{});
                        return error.UserError;
                    };
                } else {
                    try stderr.print("Error: --max-cycles requires a value\n", .{});
                    return error.UserError;
                }
            } else {
                try stderr.print("Error: unknown option '{s}'\n", .{flag});
                return error.UserError;
            }
        }
        if (args.next()) |extra| {
            try stderr.print("Warning: ignoring extra argument '{s}'\n", .{extra});
        }
        try runFile(stdout, stderr, path, max_cycles);
    } else {
        try runDemo(stdout);
    }
}

pub fn runDemo(stdout: anytype) !void {
    try stdout.print("Determinant — RV32I Executor Demo ({d} KB memory)\n\n", .{det.Cpu.mem_size / 1024});

    // Hardcoded 5-instruction RV32I program:
    //   ADDI x1, x0, 100    — x1 = 100
    //   ADDI x2, x0, 10     — x2 = 10
    //   ADD  x3, x1, x2     — x3 = x1 + x2 = 110
    //   SW   x3, 0(x1)      — mem[100] = 110
    //   ECALL                — system call
    const program = [_]u8{
        0x93, 0x00, 0x40, 0x06, // ADDI x1, x0, 100
        0x13, 0x01, 0xA0, 0x00, // ADDI x2, x0, 10
        0xB3, 0x81, 0x20, 0x00, // ADD  x3, x1, x2
        0x23, 0xA0, 0x30, 0x00, // SW   x3, 0(x1)
        0x73, 0x00, 0x00, 0x00, // ECALL
    };

    // Load program into VM
    var vm = det.Cpu.init();
    try vm.loadProgram(&program, 0);

    // Decode and display instructions
    try stdout.print("Program:\n", .{});
    {
        var addr: usize = 0;
        while (addr < program.len) {
            const remaining = program[addr..];
            if (remaining.len < 2) break;
            const half = std.mem.readInt(u16, remaining[0..2], .little);
            if (det.instructions.isCompressed(@as(u32, half))) {
                // 16-bit compressed
                if (det.decode(@as(u32, half))) |inst| {
                    try stdout.print("  0x{X:0>8}: ", .{addr});
                    try printInstruction(stdout, inst);
                    try stdout.print("\n", .{});
                } else |err| {
                    try stdout.print("  0x{X:0>8}: ??? (error: {s})\n", .{ addr, @errorName(err) });
                }
                addr += 2;
            } else {
                // 32-bit
                if (remaining.len < 4) break;
                const word = std.mem.readInt(u32, remaining[0..4], .little);
                if (det.decode(word)) |inst| {
                    try stdout.print("  0x{X:0>8}: ", .{addr});
                    try printInstruction(stdout, inst);
                    try stdout.print("\n", .{});
                } else |err| {
                    try stdout.print("  0x{X:0>8}: ??? (error: {s})\n", .{ addr, @errorName(err) });
                }
                addr += 4;
            }
        }
    }

    // Execute — unlimited cycles (demo terminates via ECALL)
    try stdout.print("\nExecuting...\n", .{});
    const result = try vm.run(unlimited_cycles);

    try printResult(stdout, &vm, result);

    // Show memory at store target
    const mem_val = std.mem.readInt(u32, vm.memory[100..][0..4], .little);
    try stdout.print("\nMemory[100] = {d} (0x{X:0>8})\n", .{ mem_val, mem_val });
}

pub fn runFile(stdout: anytype, stderr: anytype, path: []const u8, max_cycles: u64) !void {
    // Open and read the binary file
    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try stderr.print("Error: cannot open '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        try stderr.print("Error: cannot stat '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };
    if (stat.size == 0) {
        try stderr.print("Error: file is empty\n", .{});
        return error.UserError;
    }

    var vm = det.Cpu.init();

    if (stat.size > vm.memory.len) {
        try stderr.print("Error: file too large ({d} bytes, max {d})\n", .{ stat.size, vm.memory.len });
        return error.UserError;
    }

    const size: usize = @intCast(stat.size);

    // Read directly into VM memory — equivalent to loadProgram() but avoids
    // an intermediate buffer. If loadProgram() gains side effects beyond memcpy,
    // this must be updated to match.
    const n = file.readAll(vm.memory[0..size]) catch |err| {
        try stderr.print("Error: cannot read '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };

    if (n != size) {
        try stderr.print("Error: short read ({d}/{d} bytes)\n", .{ n, size });
        return error.UserError;
    }

    try stdout.print("Determinant — Loading {s} ({d} KB memory)\n\n", .{ path, det.Cpu.mem_size / 1024 });

    if (max_cycles > 0) {
        try stdout.print("Loaded {d} bytes, executing (max {d} cycles)...\n", .{ size, max_cycles });
    } else {
        try stdout.print("Loaded {d} bytes, executing (unlimited cycles)...\n", .{size});
    }

    const result = vm.run(max_cycles) catch |err| {
        try stderr.print("\nExecution error after {d} cycles at PC = 0x{X:0>8}: {s}\n", .{ vm.cycle_count, vm.pc, @errorName(err) });
        try stderr.print("\nRegisters:\n", .{});
        for (0..32) |i| {
            const val = vm.readReg(@intCast(i));
            if (val != 0) {
                try stderr.print("  x{d} = {d} (0x{X:0>8})\n", .{ i, @as(i32, @bitCast(val)), val });
            }
        }
        return error.UserError;
    };

    try printResult(stdout, &vm, result);
}

pub fn printResult(stdout: anytype, vm: *const det.Cpu, result: det.StepResult) !void {
    switch (result) {
        .@"continue" => try stdout.print("\nCycle limit reached after {d} cycles (program did not terminate)\n", .{vm.cycle_count}),
        .ecall, .ebreak => try stdout.print("\nExecution complete ({s} after {d} cycles)\n", .{ @tagName(result), vm.cycle_count }),
    }
    try stdout.print("PC = 0x{X:0>8}\n", .{vm.pc});
    try stdout.print("\nRegisters:\n", .{});
    for (0..32) |i| {
        const val = vm.readReg(@intCast(i));
        if (val != 0) {
            try stdout.print("  x{d} = {d} (0x{X:0>8})\n", .{ i, @as(i32, @bitCast(val)), val });
        }
    }
}

pub fn printInstruction(stdout: anytype, inst: det.Instruction) !void {
    const op_name = if (inst.compressed_op) |c_op| c_op.name() else inst.op.name();
    switch (inst.op) {
        .i => |i_op| switch (i_op) {
            .ADD, .SUB, .SLL, .SLT, .SLTU, .XOR, .SRL, .SRA, .OR, .AND => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
            .LB, .LH, .LW, .LBU, .LHU, .JALR => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rd, inst.imm, inst.rs1 }),
            .FENCE, .FENCE_I, .ECALL, .EBREAK => try stdout.print("{s}", .{op_name}),
            .SB, .SH, .SW => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rs2, inst.imm, inst.rs1 }),
            .BEQ, .BNE, .BLT, .BGE, .BLTU, .BGEU => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rs1, inst.rs2, inst.imm }),
            .LUI, .AUIPC => try stdout.print("{s} x{d}, 0x{X}", .{ op_name, inst.rd, inst.immUnsigned() >> 12 }),
            .JAL => try stdout.print("{s} x{d}, {d}", .{ op_name, inst.rd, inst.imm }),
            .ADDI, .SLTI, .SLTIU, .XORI, .ORI, .ANDI, .SLLI, .SRLI, .SRAI => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rd, inst.rs1, inst.imm }),
        },
        .m => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
        .a => |a_op| switch (a_op) {
            .LR_W => try stdout.print("{s} x{d}, (x{d})", .{ op_name, inst.rd, inst.rs1 }),
            .SC_W => try stdout.print("{s} x{d}, x{d}, (x{d})", .{ op_name, inst.rd, inst.rs2, inst.rs1 }),
            else => try stdout.print("{s} x{d}, x{d}, (x{d})", .{ op_name, inst.rd, inst.rs2, inst.rs1 }),
        },
        .csr => |csr_op| {
            const csr_addr = inst.csrAddr();
            switch (csr_op) {
                .CSRRW, .CSRRS, .CSRRC => try stdout.print("{s} x{d}, 0x{X:0>3}, x{d}", .{ op_name, inst.rd, csr_addr, inst.rs1 }),
                .CSRRWI, .CSRRSI, .CSRRCI => try stdout.print("{s} x{d}, 0x{X:0>3}, {d}", .{ op_name, inst.rd, csr_addr, inst.rs1 }),
            }
        },
        .zba => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
        .zbb => |bb_op| switch (bb_op) {
            .CLZ, .CTZ, .CPOP, .SEXT_B, .SEXT_H, .ZEXT_H, .ORC_B, .REV8 => try stdout.print("{s} x{d}, x{d}", .{ op_name, inst.rd, inst.rs1 }),
            .RORI => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rd, inst.rs1, inst.imm }),
            .ANDN, .ORN, .XNOR, .MAX, .MAXU, .MIN, .MINU, .ROL, .ROR => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
        },
        .zbs => |bs_op| switch (bs_op) {
            .BCLR, .BEXT, .BINV, .BSET => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
            .BCLRI, .BEXTI, .BINVI, .BSETI => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rd, inst.rs1, inst.imm }),
        },
    }
}

test {
    _ = @import("main/tests.zig");
}
