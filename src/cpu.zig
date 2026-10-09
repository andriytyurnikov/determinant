//! CpuType and RuntimeCpuType — the RISC-V CPU core. Its memory (inside the VM with a
//! size fixed at compile time, or a host buffer of a size chosen at run time) and its
//! decoder are comptime parameters.

const std = @import("std");
const decoders = @import("decoders.zig");
const instructions = @import("instructions.zig");
const rv32i = instructions.rv32i;
const rv32m = instructions.rv32m;
const rv32a = instructions.rv32a;
const zicsr = instructions.zicsr;
const zba = instructions.zba;
const zbb = instructions.zbb;
const zbs = instructions.zbs;
const cpu_exec_i = @import("cpu/exec_i.zig");
const state = @import("cpu/state.zig");

pub const DecodeFn = *const fn (u32) decoders.DecodeError!instructions.Instruction;

pub const StepResult = cpu_exec_i.Result;

/// Everything step() and run() can fail with. A fault leaves the whole VM state as it
/// was before the faulting instruction (see SEMANTICS.md, "Faults").
pub const StepError = error{
    /// The instruction does not decode, or it accesses a CSR it may not.
    IllegalInstruction,
    /// pc is odd.
    MisalignedPC,
    /// The instruction at pc does not lie entirely inside memory.
    PCOutOfBounds,
    /// A halfword or word data access (including LR/SC/AMO) is not naturally aligned.
    MisalignedAccess,
    /// A data access touches a byte outside memory.
    AddressOutOfBounds,
};

/// Errors from CpuType.restoreSnapshot().
pub const RestoreError = state.RestoreError;

/// Details of a fault, for the host: see CpuType.describeFault().
pub const Fault = struct {
    err: StepError,
    /// Address of the faulting instruction (the VM's pc, which the fault left there).
    pc: u32,
    /// The faulting instruction's bits, unless fetching them was the fault.
    raw: ?u32,
    /// The address that faulted: the data address of a load, store, AMO, LR or SC, or
    /// pc for a fetch fault. null for decode and CSR faults.
    addr: ?u32,
};

/// Compile-time configuration of a CpuType.
pub const Options = struct {
    /// Instruction decoder.
    decode: DecodeFn = &decoders.decode,
    /// Entries in the decode cache: a power of two, or 0 to disable the cache. Each
    /// entry holds one decoded Instruction (16 bytes) and covers one halfword of code,
    /// so the default caches 8 KiB of code at a time.
    decode_cache_entries: u32 = 4096,
};

/// Errors from RuntimeCpuType.init() and initInPlace().
pub const InitError = error{
    /// The memory is smaller than 4 bytes, not a multiple of 4, or larger than 2^32 - 4.
    InvalidMemorySize,
};

/// Whether a VM can have `len` bytes of memory: at least 4, a multiple of 4, and a u32
/// (so at most 2^32 - 4), so that every address is a u32. The bounds checks depend on
/// it: they compute size - 4, which must not wrap.
pub fn validMemorySize(len: usize) bool {
    return len >= 4 and len % 4 == 0 and len <= std.math.maxInt(u32);
}

/// The memory size a snapshot holds, read from its first 12 or more bytes, so that a
/// host can allocate a RuntimeCpuType's memory before restoring the snapshot.
pub fn snapshotMemorySize(snapshot_start: []const u8) error{InvalidSnapshot}!u32 {
    return state.memorySize(snapshot_start);
}

/// A VM whose memory, `memory_size` bytes, is inside the struct: every bounds check
/// compares with a constant. The size must be at least 4 and a multiple of 4.
pub fn CpuType(comptime memory_size: u32, comptime options: Options) type {
    comptime {
        if (memory_size < 4) @compileError("memory_size must be >= 4");
        if (memory_size % 4 != 0) @compileError("memory_size must be divisible by 4");
    }
    return VmType(.{ .fixed = memory_size }, options);
}

/// A VM whose memory is a buffer the host passes to init(), of any size that
/// validMemorySize() accepts. The VM borrows the buffer and never allocates; the host
/// keeps it alive. Copying the struct shares the memory: fork a VM with a snapshot.
pub fn RuntimeCpuType(comptime options: Options) type {
    return VmType(.runtime, options);
}

/// How a VM holds its memory.
const MemoryKind = union(enum) {
    /// Inside the struct, of this size.
    fixed: u32,
    /// A host buffer, of a size chosen at run time.
    runtime,
};

fn VmType(comptime kind: MemoryKind, comptime options: Options) type {
    comptime {
        if (options.decode_cache_entries != 0 and !std.math.isPowerOfTwo(options.decode_cache_entries))
            @compileError("decode_cache_entries must be a power of two, or 0");
    }
    const decodeFn = options.decode;
    const cache_entries = options.decode_cache_entries;
    return struct {
        const Self = @This();
        /// The memory size of a CpuType. A RuntimeCpuType's size is known only at run
        /// time: use memSize().
        pub const mem_size: u32 = switch (kind) {
            .fixed => |n| n,
            .runtime => @compileError("a RuntimeCpuType's memory size is chosen at run time: use memSize()"),
        };
        pub const decode = decodeFn;
        pub const decode_cache_entries = cache_entries;

        pc: u32,
        regs: [32]u32,
        memory: switch (kind) {
            .fixed => |n| [n]u8,
            .runtime => []u8,
        },
        cycle_count: u64,
        reservation: ?u32,
        csrs: zicsr.Csr,
        /// Memo of decode(), indexed by pc and validated by the fetched instruction bits.
        /// Not architectural state: decode is a pure function of those bits, so a hit
        /// returns exactly what decoding would, and stale entries (after self-modifying
        /// code or host writes) simply miss. Excluded from stateDigest().
        decode_cache: [cache_entries]instructions.Instruction,
        /// Address of the ECALL or EBREAK that last stopped step()/run() (pc is already
        /// past it). Host-facing metadata, not architectural state: excluded from
        /// stateDigest(). 0 after reset().
        stop_pc: u32,

        /// Marks an empty cache slot. fetch() never returns this value: a 32-bit
        /// instruction has low bits 0b11, and a 16-bit one is zero-extended.
        const empty_slot: instructions.Instruction = .{ .op = .{ .i = .ECALL }, .raw = 0xFFFF_FFFC };
        comptime {
            if (!instructions.isCompressed(empty_slot.raw) or empty_slot.raw <= 0xFFFF)
                @compileError("empty_slot.raw must be a value fetch() cannot return");
        }

        /// A CpuType's init() takes no arguments; a RuntimeCpuType's takes its memory.
        /// INVARIANT: no allocators — all state is fixed-size (registers, memory, CSR
        /// struct), and a RuntimeCpuType's memory belongs to the host.
        pub const init = switch (kind) {
            .fixed => initFixed,
            .runtime => initRuntime,
        };

        /// Give a RuntimeCpuType `memory` and reset it, in place: for a VM on the heap
        /// (a large decode cache would not fit on the stack). error.InvalidMemorySize,
        /// changing nothing, unless validMemorySize(memory.len).
        pub const initInPlace = switch (kind) {
            .fixed => @compileError("a CpuType has its memory inside: use reset()"),
            .runtime => initInPlaceRuntime,
        };

        /// Return a zeroed VM by value. The whole memory lives inside Self, so this
        /// is for small memories only: for large ones, place Self on the heap or in
        /// static storage and call reset() on it instead.
        fn initFixed() Self {
            var self: Self = undefined;
            self.reset();
            return self;
        }

        /// Return a zeroed VM by value, with `memory` (zeroed too) as its memory.
        /// error.InvalidMemorySize unless validMemorySize(memory.len).
        fn initRuntime(memory: []u8) InitError!Self {
            var self: Self = undefined;
            try self.initInPlaceRuntime(memory);
            return self;
        }

        fn initInPlaceRuntime(self: *Self, memory: []u8) InitError!void {
            if (!validMemorySize(memory.len)) return error.InvalidMemorySize;
            self.memory = memory;
            self.reset();
        }

        /// Reset to the power-on state in place: pc = 0, registers, memory and
        /// counters zeroed, no reservation. A RuntimeCpuType keeps its buffer. Unlike
        /// init(), this never builds a Self temporary on the stack or a memory-sized
        /// constant in the binary.
        pub fn reset(self: *Self) void {
            self.pc = 0;
            self.regs = @splat(0);
            @memset(self.memory[0..], 0);
            self.cycle_count = 0;
            self.reservation = null;
            self.csrs = .{};
            @memset(&self.decode_cache, empty_slot);
            self.stop_pc = 0;
        }

        /// The memory size in bytes: a constant for a CpuType.
        pub inline fn memSize(self: *const Self) u32 {
            return switch (kind) {
                .fixed => |n| n,
                .runtime => @intCast(self.memory.len),
            };
        }

        /// Size of a CpuType's snapshot: the state header plus the memory image.
        pub const snapshot_size: usize = state.header_len + mem_size;

        /// Size of a snapshot: the state header plus the memory image.
        pub fn snapshotSize(self: *const Self) usize {
            return state.header_len + @as(usize, self.memSize());
        }

        /// Write a snapshot of the architectural state (versioned, little-endian; the
        /// bytes stateDigest() hashes). See docs/design/snapshots.md.
        pub fn writeSnapshot(self: *const Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            return state.writeSnapshot(self, w);
        }

        /// Restore the architectural state from a snapshot of a VM with the same memory
        /// size. Empties the decode cache and sets stop_pc to 0. Returns
        /// error.InvalidSnapshot, before changing anything, for a malformed header.
        pub fn restoreSnapshot(self: *Self, r: *std.Io.Reader) state.RestoreError!void {
            try state.restoreSnapshot(self, r);
            @memset(&self.decode_cache, empty_slot);
            self.stop_pc = 0;
        }

        /// SHA-256 of the canonical state encoding (see cpu/state.zig): pc, all 32
        /// registers, cycle count, reservation, CSRs and the whole memory, serialized
        /// little-endian. Identical on every host for identical architectural state.
        pub fn stateDigest(self: *const Self) [32]u8 {
            return state.digest(self);
        }

        /// Read register. x0 always returns 0.
        pub fn readReg(self: *const Self, reg: u5) u32 {
            if (reg == 0) return 0;
            return self.regs[reg];
        }

        /// Write register. Writes to x0 are silently discarded. Branch-free on the hot
        /// path: write, then restore regs[0] = 0.
        pub fn writeReg(self: *Self, reg: u5, value: u32) void {
            self.regs[reg] = value;
            self.regs[0] = 0;
        }

        /// Fetch the instruction at PC (little-endian). Returns a 16-bit compressed
        /// instruction zero-extended to u32 when bits [1:0] != 0b11, or a full 32-bit word.
        pub fn fetch(self: *const Self) !u32 {
            if (self.pc % 2 != 0) return error.MisalignedPC;
            if (self.pc > self.memSize() - 2) return error.PCOutOfBounds;
            const addr: usize = self.pc;
            const low: u16 = std.mem.readInt(u16, self.memory[addr..][0..2], .little);
            if (instructions.isCompressed(low)) return @as(u32, low);
            if (self.pc > self.memSize() - 4) return error.PCOutOfBounds;
            return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
        }

        /// Load program bytes into memory at the given offset. Like a guest store, this
        /// drops an LR reservation on any word it overwrites.
        pub fn loadProgram(self: *Self, program: []const u8, offset: u32) !void {
            const off: usize = offset;
            const size: usize = self.memSize();
            if (program.len > size or off > size - program.len) return error.AddressOutOfBounds;
            @memcpy(self.memory[off..][0..program.len], program);
            self.invalidateReservationRange(off, program.len);
        }

        /// Drop the LR reservation, if any. A host that writes `memory` directly
        /// (instead of through loadProgram or the write* methods) must call this, or a
        /// later SC.W could succeed although its reserved word changed.
        pub fn clearReservation(self: *Self) void {
            self.reservation = null;
        }

        // --- Memory helpers ---
        // INVARIANT: all multi-byte access uses explicit .little endianness — never .native

        pub fn readByte(self: *const Self, addr: u32) !u8 {
            if (addr >= self.memSize()) return error.AddressOutOfBounds;
            return self.memory[addr];
        }

        pub fn readHalfword(self: *const Self, addr: u32) !u16 {
            if (addr % 2 != 0) return error.MisalignedAccess;
            if (addr > self.memSize() - 2) return error.AddressOutOfBounds;
            return std.mem.readInt(u16, self.memory[addr..][0..2], .little);
        }

        pub fn readWord(self: *const Self, addr: u32) !u32 {
            try self.checkWordAccess(addr);
            return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
        }

        pub fn writeByte(self: *Self, addr: u32, value: u8) !void {
            if (addr >= self.memSize()) return error.AddressOutOfBounds;
            self.memory[addr] = value;
            self.invalidateReservation(addr);
        }

        pub fn writeHalfword(self: *Self, addr: u32, value: u16) !void {
            if (addr % 2 != 0) return error.MisalignedAccess;
            if (addr > self.memSize() - 2) return error.AddressOutOfBounds;
            std.mem.writeInt(u16, self.memory[addr..][0..2], value, .little);
            self.invalidateReservation(addr);
        }

        pub fn writeWord(self: *Self, addr: u32, value: u32) !void {
            try self.checkWordAccess(addr);
            std.mem.writeInt(u32, self.memory[addr..][0..4], value, .little);
            self.invalidateReservation(addr);
        }

        /// Alignment, then bounds: the checks every word access makes before touching memory.
        fn checkWordAccess(self: *const Self, addr: u32) error{ MisalignedAccess, AddressOutOfBounds }!void {
            if (addr % 4 != 0) return error.MisalignedAccess;
            if (addr > self.memSize() - 4) return error.AddressOutOfBounds;
        }

        /// Invalidate reservation if write overlaps reserved word.
        /// INVARIANT: every write method (writeByte/writeHalfword/writeWord) MUST call this,
        /// and every other write to memory must call invalidateReservationRange or
        /// clearReservation.
        fn invalidateReservation(self: *Self, addr: u32) void {
            if (self.reservation) |res_addr| {
                if ((addr & 0xFFFFFFFC) == res_addr) { // word-aligned address comparison (clear lower 2 bits)
                    self.reservation = null;
                }
            }
        }

        /// Invalidate reservation if the bytes [start, start + len) overlap the reserved word.
        fn invalidateReservationRange(self: *Self, start: usize, len: usize) void {
            if (self.reservation) |res_addr| {
                const res: usize = res_addr;
                if (len != 0 and start < res + 4 and res < start + len) {
                    self.reservation = null;
                }
            }
        }

        // --- Execution loop ---

        /// Run until ECALL, EBREAK, a fault, or `cycle_count >= max_cycles`. The limit is
        /// absolute (compared with cycle_count, which keeps counting across calls); use
        /// runFor() for a budget relative to now. null means no limit; a limit already
        /// reached returns .continue without executing anything.
        pub fn run(self: *Self, max_cycles: ?u64) StepError!StepResult {
            var result: StepResult = .@"continue";
            while (result == .@"continue") {
                if (max_cycles) |limit| {
                    if (self.cycle_count >= limit) return result;
                }
                result = try self.step();
            }
            return result;
        }

        /// Run at most `steps` more instructions: run(cycle_count + steps).
        pub fn runFor(self: *Self, steps: u64) StepError!StepResult {
            return self.run(self.cycle_count +| steps);
        }

        /// Fetch, decode, and execute one instruction. Advances PC and increments cycle_count.
        ///
        /// Pipeline invariant — the following order is load-bearing:
        ///   1. fetch()           — read raw instruction bits at current PC
        ///   2. decode()          — parse into Instruction struct
        ///   3. read rs1, rs2     — register reads happen BEFORE execution
        ///   4. execute           — modify registers/memory (may update next_pc for branches/jumps)
        ///   5. update PC         — written AFTER execution so branches see the old PC
        ///   6. increment cycle   — AFTER everything, so CSR reads of cycle see the pre-step count
        pub fn step(self: *Self) StepError!StepResult {
            const raw = try self.fetch();
            const inst = try self.decodeCached(raw);
            const inst_size: u32 = if (instructions.isCompressed(raw)) 2 else 4;

            // INVARIANT: pipeline step 3 — register reads BEFORE execution.
            // writeReg keeps regs[0] at 0; zeroing it here as well means a host that
            // wrote the field directly cannot leak a value into x0, and lets the reads
            // index regs[] without an x0 branch (7% faster than readReg here).
            self.regs[0] = 0;
            const rs1_val = self.regs[inst.rs1];
            const rs2_val = self.regs[inst.rs2];

            var result: StepResult = .@"continue";
            var next_pc: u32 = self.pc +% inst_size;

            switch (inst.op) {
                .i => |i_op| {
                    result = try cpu_exec_i.executeI(self, i_op, inst.rd, inst.imm, rs1_val, rs2_val, inst_size, &next_pc);
                },
                .m => |m_op| self.executeM(m_op, inst.rd, rs1_val, rs2_val),
                .a => |a_op| try self.executeA(a_op, inst.rd, rs1_val, rs2_val),
                .csr => |csr_op| try self.executeCsr(csr_op, inst.rd, inst.rs1, rs1_val, inst.csrAddr()),
                .zba => |op| self.executeZba(op, inst.rd, rs1_val, rs2_val),
                .zbb => |op| self.executeZbb(op, inst.rd, rs1_val, rs2_val, inst.immUnsigned()),
                .zbs => |op| self.executeZbs(op, inst.rd, rs1_val, rs2_val, inst.immUnsigned()),
            }

            if (result != .@"continue") self.stop_pc = self.pc;
            self.pc = next_pc; // INVARIANT: pipeline step 5 — PC updated AFTER execution
            self.cycle_count +%= 1; // INVARIANT: pipeline step 6 — cycle incremented last (CSR reads see pre-step value)
            return result;
        }

        /// Describe a fault that step() or run() just returned. A fault leaves the state
        /// unchanged, so the faulting instruction is still at pc; call this before
        /// changing the state.
        pub fn describeFault(self: *const Self, err: StepError) Fault {
            var fault: Fault = .{ .err = err, .pc = self.pc, .raw = null, .addr = null };
            const raw = self.fetch() catch {
                fault.addr = self.pc;
                return fault;
            };
            fault.raw = raw;
            const inst = decodeFn(raw) catch return fault;
            const rs1_val = self.readReg(inst.rs1);
            switch (inst.op) {
                .i => |op| switch (op) {
                    .LB, .LH, .LW, .LBU, .LHU, .SB, .SH, .SW => fault.addr = rs1_val +% inst.immUnsigned(),
                    else => {},
                },
                .a => fault.addr = rs1_val,
                else => {},
            }
            return fault;
        }

        /// decodeFn(raw), memoized per pc in decode_cache. A hit requires the slot to
        /// hold exactly `raw`, so the result is always what decodeFn(raw) returns.
        inline fn decodeCached(self: *Self, raw: u32) decoders.DecodeError!instructions.Instruction {
            if (cache_entries == 0) return decodeFn(raw);
            const slot = &self.decode_cache[(self.pc >> 1) & (cache_entries - 1)];
            if (slot.raw != raw) slot.* = try decodeFn(raw);
            return slot.*;
        }

        // --- RV32M helpers ---

        fn executeM(self: *Self, op: rv32m.Opcode, rd: u5, rs1_val: u32, rs2_val: u32) void {
            self.writeReg(rd, rv32m.execute(op, rs1_val, rs2_val));
        }

        // --- RV32A helpers ---

        fn executeA(self: *Self, op: rv32a.Opcode, rd: u5, rs1_val: u32, rs2_val: u32) !void {
            const addr = rs1_val;
            switch (op) {
                .LR_W => {
                    const val = try self.readWord(addr);
                    self.writeReg(rd, val);
                    self.reservation = addr;
                },
                .SC_W => {
                    // Memory checks come first: SC.W faults on a misaligned or
                    // out-of-bounds address whether or not it would succeed, and the
                    // fault leaves the reservation unchanged. (Spec: no SC.W retires
                    // unless it passes memory permission checks.)
                    try self.checkWordAccess(addr);
                    // reservation is guaranteed word-aligned (LR.W's readWord rejects
                    // misalignment), so direct equality suffices — no mask needed here.
                    if (self.reservation == addr) {
                        try self.writeWord(addr, rs2_val);
                        self.writeReg(rd, 0); // success
                    } else {
                        self.writeReg(rd, 1); // failure
                    }
                    self.reservation = null;
                },
                else => {
                    const old = try self.readWord(addr);
                    try self.writeWord(addr, rv32a.execute(op, old, rs2_val));
                    self.writeReg(rd, old);
                },
            }
        }

        // --- Zba helpers ---

        fn executeZba(self: *Self, op: zba.Opcode, rd: u5, rs1_val: u32, rs2_val: u32) void {
            self.writeReg(rd, zba.execute(op, rs1_val, rs2_val));
        }

        // --- Zbb helpers ---

        fn executeZbb(self: *Self, op: zbb.Opcode, rd: u5, rs1_val: u32, rs2_val: u32, imm: u32) void {
            const src2: u32 = if (op.format() == .R) rs2_val else imm;
            self.writeReg(rd, zbb.execute(op, rs1_val, src2));
        }

        // --- Zbs helpers ---

        fn executeZbs(self: *Self, op: zbs.Opcode, rd: u5, rs1_val: u32, rs2_val: u32, imm: u32) void {
            const src2: u32 = if (op.format() == .R) rs2_val else imm;
            self.writeReg(rd, zbs.execute(op, rs1_val, src2));
        }

        // --- Zicsr helpers ---

        /// Execute a CSR instruction.
        /// `rs1_field` serves dual role: register index for CSRRW/S/C, 5-bit zimm for CSRRWI/SI/CI.
        fn executeCsr(self: *Self, op: zicsr.Opcode, rd: u5, rs1_field: u5, rs1_val: u32, csr_addr: u12) !void {
            const src_val: u32 = switch (op) {
                .CSRRW, .CSRRS, .CSRRC => rs1_val,
                .CSRRWI, .CSRRSI, .CSRRCI => @intCast(rs1_field),
            };
            // INVARIANT: pass pre-step cycle_count so CSR reads see pre-increment value
            const result = try self.csrs.execute(op, self.cycle_count, csr_addr, src_val, rd != 0, rs1_field != 0);
            if (result.rd_val) |val| {
                self.writeReg(rd, val);
            }
        }
    };
}

/// The default memory size: `Cpu`'s, and the CLI's without --memory.
pub const default_memory_size: u32 = 64 * 1024;

/// A VM with the default 64 KiB of memory inside it.
pub const Cpu = CpuType(default_memory_size, .{});

/// A VM with a host buffer of any valid size as its memory.
pub const RuntimeCpu = RuntimeCpuType(.{});

/// CPU for the unit tests: always 64 KiB of memory.
pub const TestCpu = CpuType(64 * 1024, .{});

test "CpuType: custom memory size" {
    const SmallCpu = CpuType(4096, .{});
    var c = SmallCpu.init();
    try std.testing.expectEqual(@as(u32, 4096), SmallCpu.mem_size);
    c.writeReg(1, 42);
    try std.testing.expectEqual(@as(u32, 42), c.readReg(1));
    try std.testing.expectError(error.AddressOutOfBounds, c.readByte(4096));
}

test "CpuType: minimum memory size" {
    const TinyCpu = CpuType(4, .{});
    var c = TinyCpu.init();
    try c.writeByte(0, 0xFF);
    try std.testing.expectEqual(@as(u8, 0xFF), try c.readByte(0));
    try std.testing.expectError(error.AddressOutOfBounds, c.readByte(4));
}

test {
    _ = @import("cpu/tests.zig");
}
