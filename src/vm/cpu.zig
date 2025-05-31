const std = @import("std");
const decoder = @import("decoder.zig");
const instructions = @import("instructions.zig");
const rv32i = instructions.rv32i;
const rv32m = instructions.rv32m;
const rv32a = instructions.rv32a;
const zicsr = instructions.zicsr;
const zba = instructions.zba;
const zbb = instructions.zbb;
const zbs = instructions.zbs;

pub const MEMORY_SIZE: u32 = 1024 * 1024; // 1 MB

pub const StepResult = enum {
    Continue,
    Ecall,
    Ebreak,
};

pub const Cpu = struct {
    pc: u32,
    regs: [32]u32,
    memory: [MEMORY_SIZE]u8,
    cycle_count: u64,
    reservation: ?u32,
    csrs: zicsr.Csr,

    pub fn init() Cpu {
        return .{
            .pc = 0,
            .regs = [_]u32{0} ** 32,
            .memory = [_]u8{0} ** MEMORY_SIZE,
            .cycle_count = 0,
            .reservation = null,
            .csrs = .{},
        };
    }

    /// Read register. x0 always returns 0.
    pub fn readReg(self: *const Cpu, reg: u5) u32 {
        if (reg == 0) return 0;
        return self.regs[reg];
    }

    /// Write register. Writes to x0 are silently discarded.
    pub fn writeReg(self: *Cpu, reg: u5, value: u32) void {
        if (reg == 0) return;
        self.regs[reg] = value;
    }

    /// Fetch the instruction at PC (little-endian). Returns a 16-bit compressed
    /// instruction zero-extended to u32 when bits [1:0] != 0b11, or a full 32-bit word.
    pub fn fetch(self: *const Cpu) !u32 {
        if (self.pc % 2 != 0) return error.MisalignedPC;
        if (self.pc > MEMORY_SIZE - 2) return error.PCOutOfBounds;
        const addr: usize = self.pc;
        const low: u16 = std.mem.readInt(u16, self.memory[addr..][0..2], .little);
        if (instructions.isCompressed(low)) return @as(u32, low);
        if (self.pc > MEMORY_SIZE - 4) return error.PCOutOfBounds;
        return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
    }

    /// Load program bytes into memory at the given offset.
    pub fn loadProgram(self: *Cpu, program: []const u8, offset: u32) !void {
        const off: usize = offset;
        if (program.len > MEMORY_SIZE or off > MEMORY_SIZE - program.len) return error.AddressOutOfBounds;
        @memcpy(self.memory[off..][0..program.len], program);
    }

    // --- Memory helpers ---

    pub fn readByte(self: *const Cpu, addr: u32) !u8 {
        if (addr >= MEMORY_SIZE) return error.AddressOutOfBounds;
        return self.memory[addr];
    }

    pub fn readHalfword(self: *const Cpu, addr: u32) !u16 {
        if (addr % 2 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 2) return error.AddressOutOfBounds;
        const a: usize = addr;
        return std.mem.readInt(u16, self.memory[a..][0..2], .little);
    }

    pub fn readWord(self: *const Cpu, addr: u32) !u32 {
        if (addr % 4 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 4) return error.AddressOutOfBounds;
        const a: usize = addr;
        return std.mem.readInt(u32, self.memory[a..][0..4], .little);
    }

    pub fn writeByte(self: *Cpu, addr: u32, value: u8) !void {
        if (addr >= MEMORY_SIZE) return error.AddressOutOfBounds;
        self.memory[addr] = value;
        self.invalidateReservation(addr);
    }

    pub fn writeHalfword(self: *Cpu, addr: u32, value: u16) !void {
        if (addr % 2 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 2) return error.AddressOutOfBounds;
        const a: usize = addr;
        std.mem.writeInt(u16, self.memory[a..][0..2], value, .little);
        self.invalidateReservation(addr);
    }

    pub fn writeWord(self: *Cpu, addr: u32, value: u32) !void {
        if (addr % 4 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 4) return error.AddressOutOfBounds;
        const a: usize = addr;
        std.mem.writeInt(u32, self.memory[a..][0..4], value, .little);
        self.invalidateReservation(addr);
    }

    // --- Executor ---

    /// Run until ECALL, EBREAK, or max_cycles is reached. Returns the StepResult that stopped execution.
    /// If max_cycles is 0, runs without a cycle limit.
    pub fn run(self: *Cpu, max_cycles: u64) !StepResult {
        var result: StepResult = .Continue;
        while (result == .Continue) {
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
    pub fn step(self: *Cpu) !StepResult {
        const raw = try self.fetch();
        const inst = try decoder.decode(raw);
        const inst_size: u32 = if (instructions.isCompressed(raw)) 2 else 4;

        const rs1_val = self.readReg(inst.rs1);
        const rs2_val = self.readReg(inst.rs2);

        var result: StepResult = .Continue;
        var next_pc: u32 = self.pc +% inst_size;

        switch (inst.op) {
            .i => |i_op| {
                result = try self.executeI(i_op, inst, rs1_val, rs2_val, inst_size, &next_pc);
            },
            .m => |m_op| self.executeM(m_op, inst.rd, rs1_val, rs2_val),
            .a => |a_op| try self.executeA(a_op, inst.rd, rs1_val, rs2_val),
            .csr => |csr_op| try self.executeCsr(csr_op, inst.rd, inst.rs1, rs1_val, inst.imm),
            .zba => |op| self.executeZba(op, inst.rd, rs1_val, rs2_val),
            .zbb => |op| self.executeZbb(op, inst.rd, rs1_val, rs2_val, @bitCast(inst.imm)),
            .zbs => |op| self.executeZbs(op, inst.rd, rs1_val, rs2_val, @bitCast(inst.imm)),
        }

        self.pc = next_pc;
        self.cycle_count +%= 1;
        return result;
    }

    fn executeI(self: *Cpu, op: rv32i.Opcode, inst: instructions.Instruction, rs1_val: u32, rs2_val: u32, inst_size: u32, next_pc: *u32) !StepResult {
        const imm_u: u32 = @bitCast(inst.imm);
        switch (op) {
            // R-type ALU
            .ADD => self.writeReg(inst.rd, rs1_val +% rs2_val),
            .SUB => self.writeReg(inst.rd, rs1_val -% rs2_val),
            .SLL => self.writeReg(inst.rd, rs1_val << @truncate(rs2_val & 0x1F)),
            .SLT => self.writeReg(inst.rd, if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))) 1 else 0),
            .SLTU => self.writeReg(inst.rd, if (rs1_val < rs2_val) 1 else 0),
            .XOR => self.writeReg(inst.rd, rs1_val ^ rs2_val),
            .SRL => self.writeReg(inst.rd, rs1_val >> @truncate(rs2_val & 0x1F)),
            .SRA => self.writeReg(inst.rd, @bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(rs2_val & 0x1F))),
            .OR => self.writeReg(inst.rd, rs1_val | rs2_val),
            .AND => self.writeReg(inst.rd, rs1_val & rs2_val),

            // I-type ALU
            .ADDI => self.writeReg(inst.rd, rs1_val +% imm_u),
            .SLTI => self.writeReg(inst.rd, if (@as(i32, @bitCast(rs1_val)) < inst.imm) 1 else 0),
            .SLTIU => self.writeReg(inst.rd, if (rs1_val < imm_u) 1 else 0),
            .XORI => self.writeReg(inst.rd, rs1_val ^ imm_u),
            .ORI => self.writeReg(inst.rd, rs1_val | imm_u),
            .ANDI => self.writeReg(inst.rd, rs1_val & imm_u),
            .SLLI => self.writeReg(inst.rd, rs1_val << @truncate(imm_u & 0x1F)),
            .SRLI => self.writeReg(inst.rd, rs1_val >> @truncate(imm_u & 0x1F)),
            .SRAI => self.writeReg(inst.rd, @bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(imm_u & 0x1F))),

            // Loads
            .LB => {
                const addr = rs1_val +% imm_u;
                const byte = try self.readByte(addr);
                self.writeReg(inst.rd, @bitCast(@as(i32, @as(i8, @bitCast(byte)))));
            },
            .LH => {
                const addr = rs1_val +% imm_u;
                const half = try self.readHalfword(addr);
                self.writeReg(inst.rd, @bitCast(@as(i32, @as(i16, @bitCast(half)))));
            },
            .LW => {
                const addr = rs1_val +% imm_u;
                const word = try self.readWord(addr);
                self.writeReg(inst.rd, word);
            },
            .LBU => {
                const addr = rs1_val +% imm_u;
                const byte = try self.readByte(addr);
                self.writeReg(inst.rd, @as(u32, byte));
            },
            .LHU => {
                const addr = rs1_val +% imm_u;
                const half = try self.readHalfword(addr);
                self.writeReg(inst.rd, @as(u32, half));
            },

            // Stores
            .SB => {
                const addr = rs1_val +% imm_u;
                try self.writeByte(addr, @truncate(rs2_val));
            },
            .SH => {
                const addr = rs1_val +% imm_u;
                try self.writeHalfword(addr, @truncate(rs2_val));
            },
            .SW => {
                const addr = rs1_val +% imm_u;
                try self.writeWord(addr, rs2_val);
            },

            // Branches
            .BEQ => {
                if (rs1_val == rs2_val) next_pc.* = self.pc +% imm_u;
            },
            .BNE => {
                if (rs1_val != rs2_val) next_pc.* = self.pc +% imm_u;
            },
            .BLT => {
                if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))) next_pc.* = self.pc +% imm_u;
            },
            .BGE => {
                if (@as(i32, @bitCast(rs1_val)) >= @as(i32, @bitCast(rs2_val))) next_pc.* = self.pc +% imm_u;
            },
            .BLTU => {
                if (rs1_val < rs2_val) next_pc.* = self.pc +% imm_u;
            },
            .BGEU => {
                if (rs1_val >= rs2_val) next_pc.* = self.pc +% imm_u;
            },

            // Upper immediates
            .LUI => self.writeReg(inst.rd, imm_u),
            .AUIPC => self.writeReg(inst.rd, self.pc +% imm_u),

            // Jumps
            .JAL => {
                self.writeReg(inst.rd, self.pc +% inst_size);
                next_pc.* = self.pc +% imm_u;
            },
            .JALR => {
                const return_addr = self.pc +% inst_size;
                next_pc.* = (rs1_val +% imm_u) & 0xFFFFFFFE;
                self.writeReg(inst.rd, return_addr);
            },

            // Memory ordering (no-op on single-hart)
            .FENCE => {},

            // System
            .ECALL => return .Ecall,
            .EBREAK => return .Ebreak,
        }
        return .Continue;
    }

    // --- RV32M helpers ---

    fn executeM(self: *Cpu, op: rv32m.Opcode, rd_reg: u5, rs1_val: u32, rs2_val: u32) void {
        self.writeReg(rd_reg, rv32m.execute(op, rs1_val, rs2_val));
    }

    // --- RV32A helpers ---

    fn invalidateReservation(self: *Cpu, addr: u32) void {
        if (self.reservation) |res_addr| {
            if ((addr & 0xFFFFFFFC) == res_addr) {
                self.reservation = null;
            }
        }
    }

    fn executeA(self: *Cpu, op: rv32a.Opcode, rd_reg: u5, rs1_val: u32, rs2_val: u32) !void {
        const addr = rs1_val;
        switch (op) {
            .LR_W => {
                const val = try self.readWord(addr);
                self.writeReg(rd_reg, val);
                self.reservation = addr;
            },
            .SC_W => {
                if (self.reservation == addr) {
                    try self.writeWord(addr, rs2_val);
                    self.writeReg(rd_reg, 0); // success
                } else {
                    self.writeReg(rd_reg, 1); // failure
                }
                self.reservation = null;
            },
            else => {
                const old = try self.readWord(addr);
                try self.writeWord(addr, rv32a.execute(op, old, rs2_val));
                self.writeReg(rd_reg, old);
            },
        }
    }

    // --- Zba helpers ---

    fn executeZba(self: *Cpu, op: zba.Opcode, rd_reg: u5, rs1_val: u32, rs2_val: u32) void {
        self.writeReg(rd_reg, zba.execute(op, rs1_val, rs2_val));
    }

    // --- Zbb helpers ---

    fn executeZbb(self: *Cpu, op: zbb.Opcode, rd_reg: u5, rs1_val: u32, rs2_val: u32, imm: u32) void {
        const src2: u32 = if (op.format() == .R) rs2_val else imm;
        self.writeReg(rd_reg, zbb.execute(op, rs1_val, src2));
    }

    // --- Zbs helpers ---

    fn executeZbs(self: *Cpu, op: zbs.Opcode, rd_reg: u5, rs1_val: u32, rs2_val: u32, imm: u32) void {
        const src2: u32 = if (op.format() == .R) rs2_val else imm;
        self.writeReg(rd_reg, zbs.execute(op, rs1_val, src2));
    }

    // --- Zicsr helpers ---

    fn executeCsr(self: *Cpu, op: zicsr.Opcode, rd_reg: u5, rs1_field: u5, rs1_val: u32, imm: i32) !void {
        const csr_addr: u12 = @truncate(@as(u32, @bitCast(imm)));
        const src_val: u32 = switch (op) {
            .CSRRW, .CSRRS, .CSRRC => rs1_val,
            .CSRRWI, .CSRRSI, .CSRRCI => @intCast(rs1_field),
        };
        const result = try self.csrs.execute(op, self.cycle_count, csr_addr, src_val, rd_reg != 0, rs1_field != 0);
        if (result.rd_val) |val| {
            self.writeReg(rd_reg, val);
        }
    }
};

test {
    _ = @import("cpu_test.zig");
}
