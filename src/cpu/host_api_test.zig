//! The host-facing API around a run: the StepError set, describeFault(), runFor() and
//! stop_pc.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const Cpu = cpu_mod.TestCpu;
const StepResult = cpu_mod.StepResult;
const StepError = cpu_mod.StepError;
const h = @import("../instructions/test_helpers.zig");

test "step, run and runFor fail only with StepError" {
    inline for (.{ Cpu.step, Cpu.run, Cpu.runFor }) |f| {
        const ret = @typeInfo(@TypeOf(f)).@"fn".return_type.?;
        try std.testing.expect(@typeInfo(ret).error_union.error_set == StepError);
    }
}

fn faultOf(cpu: *Cpu) !cpu_mod.Fault {
    _ = cpu.step() catch |err| return cpu.describeFault(err);
    return error.TestExpectedError;
}

test "describeFault: data address of a faulting load, store and AMO" {
    var cpu = Cpu.init();
    cpu.pc = 0x40;
    cpu.writeReg(1, Cpu.mem_size - 4);
    h.loadInst(&cpu, h.encodeI(0b0000011, 0b010, 2, 1, 8)); // LW x2, 8(x1)
    var f = try faultOf(&cpu);
    try std.testing.expectEqual(error.AddressOutOfBounds, f.err);
    try std.testing.expectEqual(@as(u32, 0x40), f.pc);
    try std.testing.expectEqual(@as(?u32, h.encodeI(0b0000011, 0b010, 2, 1, 8)), f.raw);
    try std.testing.expectEqual(@as(?u32, Cpu.mem_size + 4), f.addr);

    cpu.writeReg(1, 0x101);
    h.loadInst(&cpu, h.encodeS(0b001, 1, 2, 0)); // SH x2, 0(x1) at 0x101: misaligned
    f = try faultOf(&cpu);
    try std.testing.expectEqual(error.MisalignedAccess, f.err);
    try std.testing.expectEqual(@as(?u32, 0x101), f.addr);

    cpu.writeReg(1, 0x202);
    h.loadInst(&cpu, h.encodeAtomic(0b00000, 3, 1, 2)); // AMOADD.W x3, x2, (x1)
    f = try faultOf(&cpu);
    try std.testing.expectEqual(error.MisalignedAccess, f.err);
    try std.testing.expectEqual(@as(?u32, 0x202), f.addr);
}

test "describeFault: fetch, decode and CSR faults" {
    var cpu = Cpu.init();
    cpu.pc = Cpu.mem_size;
    var f = try faultOf(&cpu);
    try std.testing.expectEqual(error.PCOutOfBounds, f.err);
    try std.testing.expectEqual(@as(?u32, null), f.raw);
    try std.testing.expectEqual(@as(?u32, Cpu.mem_size), f.addr);

    cpu.pc = 0;
    h.loadInst(&cpu, 0xFFFFFFFF);
    f = try faultOf(&cpu);
    try std.testing.expectEqual(error.IllegalInstruction, f.err);
    try std.testing.expectEqual(@as(?u32, 0xFFFFFFFF), f.raw);
    try std.testing.expectEqual(@as(?u32, null), f.addr);

    h.loadInst(&cpu, h.encodeCsr(0b001, 1, 2, 0xC00)); // CSRRW x1, cycle, x2
    f = try faultOf(&cpu);
    try std.testing.expectEqual(error.IllegalInstruction, f.err);
    try std.testing.expectEqual(@as(?u32, null), f.addr);
}

test "runFor: a budget relative to the current cycle count" {
    var cpu = Cpu.init();
    h.loadInst(&cpu, h.encodeJ(0, 0)); // JAL x0, 0 — loops forever
    try std.testing.expectEqual(StepResult.@"continue", try cpu.runFor(10));
    try std.testing.expectEqual(@as(u64, 10), cpu.cycle_count);
    try std.testing.expectEqual(StepResult.@"continue", try cpu.runFor(10));
    try std.testing.expectEqual(@as(u64, 20), cpu.cycle_count);
    try std.testing.expectEqual(StepResult.@"continue", try cpu.runFor(0));
    try std.testing.expectEqual(@as(u64, 20), cpu.cycle_count);
    // Near the top of the counter the limit saturates instead of wrapping to 0.
    cpu.cycle_count = std.math.maxInt(u64) - 2;
    try std.testing.expectEqual(StepResult.@"continue", try cpu.runFor(100));
    try std.testing.expectEqual(std.math.maxInt(u64), cpu.cycle_count);
}

test "runFor: stops early at ECALL" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, 0x00000013); // NOP
    h.storeWordAt(&cpu, 4, 0x00000073); // ECALL
    try std.testing.expectEqual(StepResult.ecall, try cpu.runFor(1000));
    try std.testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "stop_pc: the address of the ECALL or EBREAK that stopped execution" {
    var cpu = Cpu.init();
    h.storeWordAt(&cpu, 0, 0x00000013); // NOP
    h.storeWordAt(&cpu, 4, 0x00000073); // ECALL
    h.storeHalfAt(&cpu, 8, 0x9002); // C.EBREAK
    h.storeWordAt(&cpu, 10, 0x00100073); // EBREAK
    try std.testing.expectEqual(@as(u32, 0), cpu.stop_pc);
    try std.testing.expectEqual(StepResult.ecall, try cpu.run(null));
    try std.testing.expectEqual(@as(u32, 4), cpu.stop_pc);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
    try std.testing.expectEqual(StepResult.ebreak, try cpu.run(null));
    try std.testing.expectEqual(@as(u32, 8), cpu.stop_pc);
    try std.testing.expectEqual(@as(u32, 10), cpu.pc);
    try std.testing.expectEqual(StepResult.ebreak, try cpu.run(null));
    try std.testing.expectEqual(@as(u32, 10), cpu.stop_pc);
    cpu.reset();
    try std.testing.expectEqual(@as(u32, 0), cpu.stop_pc);
}

test "stop_pc: not part of the state digest" {
    var a = Cpu.init();
    const b = Cpu.init();
    a.stop_pc = 0x1234;
    try std.testing.expectEqualSlices(u8, &b.stateDigest(), &a.stateDigest());
}
