//! CpuType — parameterized RISC-V CPU core (memory size × decoder as comptime args).

const std = @import("std");
const build_options = @import("build_options");
const decoders = @import("../decoders.zig");
const instructions = @import("../instructions.zig");
const rv32i = instructions.rv32i;
const rv32m = instructions.rv32m;
const rv32a = instructions.rv32a;
const zicsr = instructions.zicsr;
const zba = instructions.zba;
const zbb = instructions.zbb;
const zbs = instructions.zbs;
const cpu_exec_i = @import("exec_i.zig");

pub const DecodeFn = *const fn (u32) decoders.DecodeError!instructions.Instruction;

pub const StepResult = cpu_exec_i.Result;

pub fn CpuType(comptime memory_size: u32, comptime decodeFn: DecodeFn) type {
    comptime {
        if (memory_size < 4) @compileError("memory_size must be >= 4");
        if (memory_size % 4 != 0) @compileError("memory_size must be divisible by 4");
    }
    return struct {
        const Self = @This();
        pub const mem_size: u32 = memory_size;
        pub const decode = decodeFn;

        pc: u32,
        regs: [32]u32,
        memory: [mem_size]u8,
        cycle_count: u64,
        reservation: ?u32,
        csrs: zicsr.Csr,

        /// INVARIANT: no allocators — all state is fixed-size (registers, memory, CSR struct).
        pub fn init() Self {
            return .{
                .pc = 0,
                .regs = [_]u32{0} ** 32,
                .memory = [_]u8{0} ** mem_size,
                .cycle_count = 0,
                .reservation = null,
                .csrs = .{},
            };
        }

        /// Read register. x0 always returns 0.
        pub fn readReg(self: *const Self, reg: u5) u32 {
            if (reg == 0) return 0;
            return self.regs[reg];
        }

        /// Write register. Writes to x0 are silently discarded.
        pub fn writeReg(self: *Self, reg: u5, value: u32) void {
            if (reg == 0) return;
            self.regs[reg] = value;
        }

        /// Fetch the instruction at PC (little-endian). Returns a 16-bit compressed
        /// instruction zero-extended to u32 when bits [1:0] != 0b11, or a full 32-bit word.
        pub fn fetch(self: *const Self) !u32 {
            if (self.pc % 2 != 0) return error.MisalignedPC;
            if (self.pc > mem_size - 2) return error.PCOutOfBounds;
            const addr: usize = self.pc;
            const low: u16 = std.mem.readInt(u16, self.memory[addr..][0..2], .little);
            if (instructions.isCompressed(low)) return @as(u32, low);
            if (self.pc > mem_size - 4) return error.PCOutOfBounds;
            return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
        }

        /// Load program bytes into memory at the given offset.
        pub fn loadProgram(self: *Self, program: []const u8, offset: u32) !void {
            const off: usize = offset;
            if (program.len > mem_size or off > mem_size - program.len) return error.AddressOutOfBounds;
            @memcpy(self.memory[off..][0..program.len], program);
        }

        // --- Memory helpers ---
        // INVARIANT: all multi-byte access uses explicit .little endianness — never .native

        pub fn readByte(self: *const Self, addr: u32) !u8 {
            if (addr >= mem_size) return error.AddressOutOfBounds;
            return self.memory[addr];
        }

        pub fn readHalfword(self: *const Self, addr: u32) !u16 {
            if (addr % 2 != 0) return error.MisalignedAccess;
            if (addr > mem_size - 2) return error.AddressOutOfBounds;
            return std.mem.readInt(u16, self.memory[addr..][0..2], .little);
        }

        pub fn readWord(self: *const Self, addr: u32) !u32 {
            if (addr % 4 != 0) return error.MisalignedAccess;
            if (addr > mem_size - 4) return error.AddressOutOfBounds;
            return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
        }

        pub fn writeByte(self: *Self, addr: u32, value: u8) !void {
            if (addr >= mem_size) return error.AddressOutOfBounds;
            self.memory[addr] = value;
            self.invalidateReservation(addr);
        }

        pub fn writeHalfword(self: *Self, addr: u32, value: u16) !void {
            if (addr % 2 != 0) return error.MisalignedAccess;
            if (addr > mem_size - 2) return error.AddressOutOfBounds;
            std.mem.writeInt(u16, self.memory[addr..][0..2], value, .little);
            self.invalidateReservation(addr);
        }

        pub fn writeWord(self: *Self, addr: u32, value: u32) !void {
            if (addr % 4 != 0) return error.MisalignedAccess;
            if (addr > mem_size - 4) return error.AddressOutOfBounds;
            std.mem.writeInt(u32, self.memory[addr..][0..4], value, .little);
            self.invalidateReservation(addr);
        }

        /// Invalidate reservation if write overlaps reserved word.
        /// INVARIANT: every write method (writeByte/writeHalfword/writeWord) MUST call this.
        fn invalidateReservation(self: *Self, addr: u32) void {
            if (self.reservation) |res_addr| {
                if ((addr & 0xFFFFFFFC) == res_addr) { // word-aligned address comparison (clear lower 2 bits)
                    self.reservation = null;
                }
            }
        }

        // --- Execution loop ---

        /// Run until ECALL, EBREAK, or max_cycles is reached. Returns the StepResult that stopped execution.
        /// If max_cycles is 0, runs without a cycle limit.
        pub fn run(self: *Self, max_cycles: u64) !StepResult {
            var result: StepResult = .@"continue";
            while (result == .@"continue") {
                if (max_cycles > 0 and self.cycle_count >= max_cycles) return result;
                result = try self.step();
            }
            return result;
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
        pub fn step(self: *Self) !StepResult {
            const raw = try self.fetch();
            const inst = try decodeFn(raw);
            const inst_size: u32 = if (instructions.isCompressed(raw)) 2 else 4;

            // INVARIANT: pipeline step 3 — register reads BEFORE execution
            const rs1_val = self.readReg(inst.rs1);
            const rs2_val = self.readReg(inst.rs2);

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

            self.pc = next_pc; // INVARIANT: pipeline step 5 — PC updated AFTER execution
            self.cycle_count +%= 1; // INVARIANT: pipeline step 6 — cycle incremented last (CSR reads see pre-step value)
            return result;
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

const default_decode: DecodeFn = if (build_options.use_branch_decoder)
    &decoders.branch_decoder.decode
else
    &decoders.lut_decoder.decode;

/// Default memory size — follows the `-Dmemory_size` build option (default: 64 KB).
pub const default_memory_size: u32 = build_options.memory_size;

/// Default Cpu — memory size follows `-Dmemory_size`, decoder follows `-Ddecoder`.
pub const Cpu = CpuType(default_memory_size, default_decode);

test "CpuType: custom memory size" {
    const SmallCpu = CpuType(4096, &decoders.lut_decoder.decode);
    var c = SmallCpu.init();
    try std.testing.expectEqual(@as(u32, 4096), SmallCpu.mem_size);
    c.writeReg(1, 42);
    try std.testing.expectEqual(@as(u32, 42), c.readReg(1));
    try std.testing.expectError(error.AddressOutOfBounds, c.readByte(4096));
}

test "CpuType: minimum memory size" {
    const TinyCpu = CpuType(4, &decoders.lut_decoder.decode);
    var c = TinyCpu.init();
    try c.writeByte(0, 0xFF);
    try std.testing.expectEqual(@as(u8, 0xFF), try c.readByte(0));
    try std.testing.expectError(error.AddressOutOfBounds, c.readByte(4));
}

test {
    _ = @import("cpu_test.zig");
}
