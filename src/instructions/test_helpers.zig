//! Shared test utilities: memory helpers for any CpuType, instruction encoders, and
//! expectSteps(), the table runner for one-instruction tests.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const StepResult = cpu_mod.StepResult;

/// Store an instruction word at the CPU's current pc. Works with any CpuType.
pub fn loadInst(cpu: anytype, word: u32) void {
    std.mem.writeInt(u32, cpu.memory[cpu.pc..][0..4], word, .little);
}

pub fn storeWordAt(cpu: anytype, addr: u32, val: u32) void {
    const a: usize = addr;
    std.mem.writeInt(u32, cpu.memory[a..][0..4], val, .little);
}

pub fn readWordAt(cpu: anytype, addr: u32) u32 {
    const a: usize = addr;
    return std.mem.readInt(u32, cpu.memory[a..][0..4], .little);
}

pub fn storeHalfAt(cpu: anytype, addr: u32, val: u16) void {
    const a: usize = addr;
    std.mem.writeInt(u16, cpu.memory[a..][0..2], val, .little);
}

// --- Table-driven one-instruction tests ---

pub const RegVal = struct { u5, u32 };
pub const MemVal = struct { u32, u32 };

/// One instruction run on a fresh TestCpu: the setup fields are applied, `inst` is
/// stored at `pc` and executed with a single step(), then every expectation that is
/// set is checked.
pub const StepCase = struct {
    name: []const u8,
    inst: u32,
    // Setup
    pc: u32 = 0,
    regs: []const RegVal = &.{},
    /// Words stored before the instruction is (so they must not overlap it).
    mem: []const MemVal = &.{},
    mscratch: ?u32 = null,
    reservation: ?u32 = null,
    // Expectations
    /// The step must fail with this error (and then nothing else is checked but the
    /// fields listed below).
    err: ?anyerror = null,
    result: ?StepResult = null,
    /// Register values through readReg().
    want: []const RegVal = &.{},
    /// Raw regs[] values (to check x0 itself).
    want_raw: []const RegVal = &.{},
    want_mem: []const MemVal = &.{},
    want_pc: ?u32 = null,
    want_cycles: ?u64 = null,
    want_mscratch: ?u32 = null,
    /// Check the reservation (against want_reservation, null meaning none).
    check_reservation: bool = false,
    want_reservation: ?u32 = null,
};

pub fn expectSteps(cases: []const StepCase) !void {
    for (cases) |c| {
        expectStep(c) catch |err| {
            std.debug.print("step case \"{s}\" failed\n", .{c.name});
            return err;
        };
    }
}

fn expectStep(c: StepCase) !void {
    var cpu = Cpu.init();
    cpu.pc = c.pc;
    for (c.regs) |r| cpu.writeReg(r[0], r[1]);
    for (c.mem) |m| storeWordAt(&cpu, m[0], m[1]);
    loadInst(&cpu, c.inst);
    if (c.mscratch) |v| cpu.csrs.mscratch = v;
    if (c.reservation) |v| cpu.reservation = v;

    if (c.err) |want_err| {
        try std.testing.expectError(want_err, cpu.step());
    } else {
        const result = try cpu.step();
        if (c.result) |want_result| try std.testing.expectEqual(want_result, result);
    }
    for (c.want) |w| try std.testing.expectEqual(w[1], cpu.readReg(w[0]));
    for (c.want_raw) |w| try std.testing.expectEqual(w[1], cpu.regs[w[0]]);
    for (c.want_mem) |w| try std.testing.expectEqual(w[1], readWordAt(&cpu, w[0]));
    if (c.want_pc) |v| try std.testing.expectEqual(v, cpu.pc);
    if (c.want_cycles) |v| try std.testing.expectEqual(v, cpu.cycle_count);
    if (c.want_mscratch) |v| try std.testing.expectEqual(v, cpu.csrs.mscratch);
    if (c.check_reservation) try std.testing.expectEqual(c.want_reservation, cpu.reservation);
}

// --- Instruction encoding helpers (for tests) ---

pub fn encodeR(op: u7, f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

pub fn encodeI(op: u7, f3: u3, rd_v: u5, rs1_v: u5, imm12: u12) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, imm12) << 20);
}

/// R-type instruction in the OP opcode (0b0110011): RV32I, M, Zba, Zbb, Zbs register forms.
pub fn encodeOp(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    return encodeR(0b0110011, f3, f7, rd_v, rs1_v, rs2_v);
}

/// Shift-format OP-IMM instruction (0b0010011, funct3 001/101): f7 in [31:25], a 5-bit
/// shamt (or Zbb selector) in [24:20].
pub fn encodeOpImmShift(f3: u3, f7: u7, rd_v: u5, rs1_v: u5, shamt: u5) u32 {
    return encodeR(0b0010011, f3, f7, rd_v, rs1_v, shamt);
}

pub fn encodeS(f3: u3, rs1_v: u5, rs2_v: u5, imm12: u12) u32 {
    const imm: u32 = @intCast(imm12);
    const imm_4_0: u32 = imm & 0x1F;
    const imm_11_5: u32 = (imm >> 5) & 0x7F;
    return 0b0100011 |
        (imm_4_0 << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (imm_11_5 << 25);
}

pub fn encodeB(f3: u3, rs1_v: u5, rs2_v: u5, imm_val: i13) u32 {
    const imm: u13 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_12: u32 = (bits >> 12) & 1;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_10_5: u32 = (bits >> 5) & 0x3F;
    const bits_4_1: u32 = (bits >> 1) & 0xF;
    return 0b1100011 |
        (bit_11 << 7) |
        (bits_4_1 << 8) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (bits_10_5 << 25) |
        (bit_12 << 31);
}

pub fn encodeU(op: u7, rd_v: u5, imm20: u20) u32 {
    return @as(u32, op) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, imm20) << 12);
}

pub fn encodeJ(rd_v: u5, imm_val: i21) u32 {
    const imm: u21 = @bitCast(imm_val);
    const bits: u32 = @intCast(imm);
    const bit_20: u32 = (bits >> 20) & 1;
    const bits_10_1: u32 = (bits >> 1) & 0x3FF;
    const bit_11: u32 = (bits >> 11) & 1;
    const bits_19_12: u32 = (bits >> 12) & 0xFF;
    return 0b1101111 |
        (@as(u32, rd_v) << 7) |
        (bits_19_12 << 12) |
        (bit_11 << 20) |
        (bits_10_1 << 21) |
        (bit_20 << 31);
}

pub fn encodeAtomic(funct5: u5, rd_v: u5, rs1_v: u5, rs2_v: u5) u32 {
    const f7: u7 = @as(u7, funct5) << 2; // aq=0, rl=0
    return @as(u32, 0b0101111) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, 0b010) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, rs2_v) << 20) |
        (@as(u32, f7) << 25);
}

pub fn encodeCsr(f3: u3, rd_v: u5, rs1_v: u5, csr_addr: u12) u32 {
    return @as(u32, 0b1110011) |
        (@as(u32, rd_v) << 7) |
        (@as(u32, f3) << 12) |
        (@as(u32, rs1_v) << 15) |
        (@as(u32, csr_addr) << 20);
}
