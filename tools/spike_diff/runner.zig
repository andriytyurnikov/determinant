//! The VM side of the Spike differential tests (tools/spike_diff): runs flat RISC-V
//! binaries and prints their final state, which the Python scripts compare with Spike's.
//!
//! usage: spike-runner MANIFEST
//!        spike-runner --trace BIN LOAD_HEX ENTRY_HEX MAX_STEPS
//!
//! MANIFEST has one job per line: BIN LOAD_HEX ENTRY_HEX DUMP_LO_HEX DUMP_HI_HEX MAX_STEPS.
//! Each job runs on a fresh VM twice, with the decode cache on and off, and prints one
//! line per run (fields separated by one space):
//!   BIN CONFIG STATUS EPC RETIRED FINAL_PC X0 RESERVATION X1,...,X31 MSCRATCH DIGEST MEM
//! CONFIG is `cache` or `nocache`. STATUS is ebreak, ecall, limit (MAX_STEPS reached) or
//! the name of the StepError. EPC is the address of the instruction that stopped the
//! run: stop_pc for ECALL/EBREAK, the faulting instruction for a fault. X0 is the raw
//! regs[0], RESERVATION a hex address or `none`, DIGEST the stateDigest() and MEM the
//! memory [DUMP_LO, DUMP_HI) in hex. Numbers are hex except RETIRED (cycle_count).
//!
//! --trace prints one line per retired instruction (cache on):
//!   PC RAW [x<n>=<val>]... [mscratch=<val>] [mem[<addr>]=<word>]... [resv=<addr|none>]
//! and a final line `end STATUS PC`.

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");

/// Memory [0, 0x50000): its top matches Spike's RAM, -m0x10000:0x40000 (see template.py).
const mem_size: u32 = 0x50000;
const CacheCpu = det.CpuType(mem_size, .{});
const NoCacheCpu = det.CpuType(mem_size, .{ .decode_cache_entries = 0 });

const Job = struct {
    path: []const u8,
    load: u32,
    entry: u32,
    dump_lo: u32,
    dump_hi: u32,
    max_steps: u64,
};

fn parseJob(line: []const u8) !Job {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    const path = it.next() orelse return error.BadManifest;
    const load = try std.fmt.parseInt(u32, it.next() orelse return error.BadManifest, 16);
    const entry = try std.fmt.parseInt(u32, it.next() orelse return error.BadManifest, 16);
    const lo = try std.fmt.parseInt(u32, it.next() orelse return error.BadManifest, 16);
    const hi = try std.fmt.parseInt(u32, it.next() orelse return error.BadManifest, 16);
    const max = try std.fmt.parseInt(u64, it.next() orelse return error.BadManifest, 10);
    if (it.next() != null or lo > hi or hi > mem_size) return error.BadManifest;
    return .{ .path = path, .load = load, .entry = entry, .dump_lo = lo, .dump_hi = hi, .max_steps = max };
}

fn runJob(comptime T: type, vm: *T, config: []const u8, bin: []const u8, job: Job, out: *Io.Writer) !void {
    vm.reset();
    try vm.loadProgram(bin, job.load);
    vm.pc = job.entry;

    var status: []const u8 = "limit";
    var epc: u32 = vm.pc;
    while (vm.cycle_count < job.max_steps) {
        const pc_before = vm.pc;
        const r = vm.step() catch |err| {
            status = @errorName(err);
            epc = pc_before;
            break;
        };
        if (r != .@"continue") {
            status = @tagName(r);
            epc = vm.stop_pc;
            break;
        }
        epc = vm.pc;
    }

    try out.print("{s} {s} {s} {x:0>8} {d} {x:0>8} {x:0>8} ", .{ job.path, config, status, epc, vm.cycle_count, vm.pc, vm.regs[0] });
    if (vm.reservation) |res| try out.print("{x:0>8} ", .{res}) else try out.writeAll("none ");
    for (1..32) |i| {
        try out.print("{x:0>8}", .{vm.regs[i]});
        try out.writeByte(if (i == 31) ' ' else ',');
    }
    try out.print("{x:0>8} {x} ", .{ vm.csrs.mscratch, &vm.stateDigest() });
    try out.print("{x}\n", .{vm.memory[job.dump_lo..job.dump_hi]});
}

fn traceJob(vm: *CacheCpu, shadow: *CacheCpu, bin: []const u8, load: u32, entry: u32, max_steps: u64, out: *Io.Writer) !void {
    vm.reset();
    try vm.loadProgram(bin, load);
    vm.pc = entry;
    var status: []const u8 = "limit";
    while (vm.cycle_count < max_steps) {
        shadow.* = vm.*;
        const raw = vm.fetch() catch 0;
        const r = vm.step() catch |err| {
            status = @errorName(err);
            break;
        };
        try out.print("{x:0>8} {x:0>8}", .{ shadow.pc, raw });
        for (1..32) |i| {
            if (vm.regs[i] != shadow.regs[i]) try out.print(" x{d}={x:0>8}", .{ i, vm.regs[i] });
        }
        if (vm.csrs.mscratch != shadow.csrs.mscratch) try out.print(" mscratch={x:0>8}", .{vm.csrs.mscratch});
        if (!std.mem.eql(u8, &vm.memory, &shadow.memory)) {
            var a: u32 = 0;
            while (a < mem_size) : (a += 4) {
                const new = std.mem.readInt(u32, vm.memory[a..][0..4], .little);
                if (new != std.mem.readInt(u32, shadow.memory[a..][0..4], .little))
                    try out.print(" mem[{x:0>8}]={x:0>8}", .{ a, new });
            }
        }
        if (!std.meta.eql(vm.reservation, shadow.reservation)) {
            if (vm.reservation) |res| try out.print(" resv={x:0>8}", .{res}) else try out.writeAll(" resv=none");
        }
        try out.writeByte('\n');
        if (r != .@"continue") {
            status = @tagName(r);
            break;
        }
    }
    try out.print("end {s} {x:0>8}\n", .{ status, vm.pc });
}

fn usage() noreturn {
    std.debug.print("usage: spike-runner MANIFEST | spike-runner --trace BIN LOAD_HEX ENTRY_HEX MAX_STEPS\n", .{});
    std.process.exit(2);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var out_buf: [1 << 16]u8 = undefined;
    var out_fw: Io.File.Writer = .initStreaming(Io.File.stdout(), io, &out_buf);
    const out: *Io.Writer = &out_fw.interface;

    if (args.len > 1 and std.mem.eql(u8, args[1], "--trace")) {
        if (args.len != 6) usage();
        const bin = try Io.Dir.cwd().readFileAlloc(io, args[2], arena, .limited(mem_size + 1));
        const load = try std.fmt.parseInt(u32, args[3], 16);
        const entry = try std.fmt.parseInt(u32, args[4], 16);
        const max = try std.fmt.parseInt(u64, args[5], 10);
        const vm = try gpa.create(CacheCpu);
        defer gpa.destroy(vm);
        const shadow = try gpa.create(CacheCpu);
        defer gpa.destroy(shadow);
        try traceJob(vm, shadow, bin, load, entry, max, out);
        try out.flush();
        return;
    }
    if (args.len != 2) usage();
    const manifest = try Io.Dir.cwd().readFileAlloc(io, args[1], arena, .unlimited);

    const cache_vm = try gpa.create(CacheCpu);
    defer gpa.destroy(cache_vm);
    const nocache_vm = try gpa.create(NoCacheCpu);
    defer gpa.destroy(nocache_vm);

    var lines = std.mem.tokenizeAny(u8, manifest, "\r\n");
    while (lines.next()) |line| {
        const job = try parseJob(line);
        const bin = try Io.Dir.cwd().readFileAlloc(io, job.path, gpa, .limited(mem_size + 1));
        defer gpa.free(bin);
        try runJob(CacheCpu, cache_vm, "cache", bin, job, out);
        try runJob(NoCacheCpu, nocache_vm, "nocache", bin, job, out);
    }
    try out.flush();
}
