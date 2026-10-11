//! Decoder oracle: compares the decoder with LLVM's RISC-V disassembler, which is loaded
//! at run time from a shared libLLVM through the LLVM C API.
//!
//! usage: llvm-oracle LIBLLVM MODE [ARGS] [--features FEATURES]
//!   c16 [THREADS]            all 49152 16-bit encodings (low two bits != 0b11)
//!   c32 [THREADS [LO [N]]]   the 32-bit encodings (x << 2) | 0b11 for x in [LO, LO+N);
//!                            by default all 2^30 of them
//!   probe HEX...             print both decodes of the given encodings
//!   self-test [THREADS]      plant decoder bugs and check that every encoding they
//!                            change is reported
//!
//! THREADS defaults to 4. LLVM disassembles for riscv32 with FEATURES (default
//! +m,+a,+c,+zba,+zbb,+zbs,+zicsr,+zifencei) and its printer option -riscv-no-aliases.
//!
//! Every encoding is in one of five classes: both accept it with identical text, both
//! reject it, or one of three divergences: (i) Determinant accepts and LLVM rejects,
//! (ii) Determinant rejects and LLVM accepts, (iii) both accept and the text differs.
//! Divergences are grouped into buckets, and each one is checked against the known,
//! accepted divergences (README.md). The exit status is 1 if any is unexplained.
//!
//! Run with `zig build llvm-oracle -Dllvm_lib=PATH -- MODE ...` (always -Doptimize=fast).

const std = @import("std");
const det = @import("determinant");
const render = @import("render.zig");
const Instruction = det.Instruction;
const Opcode = det.Opcode;
const rv32c = det.instructions.rv32i.rv32c;

// LLVM C API: llvm-c/Disassembler.h, llvm-c/Target.h, llvm-c/Support.h.
const DisCtx = ?*anyopaque;
const FnCreate = *const fn ([*:0]const u8, [*:0]const u8, [*:0]const u8, ?*anyopaque, c_int, ?*const anyopaque, ?*const anyopaque) callconv(.c) DisCtx;
const FnDisasm = *const fn (DisCtx, [*]u8, u64, u64, [*]u8, usize) callconv(.c) usize;
const FnVoid = *const fn () callconv(.c) void;
const FnParse = *const fn (c_int, [*]const [*:0]const u8, ?[*:0]const u8) callconv(.c) void;

var llvm_create: FnCreate = undefined;
var llvm_disasm: FnDisasm = undefined;
var csr_names: render.CsrNames = undefined;
/// Self-test mode: plant decoder bugs (plantBug) before rendering.
var self_test = false;

const default_features = "+m,+a,+c,+zba,+zbb,+zbs,+zicsr,+zifencei";
const max_threads = 64;
const all_32bit: u64 = 1 << 30;

/// The 32-bit encodings the self-test covers, as x = raw >> 2. Each block of 2^20 varies
/// raw bits [21:2] (opcode, rd, funct3, rs1, rs2[1:0]) under a fixed funct7: 0b0100000
/// (SUB, with the branches, JAL, LW and the CSR instructions) and 0b0110000 (RORI).
const self_test_blocks = [_]u64{ 0b0100000 << 23, 0b0110000 << 23 };
const self_test_block_len: u64 = 1 << 20;

const Text = struct {
    buf: [112]u8 = undefined,
    len: usize = 0,

    fn slice(t: *const Text) []const u8 {
        return t.buf[0..t.len];
    }
};

const Sample = struct { raw: u32, det: Text, llvm: Text };

const Bucket = struct {
    count: u64 = 0,
    /// Why this divergence is accepted; null if it is unexplained.
    reason: ?[]const u8 = null,
    samples: [3]Sample = undefined,
    n_samples: usize = 0,
};

/// The bugs the self-test plants: each changes one decoded field.
const Plant = enum { branch_offset, sub_operands, load_rd, csr_number, rori_shamt };
const n_plants = @typeInfo(Plant).@"enum".field_names.len;

const n_tags = @typeInfo(std.meta.Tag(Opcode)).@"enum".field_names.len;
const n_cops = @typeInfo(rv32c.Opcode).@"enum".field_names.len;

const Stats = struct {
    total: u64 = 0,
    agree_accept: u64 = 0,
    agree_reject: u64 = 0,
    /// Divergences (i), (ii), (iii).
    cls: [3]u64 = @splat(0),
    unexplained: u64 = 0,
    /// LLVM consumed a byte count other than the instruction length.
    llvm_len_odd: u64 = 0,
    per_op: [n_tags][64]u64 = std.mem.zeroes([n_tags][64]u64),
    per_cop: [n_cops]u64 = @splat(0),
    buckets: std.StringHashMapUnmanaged(Bucket) = .empty,
    /// Self-test: encodings whose decode a planted bug changed, and those of them that
    /// were not reported as an unexplained divergence.
    planted: [n_plants]u64 = @splat(0),
    missed: [n_plants]u64 = @splat(0),
};

// --- Known divergences (README.md). Each check looks at the encoding itself, not
// only at the decode, so that a decoder bug cannot hide behind a known class.

const reason_fence = "FENCE/FENCE.I ignore their unused fields (SEMANTICS.md); LLVM disassembles only canonical encodings";
const reason_privileged = "privileged instruction: no privilege modes, so IllegalInstruction";
const reason_c_unimp = "c.unimp: the all-zero halfword is defined illegal";
const reason_prefetch = "LLVM names ORI rd=x0 with imm[4:0] = 0/1/3 as the Zicbop prefetch hints; it executes as ORI";
const reason_fence_tso = "LLVM's name for FENCE fm=TSO, rw, rw; it executes as FENCE";
const reason_unimp = "LLVM's name for CSRRW x0, cycle, x0, which traps when executed (read-only CSR)";

/// Privileged instructions of the SYSTEM funct3 = 0 space, as LLVM names them.
const privileged = [_][]const u8{
    "mret",        "sret",        "dret",           "mnret",           "wfi",
    "sfence.vma",  "sinval.vma",  "sfence.w.inval", "sfence.inval.ir", "hfence.vvma",
    "hfence.gvma", "hinval.vvma", "hinval.gvma",
};

/// (i) Determinant accepts, LLVM rejects.
fn explainDetOnly(raw: u32, len: u8, inst: Instruction) ?[]const u8 {
    if (len != 4 or inst.compressed_op != null or raw & 0x7F != 0x0F) return null;
    const funct3 = (raw >> 12) & 7;
    return switch (inst.op) {
        .i => |op| if ((op == .FENCE and funct3 == 0) or (op == .FENCE_I and funct3 == 1)) reason_fence else null,
        else => null,
    };
}

/// (ii) Determinant rejects, LLVM accepts.
fn explainLlvmOnly(raw: u32, len: u8, llvm: []const u8) ?[]const u8 {
    if (len == 2) return if (raw == 0 and std.mem.eql(u8, llvm, "c.unimp")) reason_c_unimp else null;
    if (raw & 0x707F != 0x73) return null; // SYSTEM, funct3 = 0
    for (privileged) |mn| {
        if (std.mem.eql(u8, firstToken(llvm), mn)) return reason_privileged;
    }
    return null;
}

/// (iii) Both accept, the text differs.
fn explainText(raw: u32, inst: Instruction, llvm: []const u8) ?[]const u8 {
    if (inst.compressed_op != null) return null;
    switch (inst.op) {
        .i => |op| switch (op) {
            .ORI => {
                if (inst.rd != 0 or raw & 0x707F != 0x6013) return null;
                const kind: u8 = switch (inst.imm & 31) {
                    0 => 'i',
                    1 => 'r',
                    3 => 'w',
                    else => return null,
                };
                var buf: [48]u8 = undefined;
                const want = std.mem.print(&buf, "prefetch.{c} {d}({s})", .{ kind, inst.imm & ~@as(i32, 31), render.abi[inst.rs1] }) catch return null;
                return if (std.mem.eql(u8, llvm, want)) reason_prefetch else null;
            },
            .FENCE => return if (raw == 0x8330000F and std.mem.eql(u8, llvm, "fence.tso")) reason_fence_tso else null,
            else => return null,
        },
        .csr => |op| {
            const is_unimp = raw == 0xC0001073 and op == .CSRRW and inst.rd == 0 and inst.rs1 == 0 and inst.csrAddr() == 0xC00;
            return if (is_unimp and std.mem.eql(u8, llvm, "unimp")) reason_unimp else null;
        },
        else => return null,
    }
}

// --- Comparison

/// Disassemble with LLVM. Returns false if LLVM rejects the encoding; otherwise `out`
/// holds the text with tabs as spaces, and `consumed` the bytes LLVM used.
fn llvmText(ctx: DisCtx, raw: u32, len: u8, out: *Text, consumed: *usize) bool {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, raw, .little);
    var s: [256]u8 = undefined;
    s[0] = 0;
    const n = llvm_disasm(ctx, &bytes, len, 0, &s, s.len);
    consumed.* = n;
    if (n == 0) return false;
    const z = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&s)), 0);
    const t = std.mem.trim(u8, z, " \t");
    out.len = 0;
    for (t) |ch| {
        if (out.len == out.buf.len) break;
        out.buf[out.len] = if (ch == '\t') ' ' else ch;
        out.len += 1;
    }
    return true;
}

fn plantBug(inst: *Instruction) ?Plant {
    switch (inst.op) {
        .i => |op| switch (op) {
            .BEQ, .BNE, .JAL => {
                inst.imm +%= 2;
                return .branch_offset;
            },
            .SUB => {
                std.mem.swap(u5, &inst.rs1, &inst.rs2);
                return .sub_operands;
            },
            .LW => {
                inst.rd ^= 1;
                return .load_rd;
            },
            else => return null,
        },
        .csr => {
            inst.imm ^= 1;
            return .csr_number;
        },
        .zbb => |op| {
            if (op != .RORI) return null;
            inst.imm ^= 16;
            return .rori_shamt;
        },
        else => return null,
    }
}

fn renderText(inst: Instruction, out: *Text) void {
    var w: std.Io.Writer = .fixed(&out.buf);
    render.render(&w, &csr_names, inst) catch {};
    out.len = w.buffered().len;
}

fn firstToken(s: []const u8) []const u8 {
    const i = std.mem.findScalar(u8, s, ' ') orelse s.len;
    return s[0..i];
}

fn addBucket(st: *Stats, key: []const u8, reason: ?[]const u8, raw: u32, dt: ?*const Text, lt: ?*const Text) void {
    const gpa = std.heap.smp_allocator;
    const gop = st.buckets.getOrPut(gpa, key) catch @panic("out of memory");
    if (!gop.found_existing) {
        gop.key_ptr.* = gpa.dupe(u8, key) catch @panic("out of memory");
        gop.value_ptr.* = .{ .reason = reason };
    }
    const b = gop.value_ptr;
    b.count += 1;
    // Keep the first two samples and the most recent one.
    var smp: Sample = .{ .raw = raw, .det = .{}, .llvm = .{} };
    if (dt) |d| smp.det = d.*;
    if (lt) |l| smp.llvm = l.*;
    b.samples[@min(b.n_samples, 2)] = smp;
    if (b.n_samples < 3) b.n_samples += 1;
}

/// Records one divergence; returns whether it is unexplained.
fn diverge(st: *Stats, key_base: []const u8, reason: ?[]const u8, raw: u32, dt: ?*const Text, lt: ?*const Text) bool {
    var kb: [224]u8 = undefined;
    const key = if (reason == null) std.mem.print(&kb, "{s} UNEXPLAINED", .{key_base}) catch key_base else key_base;
    addBucket(st, key, reason, raw, dt, lt);
    if (reason == null) st.unexplained += 1;
    return reason == null;
}

fn classify(st: *Stats, ctx: DisCtx, raw: u32, len: u8) void {
    st.total += 1;
    var lt: Text = .{};
    var consumed: usize = 0;
    const l_ok = llvmText(ctx, raw, len, &lt, &consumed);
    var kb: [192]u8 = undefined;
    if (l_ok and consumed != len) {
        st.llvm_len_odd += 1;
        const key = std.mem.print(&kb, "len|{s}", .{firstToken(lt.slice())}) catch "len";
        _ = diverge(st, key, null, raw, null, &lt);
    }

    var inst: ?Instruction = det.decode(raw) catch null;
    var plant: ?Plant = null;
    if (self_test) {
        if (inst) |orig| {
            var bugged = orig;
            if (plantBug(&bugged)) |p| {
                if (!std.meta.eql(bugged, orig)) {
                    plant = p;
                    inst = bugged;
                    st.planted[@backingInt(p)] += 1;
                }
            }
        }
    }

    var dt: Text = .{};
    var reported = false;
    if (inst) |i| {
        renderText(i, &dt);
        if (l_ok) {
            if (std.mem.eql(u8, dt.slice(), lt.slice())) {
                st.agree_accept += 1;
                switch (i.op) {
                    inline else => |p, tag| st.per_op[@backingInt(tag)][@backingInt(p)] += 1,
                }
                if (i.compressed_op) |c| st.per_cop[@backingInt(c)] += 1;
            } else {
                st.cls[2] += 1;
                const key = std.mem.print(&kb, "iii|{s} ~ {s}", .{ firstToken(dt.slice()), firstToken(lt.slice()) }) catch "iii";
                reported = diverge(st, key, explainText(raw, i, lt.slice()), raw, &dt, &lt);
            }
        } else {
            st.cls[0] += 1;
            var diag_buf: [96]u8 = undefined;
            var dw: std.Io.Writer = .fixed(&diag_buf);
            render.diagnose(&dw, i) catch {};
            const key = std.mem.print(&kb, "i|{s}|{s}", .{ firstToken(dt.slice()), std.mem.trim(u8, dw.buffered(), " ") }) catch "i";
            reported = diverge(st, key, explainDetOnly(raw, len, i), raw, &dt, null);
        }
    } else if (l_ok) {
        st.cls[1] += 1;
        const key = std.mem.print(&kb, "ii|{s}", .{firstToken(lt.slice())}) catch "ii";
        reported = diverge(st, key, explainLlvmOnly(raw, len, lt.slice()), raw, null, &lt);
    } else {
        st.agree_reject += 1;
    }
    if (plant) |p| {
        if (!reported) st.missed[@backingInt(p)] += 1;
    }
}

/// A set of encodings: all 16-bit ones, or 32-bit ones with x = raw >> 2 in [lo, hi).
const Part = struct {
    mode16: bool,
    lo: u64 = 0,
    hi: u64 = 0,
};

const Job = struct {
    st: *Stats,
    ctx: DisCtx,
    part: Part,
    tid: usize,
    n_threads: usize,
};

const block: u64 = 1 << 14;

fn worker(job: Job) void {
    if (job.part.mode16) {
        var h: u32 = @intCast(job.tid);
        while (h < 65536) : (h += @intCast(job.n_threads)) {
            if (h & 3 == 3) continue;
            classify(job.st, job.ctx, h, 2);
        }
        return;
    }
    // Interleaved blocks, for load balance.
    const lo = job.part.lo;
    const hi = job.part.hi;
    var blk: u64 = lo / block + job.tid;
    var done_blocks: u64 = 0;
    while (blk * block < hi) : (blk += job.n_threads) {
        const start = @max(blk * block, lo);
        const end = @min((blk + 1) * block, hi);
        var x = start;
        while (x < end) : (x += 1) {
            classify(job.st, job.ctx, @intCast((x << 2) | 0b11), 4);
        }
        done_blocks += 1;
        if (job.tid == 0 and done_blocks % 1024 == 0) {
            const pct = 100.0 * @as(f64, @floatFromInt(x - lo)) / @as(f64, @floatFromInt(hi - lo));
            std.debug.print("[progress] thread 0 at x=0x{x} ({d:.1}%)\n", .{ x, pct });
        }
    }
}

fn mergeInto(dst: *Stats, src: *const Stats) void {
    const gpa = std.heap.smp_allocator;
    dst.total += src.total;
    dst.agree_accept += src.agree_accept;
    dst.agree_reject += src.agree_reject;
    dst.unexplained += src.unexplained;
    dst.llvm_len_odd += src.llvm_len_odd;
    for (0..3) |k| dst.cls[k] += src.cls[k];
    for (0..n_tags) |t| for (0..64) |v| {
        dst.per_op[t][v] += src.per_op[t][v];
    };
    for (0..n_cops) |k| dst.per_cop[k] += src.per_cop[k];
    for (0..n_plants) |k| {
        dst.planted[k] += src.planted[k];
        dst.missed[k] += src.missed[k];
    }
    var it = src.buckets.iterator();
    while (it.next()) |e| {
        const gop = dst.buckets.getOrPut(gpa, e.key_ptr.*) catch @panic("out of memory");
        if (!gop.found_existing) {
            gop.value_ptr.* = e.value_ptr.*;
            continue;
        }
        const b = gop.value_ptr;
        b.count += e.value_ptr.count;
        for (e.value_ptr.samples[0..e.value_ptr.n_samples]) |s| {
            if (b.n_samples < 3) {
                b.samples[b.n_samples] = s;
                b.n_samples += 1;
            }
        }
    }
}

/// Compare every encoding of `part` on `ctxs.len` threads, adding the results to `total`.
fn comparePart(ctxs: []const DisCtx, part: Part, total: *Stats) !void {
    var stats: [max_threads]Stats = @splat(.{});
    var threads: [max_threads]std.Thread = undefined;
    for (ctxs, 0..) |ctx, k| {
        const job: Job = .{ .st = &stats[k], .ctx = ctx, .part = part, .tid = k, .n_threads = ctxs.len };
        threads[k] = try std.Thread.spawn(.{}, worker, .{job});
    }
    for (threads[0..ctxs.len]) |th| th.join();
    for (stats[0..ctxs.len]) |*s| mergeInto(total, s);
}

// --- LLVM setup

fn initLlvm(lib_path: []const u8) !void {
    var lib = try std.DynLib.open(lib_path);
    const inits = [_][:0]const u8{ "LLVMInitializeRISCVTargetInfo", "LLVMInitializeRISCVTargetMC", "LLVMInitializeRISCVDisassembler" };
    for (inits) |name| {
        const f = lib.lookup(FnVoid, name) orelse return error.MissingSymbol;
        f();
    }
    llvm_create = lib.lookup(FnCreate, "LLVMCreateDisasmCPUFeatures") orelse return error.MissingSymbol;
    llvm_disasm = lib.lookup(FnDisasm, "LLVMDisasmInstruction") orelse return error.MissingSymbol;
    const parse = lib.lookup(FnParse, "LLVMParseCommandLineOptions") orelse return error.MissingSymbol;
    const argv = [_][*:0]const u8{ "llvm-oracle", "-riscv-no-aliases" };
    parse(argv.len, &argv, null);
}

fn newCtx(features: [*:0]const u8) !DisCtx {
    const c = llvm_create("riscv32-unknown-elf", "", features, null, 0, null, null);
    if (c == null) return error.CreateDisasmFailed;
    return c;
}

/// Harvest LLVM's name for every CSR number from `csrrs zero, N, zero`. The names must
/// be distinct, or a wrong CSR number could render as the right text.
fn buildCsrTable(ctx: DisCtx) !void {
    const gpa = std.heap.smp_allocator;
    var seen: std.StringHashMapUnmanaged(u12) = .empty;
    var t: Text = .{};
    var consumed: usize = 0;
    for (0..4096) |n| {
        const raw: u32 = (@as(u32, @intCast(n)) << 20) | (0b010 << 12) | 0x73;
        if (!llvmText(ctx, raw, 4, &t, &consumed)) return error.CsrRejected;
        const s = t.slice();
        const pre = "csrrs zero, ";
        const post = ", zero";
        if (!std.mem.startsWith(u8, s, pre) or !std.mem.endsWith(u8, s, post)) {
            std.debug.print("error: unexpected LLVM text for CSR {d}: '{s}'\n", .{ n, s });
            return error.CsrFormat;
        }
        const name = try gpa.dupe(u8, s[pre.len .. s.len - post.len]);
        csr_names[n] = name;
        const gop = try seen.getOrPut(gpa, name);
        if (gop.found_existing) {
            std.debug.print("error: LLVM names CSRs {d} and {d} both '{s}'\n", .{ gop.value_ptr.*, n, name });
            return error.CsrCollision;
        }
        gop.value_ptr.* = @intCast(n);
    }
}

// --- Report

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn report(out: *std.Io.Writer, tot: *const Stats, title: []const u8, mode16: bool) !void {
    try out.print("\n=== Determinant vs LLVM: {s} ===\n", .{title});
    try out.print("total={d} identical={d} both-reject={d}\n", .{ tot.total, tot.agree_accept, tot.agree_reject });
    try out.print("(i)   Determinant accepts, LLVM rejects : {d}\n", .{tot.cls[0]});
    try out.print("(ii)  Determinant rejects, LLVM accepts : {d}\n", .{tot.cls[1]});
    try out.print("(iii) both accept, text differs         : {d}\n", .{tot.cls[2]});
    try out.print("LLVM length != instruction length       : {d}\n", .{tot.llvm_len_odd});
    try out.print("unexplained divergences                 : {d}\n", .{tot.unexplained});

    const gpa = std.heap.smp_allocator;
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(gpa);
    var it = tot.buckets.iterator();
    while (it.next()) |e| try keys.append(gpa, e.key_ptr.*);
    std.mem.sort([]const u8, keys.items, {}, lessThan);
    for (keys.items) |k| {
        const b = tot.buckets.get(k).?;
        try out.print("\n[{s}]  count={d}  {s}{s}\n", .{ k, b.count, if (b.reason == null) "" else "known: ", b.reason orelse "" });
        for (b.samples[0..b.n_samples]) |s| {
            const d = if (s.det.len > 0) s.det.slice() else "<illegal>";
            const l = if (s.llvm.len > 0) s.llvm.slice() else "<invalid>";
            try out.print("    0x{x:0>8}  det: {s:<40} llvm: {s}\n", .{ s.raw, d, l });
        }
    }

    try out.print("\n--- identical decodes per opcode ---\n", .{});
    const union_info = @typeInfo(Opcode).@"union";
    inline for (union_info.field_names, union_info.field_types, 0..) |ext_name, ExtOpcode, ti| {
        const enum_info = @typeInfo(ExtOpcode).@"enum";
        inline for (enum_info.field_names, enum_info.field_values) |op_name, op_value| {
            const n = tot.per_op[ti][op_value];
            if (n != 0) try out.print("  {s}.{s:<10} {d}\n", .{ ext_name, op_name, n });
        }
    }
    if (mode16) {
        try out.print("--- identical decodes per compressed opcode ---\n", .{});
        const enum_info = @typeInfo(rv32c.Opcode).@"enum";
        inline for (enum_info.field_names, enum_info.field_values) |op_name, op_value| {
            try out.print("  {s:<11} {d}\n", .{ op_name, tot.per_cop[op_value] });
        }
    }
}

/// Prints the self-test verdict; returns whether every planted bug was caught.
fn reportSelfTest(out: *std.Io.Writer, tot: *const Stats) !bool {
    try out.print("\n=== self-test: planted decoder bugs ===\n", .{});
    var ok = true;
    var reported: u64 = 0;
    inline for (@typeInfo(Plant).@"enum".field_names, 0..) |plant_name, k| {
        const planted = tot.planted[k];
        const missed = tot.missed[k];
        const pass = planted > 0 and missed == 0;
        if (!pass) ok = false;
        reported += planted - missed;
        try out.print("  {s:<14} changed {d:>8} decodes, reported {d:>8}  {s}\n", .{ plant_name, planted, planted - missed, if (pass) "ok" else "FAIL" });
    }
    // Every unexplained divergence must come from a planted bug.
    const other = tot.unexplained - reported;
    try out.print("  other unexplained divergences: {d}  {s}\n", .{ other, if (other == 0) "ok" else "FAIL" });
    if (other != 0) ok = false;
    try out.print("self-test {s}\n", .{if (ok) "passed: every changed decode, and nothing else, was reported as an unexplained divergence" else "FAILED"});
    return ok;
}

fn usage() noreturn {
    std.debug.print(
        \\usage: llvm-oracle LIBLLVM MODE [ARGS] [--features FEATURES]
        \\  c16 [THREADS]            all 16-bit encodings
        \\  c32 [THREADS [LO [N]]]   32-bit encodings (x << 2) | 0b11, x in [LO, LO+N) (default all 2^30)
        \\  probe HEX...             both decodes of the given encodings
        \\  self-test [THREADS]      plant decoder bugs; each must be reported
        \\
    , .{});
    std.process.exit(2);
}

fn parseThreads(pos: []const []const u8, i: usize) !usize {
    const n = if (pos.len > i) try std.fmt.parseInt(usize, pos[i], 10) else 4;
    if (n == 0 or n > max_threads) {
        std.debug.print("error: THREADS must be 1 to {d}\n", .{max_threads});
        std.process.exit(2);
    }
    return n;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var pos: std.ArrayList([]const u8) = .empty;
    var features: [:0]const u8 = default_features;
    var a: usize = 1;
    while (a < args.len) : (a += 1) {
        if (std.mem.eql(u8, args[a], "--features")) {
            a += 1;
            if (a == args.len) usage();
            features = args[a];
        } else try pos.append(arena, args[a]);
    }
    if (pos.items.len < 2) usage();
    const lib_path = pos.items[0];
    const mode = pos.items[1];

    var buf: [1 << 16]u8 = undefined;
    var fw: std.Io.File.Writer = .initStreaming(std.Io.File.stdout(), init.io, &buf);
    const out = &fw.interface;

    try initLlvm(lib_path);
    const ctx0 = try newCtx(features.ptr);
    // Sanity check: aliases must be off, or LLVM prints "nop" here.
    var t: Text = .{};
    var consumed: usize = 0;
    _ = llvmText(ctx0, 0x00000013, 4, &t, &consumed);
    if (!std.mem.eql(u8, t.slice(), "addi zero, zero, 0")) {
        std.debug.print("error: -riscv-no-aliases is not in effect: 0x00000013 is '{s}'\n", .{t.slice()});
        std.process.exit(1);
    }
    try buildCsrTable(ctx0);

    if (std.mem.eql(u8, mode, "probe")) {
        try out.print("lib={s} features={s}\n", .{ lib_path, features });
        for (pos.items[2..]) |hex| {
            const digits = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;
            const raw = try std.fmt.parseInt(u32, digits, 16);
            const len: u8 = if (raw & 3 == 3) 4 else 2;
            var lt: Text = .{};
            var dt: Text = .{};
            const l_ok = llvmText(ctx0, raw, len, &lt, &consumed);
            const d_ok = if (det.decode(raw)) |inst| blk: {
                renderText(inst, &dt);
                break :blk true;
            } else |_| false;
            try out.print("0x{x:0>8}  det: {s:<40} llvm: {s}\n", .{ raw, if (d_ok) dt.slice() else "<illegal>", if (l_ok) lt.slice() else "<invalid>" });
        }
        try out.flush();
        return;
    }

    const is_c16 = std.mem.eql(u8, mode, "c16");
    const is_c32 = std.mem.eql(u8, mode, "c32");
    self_test = std.mem.eql(u8, mode, "self-test");
    if (!is_c16 and !is_c32 and !self_test) usage();
    const n_threads = try parseThreads(pos.items, 2);
    var ctxs: [max_threads]DisCtx = undefined;
    ctxs[0] = ctx0;
    for (1..n_threads) |k| ctxs[k] = try newCtx(features.ptr);
    try out.print("lib={s} features={s} mode={s} threads={d}\n", .{ lib_path, features, mode, n_threads });

    var tot: Stats = .{};
    var title_buf: [128]u8 = undefined;
    var title: []const u8 = "all 16-bit encodings (low two bits != 0b11)";
    if (is_c16) {
        try comparePart(ctxs[0..n_threads], .{ .mode16 = true }, &tot);
    } else if (is_c32) {
        const lo = if (pos.items.len > 3) try std.fmt.parseInt(u64, pos.items[3], 0) else 0;
        const n = if (pos.items.len > 4) try std.fmt.parseInt(u64, pos.items[4], 0) else all_32bit;
        const hi = @min(lo +| n, all_32bit);
        if (lo >= hi) usage();
        title = try std.mem.print(&title_buf, "32-bit encodings (x << 2) | 0b11 for x in [0x{x}, 0x{x})", .{ lo, hi });
        try comparePart(ctxs[0..n_threads], .{ .mode16 = false, .lo = lo, .hi = hi }, &tot);
    } else {
        try comparePart(ctxs[0..n_threads], .{ .mode16 = true }, &tot);
        for (self_test_blocks) |lo| {
            try comparePart(ctxs[0..n_threads], .{ .mode16 = false, .lo = lo, .hi = lo + self_test_block_len }, &tot);
        }
        title = "self-test (planted bugs): all 16-bit encodings and two blocks of 2^20 32-bit encodings";
    }

    try report(out, &tot, title, !is_c32);
    var ok = tot.unexplained == 0;
    if (self_test) ok = try reportSelfTest(out, &tot);
    try out.flush();
    if (!ok) std.process.exit(1);
}
