//! RV32C expand() — maps compressed Opcode + halfword into Expanded (validates constraints, builds fields).

const rv32c = @import("rv32c.zig");
const rv32i = @import("../rv32i.zig");
const imm = @import("rv32c_imm.zig");

/// Expand a 16-bit compressed instruction into its equivalent Expanded form.
pub fn expand(half: u16) error{IllegalInstruction}!rv32c.Expanded {
    const op = try rv32c.decode(half);
    return switch (op) {
        .C_ADDI4SPN => {
            const nzu = imm.ciw_nzuimm(half);
            if (nzu == 0) return error.IllegalInstruction;
            return .{
                .op = .ADDI,
                .rd = imm.cReg(@truncate(half >> 2)),
                .rs1 = 2, // x2 = sp
                .imm = @intCast(nzu),
                .compressed_op = op,
            };
        },
        .C_LW => .{
            .op = .LW,
            .rd = imm.cReg(@truncate(half >> 2)),
            .rs1 = imm.cReg(@truncate(half >> 7)),
            .imm = @intCast(imm.clsw_offset(half)),
            .compressed_op = op,
        },
        .C_SW => .{
            .op = .SW,
            .rs1 = imm.cReg(@truncate(half >> 7)),
            .rs2 = imm.cReg(@truncate(half >> 2)),
            .imm = @intCast(imm.clsw_offset(half)),
            .compressed_op = op,
        },
        .C_ADDI => {
            const rd_val: u5 = @truncate(half >> 7);
            return .{
                .op = .ADDI,
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = imm.ci_imm(half),
                .compressed_op = op,
            };
        },
        .C_JAL => .{
            .op = .JAL,
            .rd = 1, // ra
            .imm = imm.cj_offset(half),
            .compressed_op = op,
        },
        .C_LI => {
            const rd_val: u5 = @truncate(half >> 7);
            return .{
                .op = .ADDI,
                .rd = rd_val,
                .rs1 = 0,
                .imm = imm.ci_imm(half),
                .compressed_op = op,
            };
        },
        .C_ADDI16SP => {
            const ci_imm_val = imm.ci_addi16sp_imm(half);
            if (ci_imm_val == 0) return error.IllegalInstruction;
            return .{
                .op = .ADDI,
                .rd = 2,
                .rs1 = 2,
                .imm = ci_imm_val,
                .compressed_op = op,
            };
        },
        .C_LUI => {
            const lui_imm = imm.ci_lui_imm(half);
            if (lui_imm == 0) return error.IllegalInstruction;
            return .{
                .op = .LUI,
                .rd = @truncate(half >> 7),
                .imm = lui_imm,
                .compressed_op = op,
            };
        },
        .C_SRLI => {
            const shamt = imm.ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            const rd_rs1 = imm.cReg(@truncate(half >> 7));
            return .{
                .op = .SRLI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .compressed_op = op,
            };
        },
        .C_SRAI => {
            const shamt = imm.ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            const rd_rs1 = imm.cReg(@truncate(half >> 7));
            return .{
                .op = .SRAI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = @intCast(shamt & 0x1F),
                .compressed_op = op,
            };
        },
        .C_ANDI => {
            const rd_rs1 = imm.cReg(@truncate(half >> 7));
            return .{
                .op = .ANDI,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .imm = imm.ci_imm(half),
                .compressed_op = op,
            };
        },
        .C_SUB, .C_XOR, .C_OR, .C_AND => {
            const rd_rs1 = imm.cReg(@truncate(half >> 7));
            const rs2_val = imm.cReg(@truncate(half >> 2));
            const base_op: rv32i.Opcode = switch (op) {
                .C_SUB => .SUB,
                .C_XOR => .XOR,
                .C_OR => .OR,
                .C_AND => .AND,
                else => unreachable,
            };
            return .{ .op = base_op, .rd = rd_rs1, .rs1 = rd_rs1, .rs2 = rs2_val, .compressed_op = op };
        },
        .C_J => .{
            .op = .JAL,
            .rd = 0,
            .imm = imm.cj_offset(half),
            .compressed_op = op,
        },
        .C_BEQZ => .{
            .op = .BEQ,
            .rs1 = imm.cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = imm.cb_offset(half),
            .compressed_op = op,
        },
        .C_BNEZ => .{
            .op = .BNE,
            .rs1 = imm.cReg(@truncate(half >> 7)),
            .rs2 = 0,
            .imm = imm.cb_offset(half),
            .compressed_op = op,
        },
        .C_SLLI => {
            const rd_val: u5 = @truncate(half >> 7);
            const shamt = imm.ci_shamt(half);
            if (shamt & 0x20 != 0) return error.IllegalInstruction; // shamt[5]=1 illegal on RV32
            return .{
                .op = .SLLI,
                .rd = rd_val,
                .rs1 = rd_val,
                .imm = @intCast(shamt & 0x1F),
                .compressed_op = op,
            };
        },
        .C_LWSP => {
            const rd_val: u5 = @truncate(half >> 7);
            if (rd_val == 0) return error.IllegalInstruction;
            return .{
                .op = .LW,
                .rd = rd_val,
                .rs1 = 2, // sp
                .imm = @intCast(imm.ci_lwsp_offset(half)),
                .compressed_op = op,
            };
        },
        .C_JR => {
            const rd_rs1: u5 = @truncate(half >> 7);
            if (rd_rs1 == 0) return error.IllegalInstruction;
            return .{
                .op = .JALR,
                .rd = 0,
                .rs1 = rd_rs1,
                .imm = 0,
                .compressed_op = op,
            };
        },
        .C_MV => {
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            return .{
                .op = .ADD,
                .rd = rd_rs1,
                .rs1 = 0,
                .rs2 = rs2_val,
                .compressed_op = op,
            };
        },
        .C_EBREAK => .{
            .op = .EBREAK,
            .compressed_op = op,
        },
        .C_JALR => {
            const rd_rs1: u5 = @truncate(half >> 7);
            return .{
                .op = .JALR,
                .rd = 1, // ra
                .rs1 = rd_rs1,
                .imm = 0,
                .compressed_op = op,
            };
        },
        .C_ADD => {
            const rd_rs1: u5 = @truncate(half >> 7);
            const rs2_val: u5 = @truncate(half >> 2);
            return .{
                .op = .ADD,
                .rd = rd_rs1,
                .rs1 = rd_rs1,
                .rs2 = rs2_val,
                .compressed_op = op,
            };
        },
        .C_SWSP => .{
            .op = .SW,
            .rs1 = 2, // sp
            .rs2 = @truncate(half >> 2),
            .imm = @intCast(imm.css_swsp_offset(half)),
            .compressed_op = op,
        },
    };
}
