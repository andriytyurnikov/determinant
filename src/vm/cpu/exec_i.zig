//! RV32I execute logic — free function operating on anytype CPU.

const rv32i = @import("../instructions.zig").rv32i;

pub const Result = enum {
    @"continue",
    ecall,
    ebreak,
};

/// Execute an RV32I instruction. `cpu` is the CpuType instance (anytype resolves at comptime).
pub fn executeI(cpu: anytype, op: rv32i.Opcode, rd: u5, imm: i32, rs1_val: u32, rs2_val: u32, inst_size: u32, next_pc: *u32) !Result {
    const imm_u: u32 = @bitCast(imm);
    switch (op) {
        // R-type ALU
        // INVARIANT: wrapping arithmetic (+%, -%) — overflow must wrap, not trap
        .ADD => cpu.writeReg(rd, rs1_val +% rs2_val),
        .SUB => cpu.writeReg(rd, rs1_val -% rs2_val),
        .SLL => cpu.writeReg(rd, rs1_val << @truncate(rs2_val & 0x1F)),
        .SLT => cpu.writeReg(rd, if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))) 1 else 0),
        .SLTU => cpu.writeReg(rd, if (rs1_val < rs2_val) 1 else 0),
        .XOR => cpu.writeReg(rd, rs1_val ^ rs2_val),
        .SRL => cpu.writeReg(rd, rs1_val >> @truncate(rs2_val & 0x1F)),
        .SRA => cpu.writeReg(rd, @bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(rs2_val & 0x1F))),
        .OR => cpu.writeReg(rd, rs1_val | rs2_val),
        .AND => cpu.writeReg(rd, rs1_val & rs2_val),

        // I-type ALU
        .ADDI => cpu.writeReg(rd, rs1_val +% imm_u),
        .SLTI => cpu.writeReg(rd, if (@as(i32, @bitCast(rs1_val)) < imm) 1 else 0),
        .SLTIU => cpu.writeReg(rd, if (rs1_val < imm_u) 1 else 0),
        .XORI => cpu.writeReg(rd, rs1_val ^ imm_u),
        .ORI => cpu.writeReg(rd, rs1_val | imm_u),
        .ANDI => cpu.writeReg(rd, rs1_val & imm_u),
        .SLLI => cpu.writeReg(rd, rs1_val << @truncate(imm_u & 0x1F)),
        .SRLI => cpu.writeReg(rd, rs1_val >> @truncate(imm_u & 0x1F)),
        .SRAI => cpu.writeReg(rd, @bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(imm_u & 0x1F))),

        // Loads — INVARIANT: wrapping address calc (+%); sign-extend via cascading bitcasts
        .LB => {
            const addr = rs1_val +% imm_u;
            const byte = try cpu.readByte(addr);
            cpu.writeReg(rd, @bitCast(@as(i32, @as(i8, @bitCast(byte)))));
        },
        .LH => {
            const addr = rs1_val +% imm_u;
            const half = try cpu.readHalfword(addr);
            cpu.writeReg(rd, @bitCast(@as(i32, @as(i16, @bitCast(half)))));
        },
        .LW => {
            const addr = rs1_val +% imm_u;
            const word = try cpu.readWord(addr);
            cpu.writeReg(rd, word);
        },
        .LBU => {
            const addr = rs1_val +% imm_u;
            const byte = try cpu.readByte(addr);
            cpu.writeReg(rd, @as(u32, byte));
        },
        .LHU => {
            const addr = rs1_val +% imm_u;
            const half = try cpu.readHalfword(addr);
            cpu.writeReg(rd, @as(u32, half));
        },

        // Stores
        .SB => {
            const addr = rs1_val +% imm_u;
            try cpu.writeByte(addr, @truncate(rs2_val));
        },
        .SH => {
            const addr = rs1_val +% imm_u;
            try cpu.writeHalfword(addr, @truncate(rs2_val));
        },
        .SW => {
            const addr = rs1_val +% imm_u;
            try cpu.writeWord(addr, rs2_val);
        },

        // Branches — INVARIANT: wrapping target calc (pc +% imm)
        .BEQ => {
            if (rs1_val == rs2_val) next_pc.* = cpu.pc +% imm_u;
        },
        .BNE => {
            if (rs1_val != rs2_val) next_pc.* = cpu.pc +% imm_u;
        },
        .BLT => {
            if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))) next_pc.* = cpu.pc +% imm_u;
        },
        .BGE => {
            if (@as(i32, @bitCast(rs1_val)) >= @as(i32, @bitCast(rs2_val))) next_pc.* = cpu.pc +% imm_u;
        },
        .BLTU => {
            if (rs1_val < rs2_val) next_pc.* = cpu.pc +% imm_u;
        },
        .BGEU => {
            if (rs1_val >= rs2_val) next_pc.* = cpu.pc +% imm_u;
        },

        // Upper immediates
        .LUI => cpu.writeReg(rd, imm_u),
        .AUIPC => cpu.writeReg(rd, cpu.pc +% imm_u),

        // Jumps
        .JAL => {
            cpu.writeReg(rd, cpu.pc +% inst_size);
            next_pc.* = cpu.pc +% imm_u;
        },
        .JALR => {
            const return_addr = cpu.pc +% inst_size;
            next_pc.* = (rs1_val +% imm_u) & 0xFFFFFFFE; // INVARIANT: clear bit[0] per RISC-V spec
            cpu.writeReg(rd, return_addr);
        },

        // Memory ordering (no-ops on single-hart)
        .FENCE, .FENCE_I => {},

        // System
        .ECALL => return .ecall,
        .EBREAK => return .ebreak,
    }
    return .@"continue";
}
