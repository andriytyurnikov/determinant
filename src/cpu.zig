const std = @import("std");
const decoder = @import("decoder.zig");
const instruction = @import("instruction.zig");
const Opcode = instruction.Opcode;

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

    pub fn init() Cpu {
        return .{
            .pc = 0,
            .regs = [_]u32{0} ** 32,
            .memory = [_]u8{0} ** MEMORY_SIZE,
            .cycle_count = 0,
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

    /// Fetch the 32-bit instruction at PC (little-endian).
    pub fn fetch(self: *const Cpu) !u32 {
        if (self.pc % 4 != 0) return error.MisalignedPC;
        if (self.pc > MEMORY_SIZE - 4) return error.PCOutOfBounds;
        const addr: usize = self.pc;
        return std.mem.readInt(u32, self.memory[addr..][0..4], .little);
    }

    /// Load program bytes into memory at the given offset.
    pub fn loadProgram(self: *Cpu, program: []const u8, offset: u32) !void {
        const off: usize = offset;
        if (off + program.len > MEMORY_SIZE) return error.AddressOutOfBounds;
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
    }

    pub fn writeHalfword(self: *Cpu, addr: u32, value: u16) !void {
        if (addr % 2 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 2) return error.AddressOutOfBounds;
        const a: usize = addr;
        std.mem.writeInt(u16, self.memory[a..][0..2], value, .little);
    }

    pub fn writeWord(self: *Cpu, addr: u32, value: u32) !void {
        if (addr % 4 != 0) return error.MisalignedAccess;
        if (addr > MEMORY_SIZE - 4) return error.AddressOutOfBounds;
        const a: usize = addr;
        std.mem.writeInt(u32, self.memory[a..][0..4], value, .little);
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
    pub fn step(self: *Cpu) !StepResult {
        const raw = try self.fetch();
        const inst = try decoder.decode(raw);

        const imm_u: u32 = @bitCast(inst.imm);
        const rs1_val = self.readReg(inst.rs1);
        const rs2_val = self.readReg(inst.rs2);

        var result: StepResult = .Continue;
        var next_pc: u32 = self.pc +% 4;

        switch (inst.op) {
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
                if (rs1_val == rs2_val) next_pc = self.pc +% imm_u;
            },
            .BNE => {
                if (rs1_val != rs2_val) next_pc = self.pc +% imm_u;
            },
            .BLT => {
                if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))) next_pc = self.pc +% imm_u;
            },
            .BGE => {
                if (@as(i32, @bitCast(rs1_val)) >= @as(i32, @bitCast(rs2_val))) next_pc = self.pc +% imm_u;
            },
            .BLTU => {
                if (rs1_val < rs2_val) next_pc = self.pc +% imm_u;
            },
            .BGEU => {
                if (rs1_val >= rs2_val) next_pc = self.pc +% imm_u;
            },

            // Upper immediates
            .LUI => self.writeReg(inst.rd, imm_u),
            .AUIPC => self.writeReg(inst.rd, self.pc +% imm_u),

            // Jumps
            .JAL => {
                self.writeReg(inst.rd, self.pc + 4);
                next_pc = self.pc +% imm_u;
            },
            .JALR => {
                const return_addr = self.pc + 4;
                next_pc = (rs1_val +% imm_u) & 0xFFFFFFFE;
                self.writeReg(inst.rd, return_addr);
            },

            // System
            .ECALL => result = .Ecall,
            .EBREAK => result = .Ebreak,
        }

        self.pc = next_pc;
        self.cycle_count += 1;
        return result;
    }
};

test {
    _ = @import("cpu_test.zig");
}
