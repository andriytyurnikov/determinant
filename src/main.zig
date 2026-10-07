//! CLI executable: loads flat binary, runs VM, prints disassembly and register dump.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

pub const DumpFormat = enum { hexdump, raw };

/// Process exit status.
pub const ExitStatus = enum(u8) {
    /// The program stopped at ECALL or EBREAK (or --help was shown).
    ok = 0,
    /// Usage error, or an I/O error (unreadable file, output that cannot be written).
    usage_or_io = 1,
    /// The cycle limit (--max-cycles) was reached before the program stopped.
    cycle_limit = 2,
    /// The VM raised a fault: illegal instruction, misaligned or out-of-bounds access, ...
    vm_fault = 3,
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(Io.File.stdout(), io, &stdout_buffer);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_fw: Io.File.Writer = .init(Io.File.stderr(), io, &stderr_buffer);

    const args = try init.minimal.args.toSlice(arena);
    return run(io, &stdout_fw.interface, &stderr_fw.interface, args);
}

/// Run the CLI: parse the arguments, run the program and flush the output. Returns
/// the process exit status (see ExitStatus). Failures, including output that cannot
/// be written, are reported on stderr and give a non-zero status, never a stack trace.
pub fn run(io: Io, stdout: *Io.Writer, stderr: *Io.Writer, args: []const [:0]const u8) u8 {
    const status: ExitStatus = mainInner(io, stdout, stderr, args) catch |err| switch (err) {
        error.UserError => .usage_or_io, // already reported
        error.WriteFailed => return outputFailed(stderr),
        else => blk: {
            stderr.print("Error: {s}\n", .{@errorName(err)}) catch {};
            break :blk .usage_or_io;
        },
    };
    // Flush with error checking: buffered output that cannot be written must not
    // end in a zero exit status.
    stdout.flush() catch return outputFailed(stderr);
    stderr.flush() catch {};
    return @intFromEnum(status);
}

fn outputFailed(stderr: *Io.Writer) u8 {
    stderr.print("Error: cannot write output\n", .{}) catch {};
    stderr.flush() catch {};
    return @intFromEnum(ExitStatus.usage_or_io);
}

/// Exact memory size for messages: "64 KiB", "1 MiB" or "100 bytes".
const MemSize = struct {
    bytes: u32,

    pub fn format(self: MemSize, w: *Io.Writer) Io.Writer.Error!void {
        if (self.bytes % (1024 * 1024) == 0) return w.print("{d} MiB", .{self.bytes / (1024 * 1024)});
        if (self.bytes % 1024 == 0) return w.print("{d} KiB", .{self.bytes / 1024});
        return w.print("{d} bytes", .{self.bytes});
    }
};

const vm_mem_size: MemSize = .{ .bytes = det.Cpu.mem_size };

pub fn mainInner(
    io: Io,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    args: []const [:0]const u8,
) !ExitStatus {
    // args[0] is the program name; iterate args[1..].
    var path: ?[]const u8 = null;
    var max_cycles: ?u64 = null; // unlimited
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
            try stdout.print("Compiled with {f} of VM memory.\n", .{vm_mem_size});
            try stdout.print("\nExit status: 0 stopped at ECALL/EBREAK, 1 usage or I/O error,\n", .{});
            try stdout.print("             2 cycle limit reached, 3 VM fault.\n", .{});
            return .ok;
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
        return runFile(io, stdout, stderr, p, max_cycles, dump_format);
    } else {
        return runDemo(stdout, stderr, max_cycles, dump_format);
    }
}

/// Exit status for the way a run stopped.
fn stopStatus(result: det.StepResult) ExitStatus {
    return switch (result) {
        .ecall, .ebreak => .ok,
        .@"continue" => .cycle_limit,
    };
}

/// Built-in 5-instruction RV32I demo program:
///   ADDI x1, x0, 100    — x1 = 100
///   ADDI x2, x0, 10     — x2 = 10
///   ADD  x3, x1, x2     — x3 = x1 + x2 = 110
///   SW   x3, 0(x1)      — mem[100] = 110
///   ECALL                — system call
pub const demo_program = [_]u8{
    0x93, 0x00, 0x40, 0x06, // ADDI x1, x0, 100
    0x13, 0x01, 0xA0, 0x00, // ADDI x2, x0, 10
    0xB3, 0x81, 0x20, 0x00, // ADD  x3, x1, x2
    0x23, 0xA0, 0x30, 0x00, // SW   x3, 0(x1)
    0x73, 0x00, 0x00, 0x00, // ECALL
};

/// Address the demo program stores its result to.
pub const demo_store_addr: u32 = 100;

/// Smallest VM memory in which the demo runs to completion (its store must fit).
pub const demo_min_memory: u32 = demo_store_addr + 4;

/// Allocate a zeroed VM on the heap. The VM embeds its whole memory, so it must not
/// live on the stack: a few MiB of memory would overflow it.
fn createVm() !*det.Cpu {
    const vm = try std.heap.page_allocator.create(det.Cpu);
    vm.reset();
    return vm;
}

fn destroyVm(vm: *det.Cpu) void {
    std.heap.page_allocator.destroy(vm);
}

pub fn runDemo(stdout: *Io.Writer, stderr: *Io.Writer, max_cycles: ?u64, dump_format: ?DumpFormat) !ExitStatus {
    try stdout.print("Determinant — RV32I Executor Demo ({f} memory)\n\n", .{vm_mem_size});

    const program = demo_program;

    // Load program into VM
    const vm = try createVm();
    defer destroyVm(vm);
    vm.loadProgram(&program, 0) catch {
        try stderr.print("Error: the demo program needs {d} bytes of VM memory, but only {f} are configured\n", .{ program.len, vm_mem_size });
        return error.UserError;
    };

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

    // Execute (the demo stops at its ECALL unless --max-cycles stops it first)
    try stdout.print("\nExecuting...\n", .{});
    const result = vm.run(max_cycles) catch |err| {
        try stderr.print("\nDemo execution error after {d} cycles at PC = 0x{X:0>8}: {s}\n", .{ vm.cycle_count, vm.pc, @errorName(err) });
        return .vm_fault;
    };

    try printResult(stdout, vm, result);

    // Show memory at store target (absent when memory is too small to hold it)
    if (vm.readWord(demo_store_addr)) |mem_val| {
        try stdout.print("\nMemory[{d}] = {d} (0x{X:0>8})\n", .{ demo_store_addr, mem_val, mem_val });
    } else |_| {}

    if (dump_format) |fmt| {
        try stdout.print("\n", .{});
        try dumpMemory(stdout, &vm.memory, fmt);
    }
    return stopStatus(result);
}

pub fn runFile(io: Io, stdout: *Io.Writer, stderr: *Io.Writer, path: []const u8, max_cycles: ?u64, dump_format: ?DumpFormat) !ExitStatus {
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

    const vm = try createVm();
    defer destroyVm(vm);

    if (stat.size > vm.memory.len) {
        try stderr.print("Error: file too large ({d} bytes, max {d})\n", .{ stat.size, vm.memory.len });
        return error.UserError;
    }

    const size: usize = @intCast(stat.size);

    // Read directly into VM memory instead of going through loadProgram(), to avoid
    // an intermediate buffer as large as the file. Direct memory writes must drop the
    // LR reservation (see clearReservation below).
    const n = file.readPositionalAll(io, vm.memory[0..size], 0) catch |err| {
        try stderr.print("Error: cannot read '{s}': {s}\n", .{ path, @errorName(err) });
        return error.UserError;
    };

    if (n != size) {
        try stderr.print("Error: short read ({d}/{d} bytes)\n", .{ n, size });
        return error.UserError;
    }
    vm.clearReservation();

    try stdout.print("Determinant — Loading {s} ({f} memory)\n\n", .{ path, vm_mem_size });

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
        return .vm_fault;
    };

    try printResult(stdout, vm, result);

    if (dump_format) |fmt| {
        try stdout.print("\n", .{});
        try dumpMemory(stdout, &vm.memory, fmt);
    }
    return stopStatus(result);
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
