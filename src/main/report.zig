//! The CLI's report (docs/design/cli.md): how the program stopped, a fault, the
//! registers and the trace lines, and the text of usage and I/O errors.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const disasm = @import("disasm.zig");
const units = @import("units.zig");

/// Where to look when something does not fit in memory.
pub const memory_hint = " (see --memory)";

/// How a run ended, unless it faulted.
pub const Stop = union(enum) {
    ebreak,
    /// An ECALL that is not a host call: the value of a7.
    ecall: u32,
    cycle_limit,
    /// The program called exit with this status (a0).
    exit: u32,
};

pub fn printStop(w: *Io.Writer, vm: anytype, stop: Stop) Io.Writer.Error!void {
    const n = units.cycles(vm.cycle_count);
    switch (stop) {
        .ebreak => try w.print("Stopped at EBREAK (0x{X:0>8}) after {f}\n", .{ vm.stop_pc, n }),
        .ecall => |a7| try w.print("Stopped at ECALL (0x{X:0>8}) after {f}: a7 = {d} is not a host call\n", .{ vm.stop_pc, n, a7 }),
        .cycle_limit => try w.print("Cycle limit reached after {f}\n", .{n}),
        .exit => |status| try w.print("Program exited with status {d} after {f}\n", .{ @as(i32, @bitCast(status)), n }),
    }
}

/// pc, then the non-zero registers: number, ABI name, hex and signed decimal.
pub fn printRegisters(w: *Io.Writer, vm: anytype) Io.Writer.Error!void {
    try w.print("\nRegisters:\n  pc        0x{X:0>8}\n", .{vm.pc});
    for (1..32) |i| {
        const val = vm.readReg(@intCast(i));
        if (val != 0) try w.print("  x{d:<2}  {s:<4} 0x{X:0>8}  {d}\n", .{ i, disasm.reg_names[i], val, @as(i32, @bitCast(val)) });
    }
}

pub fn faultText(err: det.StepError) []const u8 {
    return switch (err) {
        error.IllegalInstruction => "illegal instruction",
        error.MisalignedPC => "misaligned pc",
        error.PCOutOfBounds => "pc out of bounds",
        error.MisalignedAccess => "misaligned memory access",
        error.AddressOutOfBounds => "memory access out of bounds",
    };
}

/// Report a fault that just happened: the error, the instruction and the address.
pub fn printFault(w: *Io.Writer, vm: anytype, err: det.StepError) Io.Writer.Error!void {
    const fault = vm.describeFault(err);
    const mem_size: units.MemSize = .{ .bytes = vm.memSize() };
    try w.print("Fault after {f}: {s} ({s})\n", .{ units.cycles(vm.cycle_count), faultText(err), @errorName(err) });
    try w.print("  instruction at 0x{X:0>8}", .{fault.pc});
    const raw = fault.raw orelse {
        // Fetching the instruction was the fault.
        if (err == error.PCOutOfBounds) try w.print(", not inside the {f} of VM memory{s}", .{ mem_size, memory_hint });
        return w.writeAll("\n");
    };
    try w.print(": {f}  ", .{disasm.Bits{ .raw = raw, .pad = false }});
    if (det.decode(raw)) |inst| {
        try disasm.printInstruction(w, inst, fault.pc);
    } else |_| {
        try w.writeAll("(does not decode)");
    }
    try w.writeAll("\n");
    if (fault.addr) |addr| {
        try w.print("  data address 0x{X:0>8}", .{addr});
        if (err == error.AddressOutOfBounds) try w.print(", not inside the {f} of VM memory{s}", .{ mem_size, memory_hint });
        try w.writeAll("\n");
    }
}

/// One --trace line for the instruction that just retired: the cycle it retired in,
/// its address, bits and disassembly, and the register or memory it wrote.
pub fn printTraceLine(w: *Io.Writer, cycle: u64, pc: u32, raw: u32, vm: anytype) Io.Writer.Error!void {
    var line_buf: [128]u8 = undefined;
    var line: Io.Writer = .fixed(&line_buf);
    disasm.printLine(&line, pc, raw) catch {}; // longer than any line: never truncated
    try w.print("{d:>8}  ", .{cycle});

    const inst = det.decode(raw) catch return w.print("{s}\n", .{line.buffered()});
    switch (inst.op.format()) {
        .S => {
            const addr = vm.readReg(inst.rs1) +% inst.immUnsigned();
            const val = vm.readReg(inst.rs2);
            try w.print("{s:<46}  mem[0x{X:0>8}] = ", .{ line.buffered(), addr });
            switch (inst.op.i) {
                .SB => try w.print("0x{X:0>2}\n", .{@as(u8, @truncate(val))}),
                .SH => try w.print("0x{X:0>4}\n", .{@as(u16, @truncate(val))}),
                else => try w.print("0x{X:0>8}\n", .{val}),
            }
        },
        .B => try w.print("{s}\n", .{line.buffered()}),
        else => if (inst.rd != 0) {
            try w.print("{s:<46}  {s} = 0x{X:0>8}\n", .{ line.buffered(), disasm.reg_names[inst.rd], vm.readReg(inst.rd) });
        } else {
            try w.print("{s}\n", .{line.buffered()});
        },
    }
}

/// An I/O error in words, for messages such as "cannot open 'x': no such file".
pub fn ioText(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "no such file",
        error.IsDir => "is a directory",
        error.NotDir => "a part of the path is not a directory",
        error.AccessDenied, error.PermissionDenied => "permission denied",
        error.StreamTooLong, error.FileTooBig => "too large",
        error.NameTooLong => "name too long",
        error.SymLinkLoop => "too many symbolic links",
        error.OutOfMemory => "out of memory",
        else => @errorName(err),
    };
}

/// Report a usage or I/O error on `w` ("Error: ..."), and return error.UserError.
pub fn userError(w: *Io.Writer, comptime fmt: []const u8, args: anytype) error{ UserError, WriteFailed } {
    w.print("Error: " ++ fmt ++ "\n", args) catch |err| return err;
    return error.UserError;
}
