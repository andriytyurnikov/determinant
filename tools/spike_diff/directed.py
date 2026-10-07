#!/usr/bin/env python3
"""Directed edge cases: Spike vs Determinant.

  python3 -I tools/spike_diff/directed.py [-k SUBSTRING] [-v] [--work DIR] [tool options]

Each test is a standalone program: a common prologue (x_i = i * 0x01010101, gp =
data_region, data word i = 0xC0DE0000 | i), the test body, then ebreak. A faulting test
ends at the fault: Spike's trap handler dumps the state, the runner returns the error.
Each test declares `expect`: "match" (Spike and Determinant must agree) or the tag of a
known divergence (README.md). The report prints MATCH or DIVERGE per test, whether that
was expected, and the registers in `show`; it is also written to WORK/directed/results.txt.
The exit status is 1 if any result was unexpected.
"""
import argparse
import os
import sys

sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

import pipeline  # noqa: E402
from template import DATA_SIZE, LOAD_ADDR, assemble_program  # noqa: E402

TESTS = []


def test(name, expect="match", show=(), spike_args=(), note=""):
    def deco(fn):
        TESTS.append(dict(name=name, fn=fn, expect=expect, show=show, spike_args=spike_args, note=note))
        return fn
    return deco


def rvc(*lines):
    return [".option rvc", *lines, ".option norvc"]


def h16(v):
    return f".2byte 0x{v:04x}"


def w32(v):
    return f".4byte 0x{v:08x}"


def rtype(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def itype(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


A0, A1, A2, A3, A4, A5, A6, A7 = 10, 11, 12, 13, 14, 15, 16, 17
S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11 = 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27
MASK32 = 0xFFFFFFFF


# --------------------------------------------------------------------------- M extension
M_PAIRS = [(0x80000000, 0xFFFFFFFF), (0x80000000, 0), (0, 0), (5, 0), (0xFFFFFFFB, 0),
           (7, 0xFFFFFFFE), (0xFFFFFFF9, 2), (0xFFFFFFF9, 0xFFFFFFFE), (0x7FFFFFFF, 0xFFFFFFFF),
           (0x80000000, 1), (0x80000000, 0x80000000), (0xFFFFFFFF, 0xFFFFFFFF),
           (0x7FFFFFFF, 0x7FFFFFFF), (0x80000000, 0x7FFFFFFF), (1, 0xFFFFFFFF), (0xFFFFFFFF, 1),
           (0x12345678, 0x9ABCDEF0), (0xFFFFFFFF, 0x80000000), (0x7FFFFFFF, 0x80000000)]
M_OPS = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]


@test("m_div_rem_mul_edges", note="all 8 M ops over 19 edge pairs (div/rem by 0, INT_MIN/-1, MULH* sign mixes)")
def _():
    out, off = [], 0
    for x, y in M_PAIRS:
        out += [f"li a0, 0x{x:x}", f"li a1, 0x{y:x}"]
        for op in M_OPS:
            out += [f"{op} a2, a0, a1", f"sw a2, {off}(gp)"]
            off += 4
    # aliasing rd == rs1 == rs2
    out += ["li a3, 0", "div a3, a3, a3", "li a4, 0", "remu a4, a4, a4",
            "li a5, 0x80000000", "mulh a5, a5, a5", "li a6, 0xffffffff", "mulhsu a6, a6, a6"]
    return out


# --------------------------------------------------------------------------- shifts / Zb*
SH_VALUES = [0x80000001, 0xFFFFFFFF, 0x12345678, 1]
SH_AMTS = [0, 1, 31, 32, 33, 63, 64, 0xFFFFFFFF, 0x80000005, 0x7FFFFFE0]
SH_OPS = ["sll", "srl", "sra", "rol", "ror", "bclr", "bext", "binv", "bset"]


@test("shift_rot_bit_register_amounts", note="register shift/rotate/bit-index amounts >= 32 must use the low 5 bits")
def _():
    out, off = [], 0
    for v in SH_VALUES:
        for amt in SH_AMTS:
            out += [f"li a0, 0x{v:x}", f"li a1, 0x{amt:x}"]
            for op in SH_OPS:
                out += [f"{op} a2, a0, a1", f"sw a2, {off}(gp)"]
                off += 4
    return out


CMP_PAIRS = [(0, 0), (5, 5), (0xFFFFFFFF, 0xFFFFFFFF), (0x80000000, 0x80000000), (0x7FFFFFFF, 0x7FFFFFFF),
             (4, 5), (5, 4), (0x7FFFFFFF, 0x80000000), (0x80000000, 0x7FFFFFFF), (0xFFFFFFFF, 0), (0, 0xFFFFFFFF)]
CMP_OPS = ["slt", "sltu", "min", "minu", "max", "maxu"]


@test("compare_equal_adjacent_boundary_operands",
      note="SLT/SLTU/MIN*/MAX* and every branch on equal, adjacent and sign-boundary operands, rs1 == rs2, "
           "SLTI/SLTIU with imm equal to the operand")
def _():
    out, off = [], 0
    for x, y in CMP_PAIRS:
        out += [f"li a0, 0x{x:x}", f"li a1, 0x{y:x}"]
        for op in CMP_OPS:
            out += [f"{op} a2, a0, a1", f"sw a2, {off}(gp)", f"{op} a3, a0, a0", f"sw a3, {off + 4}(gp)"]
            off += 8
        for br in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
            out += ["li a2, 0", f"{br} a0, a1, 1f", "li a2, 1", "1:", f"sw a2, {off}(gp)"]
            off += 4
    for imm in (0, 5, -1, -2048, 2047):
        out += [f"li a0, {imm}", f"slti a2, a0, {imm}", f"sltiu a3, a0, {imm}",
                f"sw a2, {off}(gp)", f"sw a3, {off + 4}(gp)"]
        off += 8
    return out


UN_VALUES = [0, 0xFFFFFFFF, 0x80000000, 1, 0x00010000, 0x80, 0x8000, 0x7F, 0x7FFF, 0x00FF0000,
             0x01000000, 0x12345678, 0x00800080, 0x80008000]
UN_OPS = ["clz a2, a0", "ctz a2, a0", "cpop a2, a0", "orc.b a2, a0", "rev8 a2, a0", "sext.b a2, a0",
          "sext.h a2, a0", "zext.h a2, a0", "rori a2, a0, 0", "rori a2, a0, 1", "rori a2, a0, 31",
          "slli a2, a0, 0", "slli a2, a0, 31", "srli a2, a0, 31", "srai a2, a0, 31", "srai a2, a0, 0",
          "bclri a2, a0, 31", "bexti a2, a0, 31", "binvi a2, a0, 0", "bseti a2, a0, 31",
          "bexti a2, a0, 0", "sltiu a2, a0, -1", "slti a2, a0, -2048", "xori a2, a0, -1"]


@test("unary_bitmanip_and_imm_shifts", note="CLZ/CTZ/CPOP of 0, ORC.B, REV8, SEXT/ZEXT, RORI 0/1/31, imm shifts")
def _():
    out, off = [], 0
    for v in UN_VALUES:
        out.append(f"li a0, 0x{v:x}")
        for op in UN_OPS:
            out += [op, f"sw a2, {off}(gp)"]
            off += 4
    return out


@test("load_sign_zero_extension", note="LB/LBU/LH/LHU at every offset over 0x80/0x7F/0xFF/0x8000 patterns")
def _():
    out = ["li t0, 0x807fff00", "sw t0, 0(gp)", "li t0, 0x7fff8000", "sw t0, 4(gp)"]
    off = 64
    for o in range(8):
        for op in ("lb", "lbu"):
            out += [f"{op} a2, {o}(gp)", f"sw a2, {off}(gp)"]
            off += 4
    for o in (0, 2, 4, 6):
        for op in ("lh", "lhu"):
            out += [f"{op} a2, {o}(gp)", f"sw a2, {off}(gp)"]
            off += 4
    # positive 12-bit offsets up to 2047 (the random programs mostly use [-1024, 0])
    out += ["addi t1, gp, -1024", "lw a3, 2044(t1)", "lbu a4, 2047(t1)", "sb a3, 2047(t1)",
            "sh a3, 2046(t1)", "addi t2, gp, 2047", "lb a5, -2047(t2)"]
    return out


# --------------------------------------------------------------------------- jumps
@test("jump_link_values", show=[S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11],
      note="JAL/C.JAL/JALR/C.JALR links (pc+4 vs pc+2), JALR odd target, rd==rs1, C.JALR ra, "
           "32-bit insns and targets at 2-mod-4 addresses")
def _():
    return [
        "jal ra, 1f",
        "1: mv s1, ra",
        *rvc("c.jal 2f"),
        "2: mv s2, ra",              # 32-bit instruction at a 2-mod-4 address
        "la t0, 3f",
        "jalr ra, 0(t0)",
        "3: mv s3, ra",
        "la t0, 4f",
        *rvc("c.jalr t0"),
        "4: mv s4, ra",
        "la t0, 5f+1",
        "jalr a0, 0(t0)",           # odd target: bit 0 must be cleared
        "5: mv s5, a0",
        "la t1, 6f",
        "jalr t1, 0(t1)",           # rd == rs1: the target uses the old t1
        "6: mv s6, t1",
        "la ra, 7f",
        *rvc("c.jalr ra"),          # rs1 == ra == link register
        "7: mv s7, ra",
        "la t2, 8f",
        *rvc("c.jr t2"),
        "li a5, 0xbad",
        "8: la t0, 9f+16",
        "jalr a6, -16(t0)",
        "9: mv s8, a6",
        "la t0, 10f-2047+1",
        "jalr a7, 2047(t0)",        # maximum positive imm, odd sum
        "10: mv s9, a7",
        *rvc("c.nop"),
        "jal s10, 11f",
        "11:",
        *rvc("c.nop"),
        "beq x0, x0, 12f",
        "li a5, 0xbad2",
        *rvc("c.nop"),
        "12: auipc s11, 0",
    ]


@test("far_branch_jump_offsets", show=[S1, S2, S3, S4, S5, S6, S7, S8, 28, 29],
      note="JAL +/-0x2F000, B-type +4094/-4096, C.J +2046/-2048, C.BEQZ/C.BNEZ +254/-256")
def _():
    return [
        "jal t3, Lfar_fwd",
        "Lfar_back:",
        "mv s1, t3",
        "mv s2, t4",
        "j Lafter_far",
        ".skip 0x2f000",
        "Lfar_fwd:",
        "jal t4, Lfar_back",
        "Lafter_far:",
        "beq x0, x0, Lb_pos",
        ".skip 4090",
        "Lb_pos:",
        "addi s3, x0, 1",
        "j Lb_neg_br",
        "Lb_neg_tgt:",
        "addi s4, x0, 2",
        "j Lb_done",
        ".skip 4088",
        "Lb_neg_br:",
        "beq x0, x0, Lb_neg_tgt",
        "Lb_done:",
        *rvc("c.j Lcj_pos"),
        ".skip 2044",
        "Lcj_pos:",
        "addi s5, x0, 3",
        "j Lcj_neg_br",
        "Lcj_neg_tgt:",
        "addi s6, x0, 4",
        "j Lcj_done",
        ".skip 2040",
        "Lcj_neg_br:",
        *rvc("c.j Lcj_neg_tgt"),
        "Lcj_done:",
        "li s0, 0",
        *rvc("c.beqz s0, Lcb_pos"),
        ".skip 252",
        "Lcb_pos:",
        "addi s7, x0, 5",
        "j Lcb_neg_br",
        "Lcb_neg_tgt:",
        "addi s8, x0, 6",
        "j Lcb_done",
        ".skip 248",
        "Lcb_neg_br:",
        *rvc("c.bnez s1, Lcb_neg_tgt"),
        "Lcb_done:",
        *rvc("c.jal Lcjal_pos"),
        ".skip 2044",
        "Lcjal_pos:",
        "mv t4, ra",
    ]


# --------------------------------------------------------------------------- LR/SC/AMO
LRSC_PRE = ["li a2, 0xaaaa5555", "li a5, 0x0f0f0f0f"]


def lrsc(name, body, expect="match", note=""):
    test(name, expect=expect, show=[A0, A1, A3, A4, A6], note=note)(lambda: LRSC_PRE + body)


lrsc("lrsc_success", ["lr.w a0, (gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"], note="LR;SC succeeds (a1=0), mem updated")
lrsc("sc_without_lr", ["sc.w a1, a2, (gp)", "lw a3, 0(gp)"], note="SC without LR fails (a1=1), mem unchanged")
lrsc("sc_other_address", ["lr.w a0, (gp)", "addi t1, gp, 4", "sc.w a1, a2, (t1)", "sc.w a4, a2, (gp)", "lw a3, 0(gp)"],
     note="SC to another word fails; the reservation is then gone")
lrsc("lr_sw_same_word_sc", ["lr.w a0, (gp)", "sw a5, 0(gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     expect="same-hart-store", note="plain SW to the reserved word between LR and SC")
lrsc("lr_sb_same_word_sc", ["lr.w a0, (gp)", "sb a5, 3(gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     expect="same-hart-store", note="SB to byte 3 of the reserved word")
lrsc("lr_sh_same_word_sc", ["lr.w a0, (gp)", "sh a5, 2(gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     expect="same-hart-store", note="SH to the upper half of the reserved word")
lrsc("lr_sw_other_word_sc", ["lr.w a0, (gp)", "sw a5, 4(gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     note="a store to another word keeps the reservation")
lrsc("lr_amo_same_word_sc", ["lr.w a0, (gp)", "amoadd.w a6, a5, (gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     expect="same-hart-store", note="AMO to the reserved word between LR and SC")
lrsc("lr_amo_other_word_sc", ["addi t1, gp, 8", "lr.w a0, (gp)", "amoor.w a6, a5, (t1)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     note="AMO to another word")
lrsc("lr_sc_sc", ["lr.w a0, (gp)", "sc.w a1, a2, (gp)", "sc.w a4, a5, (gp)", "lw a3, 0(gp)"],
     note="a second SC fails")
lrsc("lr_lr_sc", ["addi t1, gp, 4", "lr.w a0, (gp)", "lr.w a6, (t1)", "sc.w a1, a2, (gp)", "sc.w a4, a2, (t1)", "lw a3, 0(gp)"],
     note="a second LR moves the reservation; both SCs fail")
lrsc("lr_x0_then_sc", ["lr.w x0, (gp)", "sc.w a1, a2, (gp)", "lw a3, 0(gp)"], note="LR.W rd=x0 still reserves")
lrsc("sc_rd_x0", ["lr.w a0, (gp)", "sc.w x0, a2, (gp)", "lw a3, 0(gp)"], note="SC.W rd=x0 stores, no register write")
lrsc("amo_rd_x0", ["amoswap.w x0, a2, (gp)", "lw a3, 0(gp)", "addi t1, gp, 4", "amomaxu.w x0, a2, (t1)", "lw a4, 4(gp)"],
     note="AMO rd=x0 still updates memory")
lrsc("amo_rd_eq_rs1_rs2", ["mv t1, gp", "amoadd.w t1, t1, (t1)", "mv a6, gp", "amoswap.w a6, a6, (a6)", "lw a3, 0(gp)"],
     note="AMO rd==rs1==rs2 (address and operand read before the rd write)")
lrsc("sc_misaligned_no_reservation", ["addi t1, gp, 2", "sc.w a1, a2, (t1)", "li a4, 0x77"],
     note="SC.W misaligned without a reservation: both fault (store/AMO misaligned)")
lrsc("sc_misaligned_with_reservation", ["lr.w a0, (gp)", "addi t1, gp, 1", "sc.w a1, a2, (t1)", "li a4, 0x77"],
     note="SC.W misaligned after an LR of the aligned word: both fault")
lrsc("sc_out_of_bounds_no_reservation", ["li t1, 0x50000", "sc.w a1, a2, (t1)", "li a4, 0x77"],
     note="SC.W to an unmapped address without a reservation: both fault (store/AMO access)")
lrsc("sc_far_out_of_bounds", ["li t1, 0x80000000", "sc.w a1, a2, (t1)", "li a4, 0x77"],
     note="SC.W to 0x80000000: both fault")
lrsc("amo_misaligned", ["addi t1, gp, 2", "amoadd.w a1, a2, (t1)"], note="both fault (store/AMO misaligned)")
lrsc("amo_out_of_bounds", ["li t1, 0x50000", "amoswap.w a1, a2, (t1)"], note="both fault (store/AMO access)")
lrsc("lr_misaligned", ["addi t1, gp, 2", "lr.w a0, (t1)"], note="both fault")
lrsc("lr_out_of_bounds", ["li t1, 0x50000", "lr.w a0, (t1)"], note="both fault")
lrsc("lr_rs2_nonzero_encoding", ["li a0, 0", w32(rtype(0b0001000, 5, 3, 0b010, A0, 0x2F)), "sc.w a1, a2, (gp)"],
     note="LR.W with rs2=x5 (reserved encoding): illegal in both")
lrsc("lr_then_6000_insns_then_sc", ["lr.w a0, (gp)", "li t1, 3000", "1: addi t1, t1, -1", "bnez t1, 1b",
                                    "sc.w a1, a2, (gp)", "lw a3, 0(gp)"],
     expect="spike-reservation-quantum", note="Spike drops reservations every 5000 instructions")


# --------------------------------------------------------------------------- misaligned
def misaligned(name, body, note=""):
    test(name, show=[A0], note=note)(lambda: ["li a2, 0x11223344"] + body)


misaligned("misaligned_lh", ["lh a0, 1(gp)"])
misaligned("misaligned_lhu", ["lhu a0, 3(gp)"])
misaligned("misaligned_lw_1", ["lw a0, 1(gp)"])
misaligned("misaligned_lw_2", ["lw a0, 2(gp)"])
misaligned("misaligned_lw_3", ["lw a0, 3(gp)"])
misaligned("misaligned_sh", ["sh a2, 1(gp)"])
misaligned("misaligned_sw", ["sw a2, 2(gp)"])
misaligned("misaligned_c_lw", ["addi s1, gp, 2", *rvc("c.lw a0, 0(s1)")])
misaligned("misaligned_c_swsp", ["addi sp, gp, 1", *rvc("c.swsp a2, 0(sp)")])
test("misaligned_lw_spike_emulated", expect="spike-misaligned-emulation", show=[A0], spike_args=("--misaligned",),
     note="with spike --misaligned the access is emulated; Determinant always faults")(lambda: ["lw a0, 2(gp)"])


# --------------------------------------------------------------------------- self-modifying code
ADDI_A0_100 = itype(100, A0, 0, A0, 0x13)
ADDI_A0_0x123 = itype(0x123, 0, 0, A0, 0x13)


@test("smc_patch_unexecuted_insn", show=[A0], note="store over a not yet executed insn, no FENCE.I: both see the new insn")
def _():
    return ["la t0, 1f", f"li t1, 0x{ADDI_A0_0x123:x}", "sw t1, 0(t0)", "1: addi a0, x0, 0x111"]


def smc_twice(fence):
    return ["li a0, 0", "la t0, Lsub", f"li t1, 0x{ADDI_A0_100:x}", "jal ra, Lsub", "mv s2, a0",
            "sw t1, 0(t0)", *(["fence.i"] if fence else []), "jal ra, Lsub", "mv s3, a0", "j Ldone",
            "Lsub: addi a0, a0, 1", "ret", "Ldone:"]


test("smc_patch_executed_insn_no_fencei", expect="smc-no-fencei", show=[S2, S3],
     note="patch an already executed insn, no FENCE.I: Spike runs its stale copy")(lambda: smc_twice(False))
test("smc_patch_executed_insn_fencei", show=[S2, S3],
     note="the same with FENCE.I: both see the new insn")(lambda: smc_twice(True))


@test("smc_patch_compressed_fencei", show=[S2, S3], note="patch a 16-bit insn (C.ADDI 1 -> C.ADDI 5) + FENCE.I")
def _():
    return ["li a0, 0", "la t0, Lsub", "li t1, 0x0515", "jal ra, Lsub", "mv s2, a0", "sh t1, 0(t0)",
            "fence.i", "jal ra, Lsub", "mv s3, a0", "j Ldone", "Lsub:", *rvc("c.addi a0, 1"), "ret", "Ldone:"]


# --------------------------------------------------------------------------- x0 destination
@test("x0_destination_all_classes", show=[A3, A4], note="every insn class with rd=x0; side effects (mem, mscratch) kept")
def _():
    return [
        "li a2, 0x5a5a5a5a",
        "add x0, a1, a2", "sub x0, a1, a2", "addi x0, a1, 5", "slli x0, a1, 3", "lui x0, 0x12345",
        "auipc x0, 0x1", "mul x0, a1, a2", "mulhu x0, a1, a2", "div x0, a1, x0", "remu x0, a1, x0",
        "sh1add x0, a1, a2", "clz x0, a1", "cpop x0, a1", "rev8 x0, a1", "rori x0, a1, 3",
        "max x0, a1, a2", "bset x0, a1, a2", "bexti x0, a1, 3",
        "lw x0, 0(gp)", "lbu x0, 1(gp)", "lh x0, 2(gp)",
        "lr.w x0, (gp)", "sc.w x0, a2, (gp)",
        "addi t1, gp, 4", "amoadd.w x0, a2, (t1)", "amoswap.w x0, a1, (gp)",
        "csrrw x0, mscratch, a2", "csrrs x0, mscratch, a1", "csrrci x0, mscratch, 1",
        "csrrs x0, cycle, x0", "csrrsi x0, instret, 0",
        "jal x0, 1f", "1: la t0, 2f", "jalr x0, 0(t0)", "2:",
        h16(0x4015), h16(0x6005), h16(0x802E), h16(0x902E), h16(0x0016), h16(0x0015),
        "add a3, x0, x0", "sltu a4, x0, a1",
    ]


test("x0_load_out_of_bounds_faults", show=[A0], note="LW x0 from an unmapped address still faults")(
    lambda: ["li t1, 0x50000", "lw x0, 0(t1)"])
test("x0_load_misaligned_faults", show=[A0], note="LW x0 misaligned still faults")(lambda: ["lw x0, 2(gp)"])
test("x0_jalr_to_unmapped", show=[A0], note="JALR x0 to an unmapped address: fault at the target fetch")(
    lambda: ["li t1, 0x60000", "jalr x0, 0(t1)"])


# --------------------------------------------------------------------------- CSR
@test("csr_readonly_counter_reads", show=[A1, A2, A3, A4, A5, A6, A7, S2, S3, S4, S5],
      note="CSRRS/CSRRC rs1=x0 and CSRRSI/CSRRCI uimm=0 on cycle/instret/h: no fault; deltas = retired count")
def _():
    return ["csrrs a0, cycle, x0", "csrrc a1, cycle, x0", "csrrsi a2, cycle, 0", "csrrci a3, cycle, 0",
            "csrrs a4, instret, x0", "csrrc a5, instret, x0", "csrrsi a6, instret, 0", "csrrci a7, instret, 0",
            "csrrs s2, cycleh, x0", "csrrs s3, instreth, x0", "csrrsi s4, cycleh, 0", "csrrs x0, cycle, x0",
            "nop", "nop", "csrrs s5, cycle, x0",
            "sub a1, a1, a0", "sub a2, a2, a0", "sub a3, a3, a0", "sub a4, a4, a0", "sub a5, a5, a0",
            "sub a6, a6, a0", "sub a7, a7, a0", "sub s5, s5, a0", "li a0, 0"]


@test("csr_counter_delta_across_loop", show=[A1, A2],
      note="instret/cycle delta across a 100-iteration loop (monotonic, = retired insns)")
def _():
    return ["csrr a0, instret", "li t1, 100", "1: addi t1, t1, -1", "bnez t1, 1b", "csrr a1, instret",
            "csrr a2, cycle", "sub a2, a2, a0", "sub a1, a1, a0", "li a0, 0"]


def csr_fault(name, line, note=""):
    test(name, show=[A0], note=note)(lambda: ["li a0, 0x0a0a0a0a", "li a1, 0", line, "li a3, 0x77"])


csr_fault("csrrw_x0_cycle_faults", "csrrw x0, cycle, a2", "CSRRW rd=x0 on read-only cycle MUST fault")
csr_fault("csrrw_rd_cycle_faults", "csrrw a0, cycle, a2", "CSRRW on cycle faults; rd not written")
csr_fault("csrrs_rs1_nonzero_reg_zero_value_faults", "csrrs a0, cycle, a1",
          "CSRRS rs1!=x0 (value 0) is a write attempt: fault")
csr_fault("csrrc_rs1_nonzero_instret_faults", "csrrc a0, instret, a2")
csr_fault("csrrsi_nonzero_cycle_faults", "csrrsi a0, cycle, 1")
csr_fault("csrrci_nonzero_instreth_faults", "csrrci a0, instreth, 4")
csr_fault("csrrwi_zero_cycle_faults", "csrrwi a0, cycle, 0", "CSRRWI always writes, even uimm=0")
csr_fault("csrrwi_x0_cycleh_faults", "csrrwi x0, cycleh, 0")


@test("mscratch_roundtrip", show=[A1, A2, A4, A5, A6, A7, S2, S3], note="all six CSR ops on mscratch")
def _():
    return ["li a0, 0x12345678", "csrrw a1, mscratch, a0", "csrrs a2, mscratch, x0", "li a3, 0xf0",
            "csrrs a4, mscratch, a3", "csrrc a5, mscratch, a3", "csrrwi a6, mscratch, 31",
            "csrrsi a7, mscratch, 0", "csrrci s2, mscratch, 1", "csrr s3, mscratch",
            "csrrw a0, mscratch, a0"]


for _name in ["mstatus", "misa", "mhartid", "sscratch", "hpmcounter3", "time"]:
    # hpmcounter3 needs Zihpm, which is not in Spike's ISA string: illegal in both
    test(f"csr_unsupported_{_name}", expect="match" if _name == "hpmcounter3" else "unsupported-csr", show=[A0],
         note=f"read of {_name}: Determinant implements only cycle/instret(+h) and mscratch")(
        lambda c=_name: [f"csrr a0, {c}", "li a3, 0x77"])


# --------------------------------------------------------------------------- RVC HINTs / reserved
HINTS = [0x0015, 0x107D, 0x0501, 0x4015, 0x6005, 0x707D, 0x802E, 0x902E, 0x0016, 0x0502, 0x8001,
         0x8481, 0x0002, 0x0001, 0x1001 | (10 << 7)]


@test("rvc_hints_behave_as_expansion", note="C.NOP imm!=0, C.ADDI imm=0, C.LI/C.LUI/C.MV/C.ADD/C.SLLI rd=x0, shamt=0 forms")
def _():
    # 0x1001|rd<<7 is C.ADDI a0, -32 (imm[5]=1, imm[4:0]=0): a normal C.ADDI, kept as a control
    return [h16(h) for h in HINTS] + ["mv a1, a0"]


RESERVED_RVC = {
    "c_addi4spn_zero_x8": 0x0000, "c_addi4spn_zero_x9": 0x0004, "c_lwsp_rd0": 0x4002, "c_jr_rs0": 0x8002,
    "c_addi16sp_zero": 0x6101, "c_lui_x5_zero": 0x6281, "c_lui_x0_zero": 0x6001,
    "c_srli_shamt5": 0x9001, "c_srai_shamt5": 0x9401, "c_slli_shamt5": 0x1082, "c_subw": 0x9C01,
    "c_addw": 0x9C21, "c_q1_reserved_10": 0x9C41, "c_q1_reserved_11": 0x9C61, "c_fld": 0x2000,
    "c_flw": 0x6000, "c_fsd": 0xA000, "c_fsw": 0xE000, "c_fldsp": 0x2002, "c_flwsp": 0x6002,
    "c_fsdsp": 0xA002, "c_fswsp": 0xE002, "c_q0_reserved_100": 0x8000,
}
for _n, _enc in RESERVED_RVC.items():
    test(f"rvc_reserved_{_n}", note=f"0x{_enc:04x} must be illegal in both")(
        lambda e=_enc: [h16(e), "li a3, 0x77"])


# --------------------------------------------------------------------------- reserved 32-bit encodings
RESERVED_32 = {
    "ebreak_rd_nonzero": 0x00100073 | (1 << 7), "ecall_rs1_nonzero": 0x00000073 | (1 << 15),
    "ecall_rd_rs1_nonzero": 0x00000073 | (31 << 7) | (31 << 15), "jalr_funct3_nonzero": 0x00000067 | (1 << 12),
    "slli_shamt5": 0x02001013, "srai_shamt5": 0x4200D013, "rori_shamt5": 0x6200D013, "bseti_shamt5": 0x2A001013,
}
for _n, _enc in RESERVED_32.items():
    test(f"reserved_{_n}", show=[A0], note=f"0x{_enc:08x} must be illegal in both")(
        lambda e=_enc: [w32(e), "li a3, 0x77"])


# --------------------------------------------------------------------------- SYSTEM, FENCE
test("ecall_stops_pc_advanced", note="plain ECALL: both stop; Det pc advanced by 4")(lambda: ["ecall", "li a3, 0x77"])
test("c_ebreak_stops_pc_advanced", note="C.EBREAK: Det pc advanced by 2")(lambda: [*rvc("c.ebreak"), "li a3, 0x77"])
test("fence_variants_are_nops", note="FENCE/FENCE.TSO/PAUSE/FENCE.I with nonzero reserved fields")(
    lambda: ["fence", "fence.tso", w32(0x0100000F), "fence.i", w32(0x0000100F | (5 << 7) | (6 << 15) | (0x123 << 20)),
             w32(0x0FF0000F | (7 << 7) | (9 << 15)), "li a3, 0x77"])


# --------------------------------------------------------------------------- memory / fetch bounds
test("fetch_unmapped_target", show=[A0], note="jump to 0x50000 (one past the end): instruction access fault")(
    lambda: ["li t0, 0x50000", "jr t0"])
test("fetch_32bit_straddling_end", show=[A0], note="32-bit insn whose second half is past the end of memory")(
    lambda: ["li t0, 0x4fffe", "li t1, 0x0013", "sh t1, 0(t0)", "jr t0"])
test("fetch_16bit_at_last_halfword", show=[A0], note="C.EBREAK in the last halfword executes")(
    lambda: ["li t0, 0x4fffe", "li t1, 0x9002", "sh t1, 0(t0)", "jr t0"])
test("fetch_32bit_at_last_word", show=[A0], note="EBREAK in the last word executes")(
    lambda: ["li t0, 0x4fffc", "li t1, 0x00100073", "sw t1, 0(t0)", "jr t0"])
test("access_last_bytes_ok", show=[A0, A1, A2, A4], note="accesses ending exactly at the top of memory")(
    lambda: ["li t0, 0x4fffc", "li a3, 0x8899aabb", "sw a3, 0(t0)", "lw a0, 0(t0)", "lbu a1, 3(t0)",
             "lh a2, 2(t0)", "sb a3, 3(t0)", "sh a3, 2(t0)", "lw a4, 0(t0)"])
for _n, _body in [("lw_past_end", ["li t0, 0x50000", "lw a0, 0(t0)"]),
                  ("lb_past_end", ["li t0, 0x50000", "lb a0, 0(t0)"]),
                  ("sw_past_end", ["li t0, 0x50000", "sw a2, 0(t0)"]),
                  ("sh_past_end", ["li t0, 0x4fffe", "sh a2, 2(t0)"]),
                  ("lw_misaligned_at_end", ["li t0, 0x4fffe", "lw a0, 0(t0)"]),
                  ("lw_top_of_address_space", ["li t0, 0xfffffffc", "lw a0, 0(t0)"]),
                  ("sb_top_of_address_space", ["li t0, 0xffffffff", "sb a2, 0(t0)"])]:
    test(f"oob_{_n}", show=[A0], note="both must fault, state unchanged")(lambda b=_body: b)


# --------------------------------------------------------------------------- runner
def prologue():
    out = [f"li x{i}, 0x{(i * 0x01010101) & MASK32:08x}" for i in range(1, 32)]
    out.append("la gp, data_region")
    return out


def insn_size(binf, addr):
    with open(binf, "rb") as f:
        b = f.read()
    off = addr - LOAD_ADDR
    if 0 <= off < len(b) - 1:
        return 2 if (b[off] & 3) != 3 else 4
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-k", default="", help="run only the tests whose name contains this")
    ap.add_argument("-v", action="store_true", help="print every difference of a divergence")
    pipeline.add_arguments(ap)
    a = ap.parse_args()
    tools, out = pipeline.setup(a, "directed")
    data = [0xC0DE0000 | i for i in range(DATA_SIZE // 4)]
    sel = [t for t in TESTS if a.k in t["name"]]
    built = []
    for t in sel:
        asm = os.path.join(out, t["name"] + ".s")
        with open(asm, "w") as f:
            f.write(assemble_program(prologue() + t["fn"]() + ["ebreak"], data))
        elf, binf, syms = pipeline.build(asm, tools)
        words, note = pipeline.run_spike(elf, tools, extra=t["spike_args"], timeout=60)
        built.append((t, binf, syms, words, note))
    manifest = os.path.join(out, "manifest.txt")
    with open(manifest, "w") as f:
        for t, binf, syms, words, note in built:
            f.write(pipeline.manifest_line(binf, syms) + "\n")
    det = pipeline.run_runner(manifest, tools)

    lines = []
    n_unexpected = 0
    for t, binf, syms, words, note in built:
        rec = det[binf]
        dd = pipeline.compare_configs(rec)
        if words is None:
            lines.append(f"{t['name']}: SPIKE FAILED ({note})")
            n_unexpected += 1
            continue
        sp = pipeline.spike_state(words, syms)
        d = rec["cache"]
        diffs = pipeline.compare(sp, d)
        if d["status"] in ("ebreak", "ecall"):
            size = insn_size(binf, d["epc"])  # None when the insn was written at run time
            adv = (d["final_pc"] - d["epc"]) & MASK32
            if adv not in (2, 4) or (size is not None and adv != size):
                diffs.append(f"det final pc {d['final_pc']:#x} != epc+{size}")
        elif d["final_pc"] != d["epc"]:
            diffs.append(f"det pc moved on fault: epc={d['epc']:#x} final={d['final_pc']:#x}")
        verdict = "MATCH" if not diffs else "DIVERGE"
        ok = (verdict == "MATCH") == (t["expect"] == "match") and not dd
        if not ok:
            n_unexpected += 1
        sp_out = f"mcause={sp['mcause']}({pipeline.CAUSE_NAMES.get(sp['mcause'], '?')}) mepc={sp['mepc']:#x}"
        det_out = f"{d['status']} epc={d['epc']:#x} pc={d['final_pc']:#x}"
        flag = "" if ok else "  <-- UNEXPECTED"
        lines.append(f"{t['name']:44s} {verdict:7s} [{t['expect']}]{flag}")
        lines.append(f"    spike: {sp_out} | det: {det_out}{'' if not dd else ' | ' + '; '.join(dd)}")
        if t["show"]:
            lines.append("    regs (spike/det): " + ", ".join(
                f"x{r}={sp['regs'][r - 1]:#x}" + ("" if sp['regs'][r - 1] == d['regs'][r - 1] else f"/{d['regs'][r - 1]:#x}")
                for r in t["show"]))
        if diffs and (a.v or not ok):
            lines += ["      " + x for x in diffs[:12]]
        elif diffs:
            lines.append("      " + "; ".join(diffs[:4]))
    lines.append(f"\n{len(built)} tests, {n_unexpected} unexpected results")
    report = "\n".join(lines) + "\n"
    sys.stdout.write(report)
    with open(os.path.join(out, "results.txt"), "w") as f:
        f.write(report)
    return 1 if n_unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
