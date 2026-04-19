//! CLI executable: loads flat binary, runs VM, prints disassembly and register dump.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

const unlimited_cycles: ?u64 = null;

pub const DumpFormat = enum { hexdump, raw };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(Io.File.stdout(), io, &stdout_buffer);
    const stdout: *Io.Writer = &stdout_fw.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_fw: Io.File.Writer = .init(Io.File.stderr(), io, &stderr_buffer);
    const stderr: *Io.Writer = &stderr_fw.interface;

    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const args = try init.minimal.args.toSlice(arena);

    mainInner(io, stdout, stderr, args) catch |err| switch (err) {
        error.UserError => {
            stdout.flush() catch {};
            stderr.flush() catch {};
            std.process.exit(1);
        },
        else => return err,
    };
}

pub fn mainInner(
    io: Io,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    args: []const [:0]const u8,
) !void {
    // args[0] is the program name; iterate args[1..].
    var path: ?[]const u8 = null;
    var max_cycles: ?u64 = unlimited_cycles;
    var dump_format: ?DumpFormat = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout.print("Usage: determinant [<file>] [--max-cycles N] [--dump-memory [raw]]\n\n", .{});
            try stdout.print("  <file>              RISC-V binary to load and execute\n", .{});
            try stdout.print("  --max-cycles N      Maximum execution cycles (default: unlimited)\n", .{});
            try stdout.print("  --dump-memory [raw] Dump VM memory after execution (hexdump or raw hex)\n", .{});
            try stdout.print("\nWith no arguments, runs a built-in demo program.\n", .{});
            try stdout.print("Compiled with {d} KB VM memory.\n", .{det.Cpu.mem_size / 1024});
            return;
        } else if (std.mem.eql(u8, arg, "--max-cycles")) {
            i += 1;
            if (i < args.len) {
                max_cycles = std.fmt.parseInt(u64, args[i], 10) catch {
                    try stderr.print("Error: invalid --max-cycles value\n", .{});
                    return error.UserError;
                };
            } else {
                try stderr.print("Error: --max-cycles requires a value\n", .{});
                return error.UserError;
            }
        } else if (std.mem.eql(u8, arg, "--dump-memory")) {
            dump_format = .hexdump;
            // Peek at next arg for optional "raw" format
            if (i + 1 < args.len and std.mem.eql(u8, args[i + 1], "raw")) {
                dump_format = .raw;
                i += 1;
            }
        } else if (arg.len >= 1 and arg[0] == '-') {
            try stderr.print("Error: unknown option '{s}'\n", .{arg});
            return error.UserError;
        } else {
            if (path != null) {
                try stderr.print("Warning: ignoring extra argument '{s}'\n", .{arg});
            } else {
                path = arg;
            }
        }
    }

    if (path) |p| {
        try runFile(io, stdout, stderr, p, max_cycles, dump_format);
    } else {
        try runDemo(stdout, stderr, dump_format);
    }
}

pub fn runDemo(stdout: *Io.Writer, stderr: *Io.Writer, dump_format: ?DumpFormat) !void {
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
    const result = vm.run(unlimited_cycles) catch |err| {
        try stderr.print("\nDemo execution error after {d} cycles at PC = 0x{X:0>8}: {s}\n", .{ vm.cycle_count, vm.pc, @errorName(err) });
        return error.UserError;
    };

    try printResult(stdout, &vm, result);

    // Show memory at store target
    const mem_val = std.mem.readInt(u32, vm.memory[100..][0..4], .little);
    try stdout.print("\nMemory[100] = {d} (0x{X:0>8})\n", .{ mem_val, mem_val });

    if (dump_format) |fmt| {
        try stdout.print("\n", .{});
        try dumpMemory(stdout, &vm.memory, fmt);
    }
}

pub fn runFile(io: Io, stdout: *Io.Writer, stderr: *Io.Writer, path: []const u8, max_cycles: ?u64, dump_format: ?DumpFormat) !void {
    // Open and read the binary file
    var file = Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
        try stderr.print("Error: cannot open '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };
    defer file.close(io);

    const stat = file.stat(io) catch |err| {
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
    const n = file.readPositionalAll(io, vm.memory[0..size], 0) catch |err| {
        try stderr.print("Error: cannot read '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };

    if (n != size) {
        try stderr.print("Error: short read ({d}/{d} bytes)\n", .{ n, size });
        return error.UserError;
    }

    try stdout.print("Determinant — Loading {s} ({d} KB memory)\n\n", .{ path, det.Cpu.mem_size / 1024 });

    if (max_cycles) |mc| {
        try stdout.print("Loaded {d} bytes, executing (max {d} cycles)...\n", .{ size, mc });
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

    if (dump_format) |fmt| {
        try stdout.print("\n", .{});
        try dumpMemory(stdout, &vm.memory, fmt);
    }
}

pub fn printResult(stdout: *Io.Writer, vm: *const det.Cpu, result: det.StepResult) !void {
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

pub fn printInstruction(stdout: *Io.Writer, inst: det.Instruction) !void {
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

pub fn dumpMemory(stdout: *Io.Writer, memory: []const u8, format: DumpFormat) !void {
    switch (format) {
        .hexdump => try dumpHexdump(stdout, memory),
        .raw => try dumpRaw(stdout, memory),
    }
}

fn dumpHexdump(stdout: *Io.Writer, memory: []const u8) !void {
    var prev_line: ?*const [16]u8 = null;
    var collapsing = false;
    var offset: usize = 0;

    while (offset < memory.len) : (offset += 16) {
        const remaining = memory.len - offset;
        const line_len = if (remaining >= 16) 16 else remaining;
        const line = memory[offset..][0..line_len];

        // Check for collapsible repeated line (only full 16-byte lines)
        if (line_len == 16) {
            if (prev_line) |prev| {
                if (std.mem.eql(u8, line, prev)) {
                    if (!collapsing) {
                        try stdout.print("*\n", .{});
                        collapsing = true;
                    }
                    continue;
                }
            }
        }

        collapsing = false;

        // Address
        try stdout.print("{X:0>8}  ", .{offset});

        // Hex bytes — first group of 8
        for (0..8) |j| {
            if (j < line_len) {
                try stdout.print("{X:0>2} ", .{line[j]});
            } else {
                try stdout.print("   ", .{});
            }
        }
        try stdout.print(" ", .{});

        // Hex bytes — second group of 8
        for (8..16) |j| {
            if (j < line_len) {
                try stdout.print("{X:0>2} ", .{line[j]});
            } else {
                try stdout.print("   ", .{});
            }
        }

        // ASCII
        try stdout.print(" |", .{});
        for (0..line_len) |j| {
            const c = line[j];
            if (c >= 0x20 and c <= 0x7E) {
                try stdout.print("{c}", .{c});
            } else {
                try stdout.print(".", .{});
            }
        }
        try stdout.print("|\n", .{});

        if (line_len == 16) {
            prev_line = memory[offset..][0..16];
        } else {
            prev_line = null;
        }
    }

    // Final address line (total size)
    try stdout.print("{X:0>8}\n", .{memory.len});
}

fn dumpRaw(stdout: *Io.Writer, memory: []const u8) !void {
    var offset: usize = 0;
    while (offset < memory.len) : (offset += 32) {
        const remaining = memory.len - offset;
        const line_len = if (remaining >= 32) 32 else remaining;
        for (0..line_len) |j| {
            try stdout.print("{X:0>2}", .{memory[offset + j]});
        }
        try stdout.print("\n", .{});
    }
}

test {
    _ = @import("main/tests.zig");
}
