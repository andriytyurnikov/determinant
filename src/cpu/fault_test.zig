//! Precise faults: every kind of fault leaves the whole architectural state unchanged
//! (SEMANTICS.md, "Faults"). Each case starts from a VM where every part of the state is
//! non-trivial — a live reservation, non-zero mscratch, cycle count, registers and
//! memory — and compares the full state digest before and after the faulting step.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const h = @import("../instructions/test_helpers.zig");
const Cpu = cpu_mod.TestCpu;

const mem_end: u32 = Cpu.mem_size;
const start_pc: u32 = 0x1000;
const reserved: u32 = 0x2000;

const Case = struct {
    name: []const u8,
    /// Instruction at pc: 32 bits, or 16 bits when `compressed`.
    inst: u32 = 0,
    compressed: bool = false,
    /// Register values the case needs (x1 is the usual address base).
    regs: []const struct { u5, u32 } = &.{},
    /// pc to fault at; no instruction is placed when this is set.
    pc: ?u32 = null,
    err: anyerror,
};

fn lw(rd: u5, rs1: u5, imm: u12) u32 {
    return h.encodeI(0b0000011, 0b010, rd, rs1, imm);
}
fn load(f3: u3, rd: u5, rs1: u5, imm: u12) u32 {
    return h.encodeI(0b0000011, f3, rd, rs1, imm);
}
fn csr(f3: u3, rd: u5, rs1: u5, addr: u12) u32 {
    return h.encodeCsr(f3, rd, rs1, addr);
}

const cases = [_]Case{
    // Decode
    .{ .name = "illegal 32-bit word", .inst = 0xFFFFFFFF, .err = error.IllegalInstruction },
    .{ .name = "illegal 16-bit (all zero)", .inst = 0x0000, .compressed = true, .err = error.IllegalInstruction },
    .{ .name = "reserved ECALL (rd = 5)", .inst = 0x00000073 | (5 << 7), .err = error.IllegalInstruction },
    .{ .name = "reserved LR.W (rs2 = 3)", .inst = h.encodeAtomic(0b00010, 5, 1, 3), .regs = &.{.{ 1, 0x3000 }}, .err = error.IllegalInstruction },
    // Fetch
    .{ .name = "odd pc", .pc = start_pc + 1, .err = error.MisalignedPC },
    .{ .name = "pc at the end of memory", .pc = mem_end, .err = error.PCOutOfBounds },
    .{ .name = "pc far out of bounds", .pc = 0xFFFF_FFFE, .err = error.PCOutOfBounds },
    // Loads
    .{ .name = "LH misaligned", .inst = load(0b001, 5, 1, 1), .regs = &.{.{ 1, 0x3000 }}, .err = error.MisalignedAccess },
    .{ .name = "LHU misaligned", .inst = load(0b101, 5, 1, 3), .regs = &.{.{ 1, 0x3000 }}, .err = error.MisalignedAccess },
    .{ .name = "LW misaligned (addr % 4 = 2)", .inst = lw(5, 1, 2), .regs = &.{.{ 1, 0x3000 }}, .err = error.MisalignedAccess },
    .{ .name = "LB out of bounds", .inst = load(0b000, 5, 1, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "LW out of bounds", .inst = lw(5, 1, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "LW at a wrapped address", .inst = lw(5, 1, 0xFFC), .regs = &.{.{ 1, 0 }}, .err = error.AddressOutOfBounds },
    .{ .name = "C.LW misaligned", .inst = 0x4000, .compressed = true, .regs = &.{.{ 8, 0x3002 }}, .err = error.MisalignedAccess }, // C.LW x8, 0(x8)
    // Stores
    .{ .name = "SB out of bounds", .inst = h.encodeS(0b000, 1, 2, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "SH misaligned", .inst = h.encodeS(0b001, 1, 2, 1), .regs = &.{.{ 1, reserved }}, .err = error.MisalignedAccess },
    .{ .name = "SH out of bounds", .inst = h.encodeS(0b001, 1, 2, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "SW misaligned onto the reserved word", .inst = h.encodeS(0b010, 1, 2, 2), .regs = &.{.{ 1, reserved }}, .err = error.MisalignedAccess },
    .{ .name = "SW out of bounds", .inst = h.encodeS(0b010, 1, 2, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "C.SW out of bounds", .inst = 0xC000, .compressed = true, .regs = &.{.{ 8, mem_end }}, .err = error.AddressOutOfBounds }, // C.SW x8, 0(x8)
    // Atomics
    .{ .name = "AMOADD.W misaligned", .inst = h.encodeAtomic(0b00000, 5, 1, 2), .regs = &.{.{ 1, reserved + 2 }}, .err = error.MisalignedAccess },
    .{ .name = "AMOSWAP.W out of bounds", .inst = h.encodeAtomic(0b00001, 5, 1, 2), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "LR.W misaligned", .inst = h.encodeAtomic(0b00010, 5, 1, 0), .regs = &.{.{ 1, 0x3001 }}, .err = error.MisalignedAccess },
    .{ .name = "LR.W out of bounds", .inst = h.encodeAtomic(0b00010, 5, 1, 0), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    .{ .name = "SC.W misaligned", .inst = h.encodeAtomic(0b00011, 5, 1, 2), .regs = &.{.{ 1, reserved + 2 }}, .err = error.MisalignedAccess },
    .{ .name = "SC.W out of bounds", .inst = h.encodeAtomic(0b00011, 5, 1, 2), .regs = &.{.{ 1, mem_end }}, .err = error.AddressOutOfBounds },
    // CSRs
    .{ .name = "CSRRW writes read-only cycle", .inst = csr(0b001, 5, 1, 0xC00), .err = error.IllegalInstruction },
    .{ .name = "CSRRW x0 writes read-only cycleh", .inst = csr(0b001, 0, 1, 0xC80), .err = error.IllegalInstruction },
    .{ .name = "CSRRSI writes read-only instret", .inst = csr(0b110, 5, 1, 0xC02), .err = error.IllegalInstruction },
    .{ .name = "CSRRC writes read-only instreth", .inst = csr(0b011, 5, 1, 0xC82), .regs = &.{.{ 1, 1 }}, .err = error.IllegalInstruction },
    .{ .name = "CSRRS reads absent time", .inst = csr(0b010, 5, 0, 0xC01), .err = error.IllegalInstruction },
    .{ .name = "CSRRS reads an unknown CSR", .inst = csr(0b010, 5, 0, 0x7C0), .err = error.IllegalInstruction },
    .{ .name = "CSRRW writes an unknown CSR", .inst = csr(0b001, 0, 1, 0x341), .err = error.IllegalInstruction },
};

/// A VM in which every piece of architectural state is non-trivial.
fn busyCpu(cpu: *Cpu) void {
    cpu.reset();
    for (1..32) |i| cpu.regs[i] = @as(u32, @intCast(i)) *% 0x0101_0101;
    for (&cpu.memory, 0..) |*b, i| b.* = @truncate(i *% 7 +% 3);
    cpu.pc = start_pc;
    cpu.cycle_count = 77;
    cpu.reservation = reserved;
    cpu.csrs.mscratch = 0x1234_5678;
}

test "faults are precise: the whole state is unchanged" {
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    for (cases) |c| {
        busyCpu(cpu);
        for (c.regs) |r| cpu.writeReg(r[0], r[1]);
        if (c.pc) |pc| {
            cpu.pc = pc;
        } else if (c.compressed) {
            std.mem.writeInt(u16, cpu.memory[start_pc..][0..2], @intCast(c.inst), .little);
        } else {
            std.mem.writeInt(u32, cpu.memory[start_pc..][0..4], c.inst, .little);
        }
        const before = cpu.stateDigest();
        const pc_before = cpu.pc;

        _ = cpu.step() catch |err| {
            if (err != c.err) {
                std.debug.print("{s}: expected {s}, got {s}\n", .{ c.name, @errorName(c.err), @errorName(err) });
                return error.TestUnexpectedError;
            }
            if (!std.mem.eql(u8, &before, &cpu.stateDigest())) {
                std.debug.print("{s}: state changed by the fault\n", .{c.name});
                return error.TestUnexpectedResult;
            }
            // The digest covers these too; checked by name for clearer failures.
            try std.testing.expectEqual(pc_before, cpu.pc);
            try std.testing.expectEqual(@as(u64, 77), cpu.cycle_count);
            try std.testing.expectEqual(@as(?u32, reserved), cpu.reservation);
            try std.testing.expectEqual(@as(u32, 0x1234_5678), cpu.csrs.mscratch);
            try std.testing.expectEqual(@as(u32, 0), cpu.regs[0]);
            continue;
        };
        std.debug.print("{s}: expected {s}, but the step succeeded\n", .{ c.name, @errorName(c.err) });
        return error.TestExpectedError;
    }
}

test "faults are precise: a faulting run() leaves the state as before the faulting step" {
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    busyCpu(cpu);
    // Two NOPs, then a load from out of bounds.
    std.mem.writeInt(u32, cpu.memory[start_pc..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[start_pc + 4 ..][0..4], 0x00000013, .little);
    std.mem.writeInt(u32, cpu.memory[start_pc + 8 ..][0..4], lw(5, 1, 0), .little);
    cpu.writeReg(1, mem_end);
    _ = try cpu.step();
    _ = try cpu.step();
    const before = cpu.stateDigest();
    try std.testing.expectError(error.AddressOutOfBounds, cpu.run(null));
    try std.testing.expectEqualSlices(u8, &before, &cpu.stateDigest());
    try std.testing.expectEqual(start_pc + 8, cpu.pc);
}
