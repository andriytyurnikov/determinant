#!/usr/bin/env python3
"""Seeded random program generator: RV32I M A C Zicsr Zifencei Zba Zbb Zbs.

Every program is a pure function of (seed, mix). These rules keep Spike and Determinant
comparable; what lies outside them is covered by directed.py and encsweep.py:
  * all 31 registers and mscratch get random values in the prologue (Spike's boot ROM
    leaves a1 and t0 non-zero, Determinant starts with every register zero)
  * one register (BASE) per program is never written; it points at the middle of the
    2 KiB data region. Every memory access is BASE + (reg & mask) + imm, so it is always
    in bounds and naturally aligned (random, data-dependent addresses)
  * control flow is forward-only, except bounded counted loops (reserved counter)
  * every LR.W is followed, in the same straight-line item, by an SC.W with no store or
    AMO in between (Determinant drops a reservation on a store by the same hart to the
    reserved word, Spike does not; both are allowed)
  * counters (cycle/instret) are only observed as deltas between two reads (Spike's
    also count its boot ROM and the preamble)
  * the program ends in ebreak / c.ebreak / ecall, or in a fault both raise

usage: gen.py --seed N [--mix MIX] [--items K] [-o OUT.s]
"""
import argparse
import os
import random
import sys

if __name__ == "__main__":
    sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

from template import DATA_SIZE, assemble_program  # noqa: E402

M32 = 0xFFFFFFFF
SPECIAL = [0, 1, 2, 3, 0xFFFFFFFF, 0xFFFFFFFE, 0x80000000, 0x7FFFFFFF, 0x80000001,
           31, 32, 33, 63, 64, 0x7F, 0x80, 0xFF, 0x100, 0x7FFF, 0x8000, 0xFFFF,
           0x10000, 0xFFFF8000, 0xFFFFFF80, 0xFFFF0000, 0x00FF00FF, 0xFF00FF00,
           0x01010101, 0x80808080, 0x7F7F7F7F, 0xAAAAAAAA, 0x55555555, 0x00000800,
           0xFFFFF800, 0x000007FF]
IMM_SPECIAL = [0, 1, -1, 2047, -2048, 2, -2, 31, 32, 0x7FF, -0x800, 0x400, -0x400]

ALU_R = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
ALU_I = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_I = ["slli", "srli", "srai"]
M_OPS = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]
ZBA = ["sh1add", "sh2add", "sh3add"]
ZBB_R = ["andn", "orn", "xnor", "max", "maxu", "min", "minu", "rol", "ror"]
ZBB_U = ["clz", "ctz", "cpop", "sext.b", "sext.h", "zext.h", "orc.b", "rev8"]
ZBS_R = ["bclr", "bext", "binv", "bset"]
ZBS_I = ["bclri", "bexti", "binvi", "bseti"]
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
AMOS = ["amoswap", "amoadd", "amoxor", "amoand", "amoor", "amomin", "amomax", "amominu", "amomaxu"]
LOADS = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]
COUNTERS = ["cycle", "instret"]
COUNTERS_H = ["cycleh", "instreth"]

# Reserved or unimplemented 32-bit encodings, illegal on both: custom-0, MISC-MEM funct3=2,
# JALR funct3=1, BRANCH funct3=2, LD, LWU, SD, AMO.D, OP-32, SRLI/SLLI with shamt[5]=1,
# OP funct7=0000101 funct3=0, LR.W with rs2!=0, ECALL with rd!=0, EBREAK with rs1!=0.
RESERVED_32 = [0x0000000B, 0x0000200F, 0x00001067, 0x00002063, 0x00003003, 0x00006003,
               0x00003023, 0x0000302F, 0x0000003B, 0x0200D013, 0x02001013, 0x0A000033,
               0x1051A52F, 0x000000F3, 0x00108073]
# Reserved RVC encodings: the all-zero halfword, C.LWSP rd=0, C.JR rs1=0, C.ADDI16SP 0,
# C.SUBW, C.FLW, quadrant 0 funct3=100, C.SLLI shamt[5]=1.
RESERVED_16 = [0x0000, 0x4002, 0x8002, 0x6101, 0x9C01, 0x6000, 0x8000, 0x1082]

# category -> weight, per mix
CATS = ["alu_r", "alu_i", "lui_auipc", "m", "zba", "zbb", "zbs", "li_special", "c_alu",
        "c_hint", "load", "store", "c_mem", "amo", "lrsc", "sc_only", "branch",
        "c_branch", "jal", "c_jump", "jalr", "c_jr", "loop", "csr_scratch",
        "csr_counter", "fence"]
MIXES = {
    "mixed": {c: 1.0 for c in CATS},
    "alu": dict(alu_r=4, alu_i=4, lui_auipc=1, m=4, zba=2, zbb=4, zbs=3, li_special=3,
                c_alu=1, branch=0.5, load=0.5, store=0.5),
    "mem": dict(load=5, store=5, c_mem=4, amo=1, alu_r=1, alu_i=1, m=0.5, li_special=1,
                branch=0.5, loop=0.5, lrsc=0.5),
    "comp": dict(c_alu=6, c_hint=2, c_mem=3, c_branch=2, c_jump=2, c_jr=1, alu_r=1, alu_i=1,
                 li_special=1, loop=0.5),
    "amo": dict(amo=5, lrsc=4, sc_only=1, load=1, store=1, alu_r=1, alu_i=1, li_special=1),
    "branch": dict(branch=4, c_branch=2, jal=2, c_jump=2, jalr=2, c_jr=2, loop=2,
                   alu_r=1, alu_i=1, li_special=1, m=0.5, load=0.5, store=0.5),
    "csr": dict(csr_scratch=4, csr_counter=3, alu_r=1, alu_i=1, li_special=1, fence=1,
                branch=0.5),
}


def s12(v):
    v &= 0xFFF
    return v - 0x1000 if v & 0x800 else v


class Item:
    """A straight-line chunk of assembly. `branch` items end in a forward jump or branch
    whose label is written as {L}; `maxdist` bounds the byte distance to the label."""
    __slots__ = ("lines", "size", "branch", "maxdist")

    def __init__(self, lines, size, branch=False, maxdist=0):
        self.lines, self.size, self.branch, self.maxdist = lines, size, branch, maxdist


def rvc(line):
    return [".option rvc", line, ".option norvc"]


class Gen:
    def __init__(self, seed, mix):
        self.rng = random.Random(f"{mix}:{seed}")
        self.weights = MIXES[mix]
        self.base = self.rng.randrange(3, 32)
        self.reserved = {self.base}
        self.noread = set()  # registers holding absolute counter values (Spike != Det)
        self.nlabel = 0
        self.in_loop = False

    # --- random helpers -------------------------------------------------------
    def chance(self, p):
        return self.rng.random() < p

    def val(self):
        p = self.rng.random()
        if p < 0.25:
            return self.rng.choice(SPECIAL)
        if p < 0.35:
            return self.rng.randint(-64, 64) & M32
        if p < 0.45:
            b = 1 << self.rng.randrange(32)
            return self.rng.choice([b, (-b) & M32, b - 1, (~b) & M32])
        return self.rng.getrandbits(32)

    def imm12(self):
        if self.chance(0.3):
            return self.rng.choice(IMM_SPECIAL)
        return self.rng.randint(-2048, 2047)

    def label(self):
        self.nlabel += 1
        return f"L{self.nlabel}"

    def wreg(self, x0_prob=0.06):
        """Destination register: never reserved; sometimes x0."""
        if self.chance(x0_prob):
            return 0
        return self.rng.choice([r for r in range(1, 32) if r not in self.reserved])

    def tmp(self, choices=range(1, 32)):
        """Non-zero, non-reserved register used for address temporaries."""
        return self.rng.choice([r for r in choices if r != 0 and r not in self.reserved])

    def rreg(self):
        if self.chance(0.05):
            return 0
        return self.rng.choice([r for r in range(1, 32) if r not in self.noread])

    def rpair(self):
        """Two source registers, the same one in 10% of cases: equal operands are an edge
        case of every two-operand instruction (SLT/SLTU, MIN/MAX, SUB, ...)."""
        a = self.rreg()
        return a, (a if self.chance(0.1) else self.rreg())

    def cw(self):
        return self.tmp(range(8, 16))

    def cr(self):
        return self.rng.choice([r for r in range(8, 16) if r not in self.noread])

    def li(self, rd, v):
        v &= M32
        lo = s12(v)
        hi = ((v - lo) >> 12) & 0xFFFFF
        return [f"lui x{rd}, 0x{hi:x}", f"addi x{rd}, x{rd}, {lo}"]

    # --- one non-control, non-memory instruction (loop bodies, LR/SC windows) --
    def alu_one(self):
        cat = self.rng.choice(["alu_r", "alu_i", "m", "zba", "zbb", "zbs", "lui_auipc"])
        return getattr(self, "g_" + cat)()

    # --- categories: each returns an Item ------------------------------------
    def g_alu_r(self):
        op = self.rng.choice(ALU_R)
        a, b = self.rpair()
        return Item([f"{op} x{self.wreg()}, x{a}, x{b}"], 4)

    def g_alu_i(self):
        if self.chance(0.35):
            op = self.rng.choice(SHIFT_I)
            sh = self.rng.choice([0, 1, 31, self.rng.randrange(32)])
            return Item([f"{op} x{self.wreg()}, x{self.rreg()}, {sh}"], 4)
        op = self.rng.choice(ALU_I)
        return Item([f"{op} x{self.wreg()}, x{self.rreg()}, {self.imm12()}"], 4)

    def g_lui_auipc(self):
        op = self.rng.choice(["lui", "auipc"])
        imm = self.rng.choice([0, 1, 0xFFFFF, 0x80000, 0x7FFFF, self.rng.getrandbits(20)])
        return Item([f"{op} x{self.wreg()}, 0x{imm:x}"], 4)

    def g_m(self):
        op = self.rng.choice(M_OPS)
        a, b = self.rpair()
        return Item([f"{op} x{self.wreg()}, x{a}, x{b}"], 4)

    def g_zba(self):
        op = self.rng.choice(ZBA)
        a, b = self.rpair()
        return Item([f"{op} x{self.wreg()}, x{a}, x{b}"], 4)

    def g_zbb(self):
        p = self.rng.random()
        if p < 0.45:
            op = self.rng.choice(ZBB_R)
            a, b = self.rpair()
            return Item([f"{op} x{self.wreg()}, x{a}, x{b}"], 4)
        if p < 0.85:
            op = self.rng.choice(ZBB_U)
            return Item([f"{op} x{self.wreg()}, x{self.rreg()}"], 4)
        sh = self.rng.choice([0, 1, 31, self.rng.randrange(32)])
        return Item([f"rori x{self.wreg()}, x{self.rreg()}, {sh}"], 4)

    def g_zbs(self):
        if self.chance(0.5):
            op = self.rng.choice(ZBS_R)
            a, b = self.rpair()
            return Item([f"{op} x{self.wreg()}, x{a}, x{b}"], 4)
        op = self.rng.choice(ZBS_I)
        sh = self.rng.choice([0, 31, self.rng.randrange(32)])
        return Item([f"{op} x{self.wreg()}, x{self.rreg()}, {sh}"], 4)

    def g_li_special(self):
        return Item(self.li(self.wreg(0.02), self.val()), 8)

    def g_c_alu(self):
        k = self.rng.randrange(16)
        if k == 0:
            rd = self.wreg(0)
            imm = self.rng.choice([i for i in range(-32, 32) if i != 0])
            return Item(rvc(f"c.addi x{rd}, {imm}"), 2)
        if k == 1:
            return Item(rvc(f"c.li x{self.wreg(0)}, {self.rng.randint(-32, 31)}"), 2)
        if k == 2:
            rd = self.tmp([r for r in range(1, 32) if r != 2])
            imm = self.rng.choice([i for i in range(-32, 32) if i != 0]) & 0xFFFFF
            return Item(rvc(f"c.lui x{rd}, 0x{imm:x}"), 2)
        if k == 3 and 2 not in self.reserved:
            imm = 16 * self.rng.choice([i for i in range(-32, 32) if i != 0])
            return Item(rvc(f"c.addi16sp sp, {imm}"), 2)
        if k == 4:
            return Item(rvc(f"c.addi4spn x{self.cw()}, sp, {4 * self.rng.randint(1, 255)}"), 2)
        if k in (5, 6):
            op = "c.srli" if k == 5 else "c.srai"
            return Item(rvc(f"{op} x{self.cw()}, {self.rng.randint(1, 31)}"), 2)
        if k == 7:
            return Item(rvc(f"c.andi x{self.cw()}, {self.rng.randint(-32, 31)}"), 2)
        if k in (8, 9, 10, 11):
            op = ["c.sub", "c.xor", "c.or", "c.and"][k - 8]
            return Item(rvc(f"{op} x{self.cw()}, x{self.cr()}"), 2)
        if k == 12:
            return Item(rvc(f"c.slli x{self.wreg(0)}, {self.rng.randint(1, 31)}"), 2)
        if k == 13:
            return Item(rvc(f"c.mv x{self.wreg(0)}, x{self.rng.randrange(1, 32)}"), 2)
        if k == 14:
            return Item(rvc(f"c.add x{self.wreg(0)}, x{self.rng.randrange(1, 32)}"), 2)
        return Item(rvc("c.nop"), 2)

    def g_c_hint(self):
        """RVC HINT encodings (rd=x0 / imm=0 / shamt=0 forms), emitted raw since the
        assembler rejects most of them. Each must behave exactly like its expansion."""
        k = self.rng.randrange(10)
        imm6 = self.rng.randrange(64)
        if k == 0:  # C.NOP with nzimm
            imm6 = imm6 or 1
            enc = ((imm6 >> 5) & 1) << 12 | (imm6 & 31) << 2 | 0b01
        elif k == 1:  # C.ADDI rd!=0, imm=0
            enc = self.wreg(0) << 7 | 0b01
        elif k == 2:  # C.LI rd=0
            enc = 0b010 << 13 | ((imm6 >> 5) & 1) << 12 | (imm6 & 31) << 2 | 0b01
        elif k == 3:  # C.LUI rd=0, nzimm!=0
            imm6 = imm6 or 1
            enc = 0b011 << 13 | ((imm6 >> 5) & 1) << 12 | (imm6 & 31) << 2 | 0b01
        elif k == 4:  # C.MV rd=0
            enc = 0b1000 << 12 | self.rng.randrange(1, 32) << 2 | 0b10
        elif k == 5:  # C.ADD rd=0
            enc = 0b1001 << 12 | self.rng.randrange(1, 32) << 2 | 0b10
        elif k == 6:  # C.SLLI rd=0
            enc = self.rng.randrange(32) << 2 | 0b10
        elif k == 7:  # C.SLLI rd!=0, shamt=0
            enc = self.wreg(0) << 7 | 0b10
        elif k == 8:  # C.SRLI shamt=0
            enc = 0b100 << 13 | 0b00 << 10 | (self.cw() - 8) << 7 | 0b01
        else:  # C.SRAI shamt=0
            enc = 0b100 << 13 | 0b01 << 10 | (self.cw() - 8) << 7 | 0b01
        return Item([f".2byte 0x{enc:04x}"], 2)

    def addr(self, t, mask):
        """t = BASE + (random_reg & mask): aligned, in [BASE, BASE + mask]."""
        return [f"andi x{t}, x{self.rreg()}, {mask}", f"add x{t}, x{t}, x{self.base}"]

    def mem_addr(self, t, w):
        """(lines, imm, size): x{t} + imm is w-aligned and inside the data region.
        Either imm in [-1024, 0], or t biased by -2048 and imm in [1024, 2047]."""
        lines = self.addr(t, 0x400 - w)
        if self.chance(0.3):
            return lines + [f"addi x{t}, x{t}, -2048"], w * self.rng.randint(1024 // w, 2047 // w), 12
        return lines, -w * self.rng.randint(0, 1024 // w), 8

    def g_load(self):
        op, w = self.rng.choice(LOADS)
        t = self.tmp()
        lines, imm, size = self.mem_addr(t, w)
        return Item(lines + [f"{op} x{self.wreg()}, {imm}(x{t})"], size + 4)

    def g_store(self):
        op, w = self.rng.choice(STORES)
        t = self.tmp()
        lines, imm, size = self.mem_addr(t, w)
        return Item(lines + [f"{op} x{self.rreg()}, {imm}(x{t})"], size + 4)

    def g_c_mem(self):
        k = self.rng.randrange(4)
        if k < 2:
            t = self.cw()
            off = 4 * self.rng.randrange(32)
            if k == 0:
                return Item(self.addr(t, 0x37C) + rvc(f"c.lw x{self.cw()}, {off}(x{t})"), 10)
            return Item(self.addr(t, 0x37C) + rvc(f"c.sw x{self.cr()}, {off}(x{t})"), 10)
        if 2 in self.reserved:
            return self.g_load()
        off = 4 * self.rng.randrange(64)
        if k == 2:
            return Item(self.addr(2, 0x2FC) + rvc(f"c.lwsp x{self.wreg(0)}, {off}(sp)"), 10)
        return Item(self.addr(2, 0x2FC) + rvc(f"c.swsp x{self.rreg()}, {off}(sp)"), 10)

    def aqrl(self):
        return self.rng.choice(["", "", ".aq", ".rl", ".aqrl"])

    def g_amo(self):
        op = self.rng.choice(AMOS)
        t = self.tmp()
        return Item(self.addr(t, 0x3FC) + [f"{op}.w{self.aqrl()} x{self.wreg()}, x{self.rreg()}, (x{t})"], 12)

    def g_lrsc(self):
        t = self.tmp()
        lines = self.addr(t, 0x3FC)
        size = 8
        self.reserved.add(t)
        lines.append(f"lr.w{self.aqrl()} x{self.wreg()}, (x{t})")
        size += 4
        for _ in range(self.rng.randrange(4)):
            it = self.g_load() if self.chance(0.25) else self.alu_one()  # loads keep the reservation
            lines += it.lines
            size += it.size
        sc_reg = t
        if self.chance(0.25):  # SC to a (usually) different address
            sc_reg = self.tmp()
            lines += self.addr(sc_reg, 0x3FC)
            size += 8
            self.reserved.add(sc_reg)
        # A second SC (reservation already consumed: must fail) needs the address
        # register to survive the first SC's rd write, so keep it reserved until then.
        second = self.chance(0.2)
        if not second:
            self.reserved -= {t, sc_reg}
        lines.append(f"sc.w{self.aqrl()} x{self.wreg()}, x{self.rreg()}, (x{sc_reg})")
        size += 4
        if second:
            self.reserved -= {t, sc_reg}
            lines.append(f"sc.w x{self.wreg()}, x{self.rreg()}, (x{sc_reg})")
            size += 4
        return Item(lines, size)

    def g_sc_only(self):
        t = self.tmp()
        return Item(self.addr(t, 0x3FC) + [f"sc.w x{self.wreg()}, x{self.rreg()}, (x{t})"], 12)

    def g_branch(self):
        op = self.rng.choice(BRANCHES)
        a = self.rreg()
        b = a if self.chance(0.15) else self.rreg()
        return Item([f"{op} x{a}, x{b}, {{L}}"], 4, True, 3500)

    def g_c_branch(self):
        op = self.rng.choice(["c.beqz", "c.bnez"])
        return Item(rvc(f"{op} x{self.cr()}, {{L}}"), 2, True, 230)

    def g_jal(self):
        return Item([f"jal x{self.wreg(0.3)}, {{L}}"], 4, True, 100000)

    def g_c_jump(self):
        if 1 in self.reserved or self.chance(0.5):
            return Item(rvc("c.j {L}"), 2, True, 1800)
        return Item(rvc("c.jal {L}"), 2, True, 1800)

    def g_jalr(self):
        t = self.tmp()
        imm = self.rng.choice([0, 0, 4, -4, 2, -2, self.imm12() & ~1])
        odd = self.rng.choice([0, 0, 1])  # JALR must clear bit 0 of the target
        lines = [f"la x{t}, {{L}}-({imm})+{odd}", f"jalr x{self.wreg(0.25)}, {imm}(x{t})"]
        return Item(lines, 12, True, 100000)

    def g_c_jr(self):
        t = self.tmp()
        if 1 in self.reserved or self.chance(0.5):
            return Item([f"la x{t}, {{L}}"] + rvc(f"c.jr x{t}"), 10, True, 100000)
        return Item([f"la x{t}, {{L}}"] + rvc(f"c.jalr x{t}"), 10, True, 100000)

    def g_loop(self):
        if self.in_loop:
            return self.alu_one()
        c = self.tmp(range(3, 32))
        n = self.rng.randint(1, 6)
        self.reserved.add(c)
        self.in_loop = True
        body = self.block(self.rng.randint(1, 10))
        self.in_loop = False
        self.reserved.discard(c)
        top, cont = self.label(), self.label()
        lines = self.li(c, n) + [f"{top}:"] + resolve(self, body, end_label=cont)
        lines += [f"{cont}:", f"addi x{c}, x{c}, -1"]
        body_size = sum(i.size for i in body) + 4
        if 8 <= c <= 15 and body_size < 200 and self.chance(0.5):
            lines += rvc(f"c.bnez x{c}, {top}")
            size = 8 + body_size + 2
        else:
            lines.append(self.rng.choice([f"bnez x{c}, {top}", f"blt x0, x{c}, {top}",
                                          f"bne x{c}, x0, {top}", f"bltu x0, x{c}, {top}"]))
            size = 8 + body_size + 4
        return Item(lines, size)

    def g_csr_scratch(self):
        op = self.rng.choice(["csrrw", "csrrs", "csrrc", "csrrwi", "csrrsi", "csrrci"])
        src = f"{self.rng.randrange(32)}" if op.endswith("i") else f"x{self.rreg()}"
        return Item([f"{op} x{self.wreg(0.2)}, mscratch, {src}"], 4)

    def g_csr_counter(self):
        if self.chance(0.2):  # the high halves are 0 on both
            return Item([f"csrr x{self.wreg()}, {self.rng.choice(COUNTERS_H)}"], 4)
        ctr = self.rng.choice(COUNTERS)
        a = self.tmp()
        self.reserved.add(a)
        self.noread.add(a)  # the absolute count may only reach the delta computation
        b = self.tmp()
        reads = [f"csrrs x{{}}, {ctr}, x0", f"csrrc x{{}}, {ctr}, x0",
                 f"csrrsi x{{}}, {ctr}, 0", f"csrrci x{{}}, {ctr}, 0"]
        lines = [self.rng.choice(reads).format(a)]
        size = 4
        for _ in range(self.rng.randrange(4)):
            it = self.alu_one()
            lines += it.lines
            size += it.size
        self.reserved.discard(a)
        self.noread.discard(a)
        lines += [self.rng.choice(reads).format(b), f"sub x{b}, x{b}, x{a}", f"addi x{a}, x{b}, 0"]
        return Item(lines, size + 12)

    def g_fence(self):
        return Item([self.rng.choice(["fence", "fence rw, rw", "fence.tso", "fence i, o",
                                      "fence.i", ".4byte 0x0100000f", "fence r, w"])], 4)

    def terminator(self):
        """End of program: ebreak/ecall (70%) or a fault under random state (30%), of a
        kind that Spike and Determinant both raise."""
        if self.chance(0.7):
            return self.rng.choice([["ebreak"], ["ebreak"], ["ebreak"], ["ecall"],
                                    [".option rvc", "c.ebreak", ".option norvc"]])
        b, t, rd, rs = self.base, self.tmp(), self.wreg(), self.rreg()
        k = self.rng.randrange(12)
        if k == 0:  # misaligned load
            op, w = self.rng.choice([("lw", 4), ("lh", 2), ("lhu", 2)])
            off = w * self.rng.randint(-100, 100) + self.rng.randrange(1, w)
            return [f"{op} x{rd}, {off}(x{b})"]
        if k == 1:  # misaligned store
            op, w = self.rng.choice([("sw", 4), ("sh", 2)])
            off = w * self.rng.randint(-100, 100) + self.rng.randrange(1, w)
            return [f"{op} x{rs}, {off}(x{b})"]
        if k == 2:  # misaligned AMO / LR / SC (SC faults with or without a reservation)
            insn = self.rng.choice([f"amoadd.w x{rd}, x{rs}, (x{t})", f"amoswap.w x{rd}, x{rs}, (x{t})",
                                    f"lr.w x{rd}, (x{t})", f"sc.w x{rd}, x{rs}, (x{t})"])
            return [f"addi x{t}, x{b}, {self.rng.choice([1, 2, 3, -1, -2, 6])}", insn]
        hi = self.rng.choice([0x50, 0x51, 0x60, 0x80000, 0xFFFFF, self.rng.randint(0x50, 0xFFFFF)])
        if k == 3:  # unmapped load (any width, any alignment => fault)
            op = self.rng.choice(["lb", "lbu", "lh", "lhu", "lw"])
            return [f"lui x{t}, 0x{hi:x}", f"{op} x{rd}, {self.rng.choice([0, 4, 8, 2047])}(x{t})"]
        if k == 4:  # unmapped store
            op = self.rng.choice(["sb", "sh", "sw"])
            return [f"lui x{t}, 0x{hi:x}", f"{op} x{rs}, {self.rng.choice([0, 4, 8])}(x{t})"]
        if k == 5:  # unmapped AMO / LR / SC
            insn = self.rng.choice([f"amoor.w x{rd}, x{rs}, (x{t})", f"lr.w x{rd}, (x{t})",
                                    f"sc.w x{rd}, x{rs}, (x{t})"])
            return [f"lui x{t}, 0x{hi:x}", insn]
        if k == 6:  # jump to unmapped memory (JALR retires, the fetch at the target faults)
            return [f"lui x{t}, 0x{hi:x}", f"jalr x{rd}, {self.rng.choice([0, 2, 4])}(x{t})"]
        if k == 7:  # write attempt to a read-only counter
            return [self.rng.choice([f"csrrw x{rd}, cycle, x{rs}", "csrrwi x0, instret, 0",
                                     f"csrrsi x{rd}, cycleh, 1", f"csrrc x{rd}, instreth, x{max(rs, 1)}"])]
        if k == 8:  # CSR that neither implements (custom, hpm counters without Zihpm)
            return [self.rng.choice([f"csrrs x{rd}, 0x7c0, x0", f"csrr x{rd}, hpmcounter3", f"csrr x{rd}, 0x8ff"])]
        if k == 9:  # reserved or unimplemented 32-bit encoding
            return [f".4byte 0x{self.rng.choice(RESERVED_32):08x}"]
        if k == 10:  # reserved RVC encoding
            return [f".2byte 0x{self.rng.choice(RESERVED_16):04x}"]
        return ["ecall"]

    # --- blocks -----------------------------------------------------------------
    def block(self, n):
        cats = [c for c in CATS if self.weights.get(c, 0) > 0]
        w = [self.weights[c] for c in cats]
        return [getattr(self, "g_" + self.rng.choices(cats, w)[0])() for _ in range(n)]

    def program(self, n_items):
        body = ["# prologue: randomize all registers and mscratch"]
        for r in range(1, 32):
            body += self.li(r, self.val())
        body.append(f"csrw mscratch, x{self.rng.randrange(1, 32)}")
        body += self.li(self.base, 0)  # overwritten below; keeps the layout uniform
        body.append(f"la x{self.base}, data_region+1024")
        items = self.block(n_items)
        body += resolve(self, items, end_label=None)
        body += self.terminator()
        data = [self.val() for _ in range(DATA_SIZE // 4)]
        return assemble_program(body, data)


def resolve(gen, items, end_label):
    """Place forward-branch labels. A target is an item boundary 1..8 items ahead within
    byte range; index len(items) is the block end (end_label or a fresh label)."""
    labels = {}
    targets = {}
    for i, it in enumerate(items):
        if not it.branch:
            continue
        cands = []
        dist = it.size
        for t in range(i + 1, min(len(items), i + 8) + 1):
            if dist > it.maxdist:
                break
            cands.append(t)
            if t < len(items):
                dist += items[t].size
        t = gen.rng.choice(cands)
        if t not in labels:
            labels[t] = end_label if (t == len(items) and end_label) else gen.label()
        targets[i] = labels[t]
    out = []
    for i, it in enumerate(items):
        if i in labels:
            out.append(f"{labels[i]}:")
        for line in it.lines:
            out.append(line.replace("{L}", targets[i]) if i in targets else line)
    if len(items) in labels and labels[len(items)] != end_label:
        out.append(f"{labels[len(items)]}:")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--mix", default="mixed", choices=sorted(MIXES))
    ap.add_argument("--items", type=int, default=150)
    ap.add_argument("-o", "--out", help="output file (default: stdout)")
    a = ap.parse_args()
    src = Gen(a.seed, a.mix).program(a.items)
    if a.out:
        with open(a.out, "w") as f:
            f.write(src)
    else:
        sys.stdout.write(src)


if __name__ == "__main__":
    main()
