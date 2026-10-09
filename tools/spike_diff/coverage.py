#!/usr/bin/env python3
"""Dynamic coverage of the random generator, measured on Spike's execution log.

  python3 -I tools/spike_diff/coverage.py [--count N] [--start S] [--items K] [--mix MIX ...]
                                          [--work DIR] [tool options]

Reports the executed mnemonics (Spike's disassembly) against every instruction
Determinant implements, branches taken and not taken, rd=x0 executions per mnemonic,
32-bit instructions at 2-mod-4 PCs, and RVC HINT encodings. The programs are built in
WORK/coverage and deleted.
"""
import argparse
import collections
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

import gen  # noqa: E402
import pipeline  # noqa: E402
from template import ISA_SPIKE, SPIKE_MEM  # noqa: E402

LINE = re.compile(r"core\s+0: 0x([0-9a-f]+) \(0x([0-9a-f]+)\) (\S+)\s*(.*)")

# Every mnemonic Determinant implements, as Spike's disassembler prints it.
EXPECTED = """add sub sll slt sltu xor srl sra or and addi slti sltiu xori ori andi slli srli srai
lb lh lw lbu lhu sb sh sw beq bne blt bge bltu bgeu lui auipc jal jalr fence fence.i ecall ebreak
mul mulh mulhsu mulhu div divu rem remu lr.w sc.w amoswap.w amoadd.w amoxor.w amoand.w amoor.w
amomin.w amomax.w amominu.w amomaxu.w csrrw csrrs csrrc csrrwi csrrsi csrrci sh1add sh2add sh3add
andn orn xnor clz ctz cpop max maxu min minu sext.b sext.h zext.h rol ror rori orc.b rev8
bclr bclri bext bexti binv binvi bset bseti
c.addi4spn c.lw c.sw c.addi c.jal c.li c.addi16sp c.lui c.srli c.srai c.andi c.sub c.xor c.or c.and
c.j c.beqz c.bnez c.slli c.lwsp c.jr c.mv c.ebreak c.jalr c.add c.swsp c.nop""".split()

ALIASES = {  # Spike prints pseudo-instructions for some encodings
    "nop": "addi", "mv": "addi", "li": "addi", "not": "xori", "seqz": "sltiu", "snez": "sltu",
    "sltz": "slt", "sgtz": "slt", "neg": "sub", "j": "jal", "jr": "jalr", "ret": "jalr",
    "beqz": "beq", "bnez": "bne", "blez": "bge", "bgez": "bge", "bltz": "blt", "bgtz": "blt",
    "csrr": "csrrs", "csrw": "csrrw", "csrs": "csrrs", "csrc": "csrrc", "csrwi": "csrrwi",
    "csrsi": "csrrsi", "csrci": "csrrci", "rdcycle": "csrrs", "rdinstret": "csrrs",
    "rdcycleh": "csrrs", "rdinstreth": "csrrs", "zext.b": "andi", "fence.tso": "fence",
    "pause": "fence", "frcsr": "csrrs",
}
BRANCHES = {"beq", "bne", "blt", "bge", "bltu", "bgeu", "c.beqz", "c.bnez"}


def classify_hint(raw):
    if raw & 3 == 3:
        return None
    op, f3 = raw & 3, raw >> 13
    rd = (raw >> 7) & 31
    imm6 = ((raw >> 12) & 1) << 5 | (raw >> 2) & 31
    if op == 1 and f3 == 0 and rd == 0 and imm6:
        return "C.NOP nzimm"
    if op == 1 and f3 == 0 and rd and not imm6:
        return "C.ADDI imm=0"
    if op == 1 and f3 == 2 and rd == 0:
        return "C.LI rd=0"
    if op == 1 and f3 == 3 and rd == 0 and imm6:
        return "C.LUI rd=0"
    if op == 2 and f3 == 4 and not (raw >> 12) & 1 and rd == 0 and (raw >> 2) & 31:
        return "C.MV rd=0"
    if op == 2 and f3 == 4 and (raw >> 12) & 1 and rd == 0 and (raw >> 2) & 31:
        return "C.ADD rd=0"
    if op == 2 and f3 == 0 and rd == 0:
        return "C.SLLI rd=0"
    if op == 2 and f3 == 0 and not imm6:
        return "C.SLLI shamt=0"
    if op == 1 and f3 == 4 and (raw >> 10) & 3 in (0, 1) and not imm6:
        return "C.SRLI/SRAI shamt=0"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=30, help="programs per mix (default: %(default)s)")
    ap.add_argument("--start", type=int, default=0, help="first seed (default: %(default)s)")
    ap.add_argument("--mix", action="append", choices=sorted(gen.MIXES), help="repeatable; default: all mixes")
    ap.add_argument("--items", type=int, default=250, help="items per program (default: %(default)s)")
    pipeline.add_arguments(ap)
    a = ap.parse_args()
    tools, out = pipeline.setup(a, "coverage", need_runner=False)
    mixes = a.mix or sorted(gen.MIXES)
    mn = collections.Counter()
    taken = collections.Counter()
    x0dest = collections.Counter()
    hints = collections.Counter()
    misc = collections.Counter()
    for mix in mixes:
        for seed in range(a.start, a.start + a.count):
            asm = os.path.join(out, f"{mix}{seed}.s")
            with open(asm, "w") as f:
                f.write(gen.Gen(seed, mix).program(a.items))
            elf, binf, syms = pipeline.build(asm, tools)
            r = subprocess.run([tools.spike, f"--isa={ISA_SPIKE}", f"-m{SPIKE_MEM}", "-l", elf],
                               capture_output=True, text=True, env=tools.spike_env, timeout=60)
            body = False
            prev = None
            for line in r.stderr.splitlines():
                m = LINE.match(line)
                if not m:
                    continue
                pc, raw, op = int(m.group(1), 16), int(m.group(2), 16), m.group(3)
                if pc == syms["test_start"]:
                    body = True
                if pc >= syms["trap_handler"]:
                    break
                if not body:
                    continue
                if prev is not None:
                    ppc, pop, psize = prev
                    if pop in BRANCHES:
                        taken[(pop, pc != ppc + psize)] += 1
                size = 2 if raw & 3 != 3 else 4
                prev = (pc, op, size)
                canon = ALIASES.get(op, op)
                mn[canon] += 1
                misc["insns"] += 1
                if size == 4 and pc % 4 == 2:
                    misc["32-bit insn at 2-mod-4 pc"] += 1
                if (size == 4 and raw & 0x7F not in (0x63, 0x23) and (raw >> 7) & 31 == 0
                        and canon not in ("fence", "fence.i", "ecall", "ebreak")):
                    x0dest[canon] += 1
                h = classify_hint(raw)
                if h:
                    hints[h] += 1
            pipeline.remove_artifacts(asm)
    missing = [e for e in EXPECTED if mn[e] == 0]
    print(f"programs: {len(mixes) * a.count}, executed instructions: {misc['insns']}")
    print(f"32-bit insns at 2-mod-4 PCs: {misc['32-bit insn at 2-mod-4 pc']}")
    print(f"distinct implemented mnemonics executed: {len(EXPECTED) - len(missing)}/{len(EXPECTED)}; missing: {missing}")
    print("least executed: " + ", ".join(f"{k}={mn[k]}" for k in sorted(EXPECTED, key=lambda k: mn[k])[:15]))
    other = {k: v for k, v in mn.items() if k not in EXPECTED}
    if other:
        print(f"other mnemonics (the fault terminators, or aliases not mapped): {other}")
    print("branches (taken/not): " + ", ".join(f"{b}={taken[(b, True)]}/{taken[(b, False)]}" for b in sorted(BRANCHES)))
    print(f"32-bit insns with rd=x0 by mnemonic ({sum(x0dest.values())} total): "
          + ", ".join(f"{k}={v}" for k, v in x0dest.most_common()))
    print("RVC HINT encodings executed: " + ", ".join(f"{k}={v}" for k, v in sorted(hints.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
