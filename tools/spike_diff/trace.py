#!/usr/bin/env python3
"""Localize a divergence: align Spike's commit log with the runner's step trace.

  python3 -I tools/spike_diff/trace.py PROGRAM.elf [--context N] [--work DIR] [tool options]

PROGRAM.elf is a program the other scripts kept (its PROGRAM.bin must be next to it).
Prints the first step at which the pc, a register write or mscratch differs, with the
N steps before it.
"""
import argparse
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

import pipeline  # noqa: E402
from template import ISA_SPIKE, LOAD_ADDR, SPIKE_MEM  # noqa: E402

COMMIT = re.compile(r"core\s+0: 3 0x([0-9a-f]+) \(0x([0-9a-f]+)\)(.*)")
DISASM = re.compile(r"core\s+0: 0x([0-9a-f]+) \(0x([0-9a-f]+)\) (.*)")


def spike_trace(elf, tools, start, stop):
    r = subprocess.run([tools.spike, f"--isa={ISA_SPIKE}", f"-m{SPIKE_MEM}", "-l", "--log-commits", elf],
                       capture_output=True, text=True, env=tools.spike_env, timeout=60)
    steps, dis, on = [], {}, False
    for line in r.stderr.splitlines():
        m = DISASM.match(line)
        if m:
            dis[int(m.group(1), 16)] = m.group(3).strip()
            continue
        if "exception" in line and on:
            steps.append(("trap", line.strip()))
            break
        m = COMMIT.match(line)
        if not m:
            continue
        pc = int(m.group(1), 16)
        if pc == start:
            on = True
        if not on:
            continue
        if pc == stop:
            break
        toks = m.group(3).split()
        regs, csrs, mem = {}, {}, []
        i = 0
        while i < len(toks):
            t = toks[i]
            if re.fullmatch(r"x\d+", t):
                regs[int(t[1:])] = int(toks[i + 1], 16)
                i += 2
            elif t == "mem":
                if i + 2 < len(toks) and toks[i + 2].startswith("0x") and not re.fullmatch(r"x\d+", toks[i + 2]):
                    mem.append((int(toks[i + 1], 16), int(toks[i + 2], 16)))
                    i += 3
                else:
                    i += 2
            elif re.fullmatch(r"c[0-9a-f]+_\w+", t):
                csrs[t.split("_", 1)[1]] = int(toks[i + 1], 16)
                i += 2
            else:
                i += 1
        steps.append((pc, int(m.group(2), 16), regs, csrs, mem))
    return steps, dis


def det_trace(binf, tools, entry):
    r = subprocess.run([tools.runner, "--trace", binf, f"{LOAD_ADDR:x}", f"{entry:x}", str(pipeline.MAX_STEPS)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        pipeline.fail(f"spike-runner --trace failed: {r.stderr[-2000:]}")
    steps = []
    for line in r.stdout.splitlines():
        p = line.split()
        if p[0] == "end":
            steps.append(("end", p[1], int(p[2], 16)))
            break
        regs, csrs, mem = {}, {}, []
        for t in p[2:]:
            k, v = t.split("=")
            if k.startswith("x"):
                regs[int(k[1:])] = int(v, 16)
            elif k == "mscratch":
                csrs["mscratch"] = int(v, 16)
            elif k.startswith("mem["):
                mem.append((int(k[4:-1], 16), int(v, 16)))
            elif k == "resv":
                csrs["resv"] = v
        steps.append((int(p[0], 16), int(p[1], 16), regs, csrs, mem))
    return steps


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("elf")
    ap.add_argument("--context", type=int, default=6, help="steps to show before the divergence (default: %(default)s)")
    pipeline.add_arguments(ap)
    a = ap.parse_args()
    tools, _ = pipeline.setup(a)
    elf = os.path.abspath(a.elf)
    binf = elf[:-4] + ".bin"
    syms = pipeline.symbols(elf, tools)
    sp, dis = spike_trace(elf, tools, syms["test_start"], syms["trap_handler"])
    dt = det_trace(binf, tools, syms["test_start"])
    dregs = [None] * 32
    ctr_off = None  # Spike's counters run ahead by a constant (boot ROM + preamble)
    for n, (s, d) in enumerate(zip(sp, dt)):
        if s[0] == "trap" or d[0] == "end":
            print(f"step {n}: spike={s if s[0] == 'trap' else hex(s[0])} det={d}")
            break
        for r, v in d[2].items():
            dregs[r] = v
        problems = []
        if s[0] != d[0]:
            problems.append(f"pc spike={s[0]:#x} det={d[0]:#x}")
        is_ctr = re.search(r"\b(cycle|instret)\b", dis.get(s[0], ""))
        for r, v in s[2].items():
            if r and dregs[r] is not None and dregs[r] != v:
                if is_ctr:
                    off = (v - dregs[r]) & 0xFFFFFFFF
                    ctr_off = off if ctr_off is None else ctr_off
                    if off == ctr_off:
                        continue
                problems.append(f"x{r} spike={v:#010x} det={dregs[r]:#010x}")
        if "mscratch" in s[3] and "mscratch" in d[3] and s[3]["mscratch"] != d[3]["mscratch"]:
            problems.append(f"mscratch spike={s[3]['mscratch']:#x} det={d[3]['mscratch']:#x}")
        if problems:
            print(f"FIRST DIVERGENCE at step {n}: {'; '.join(problems)}")
            for k in range(max(0, n - a.context), n + 1):
                s2, d2 = sp[k], dt[k]
                sregs = {f"x{x}": hex(v) for x, v in s2[2].items()}
                print(f"  [{k}] {s2[0]:#x} {s2[1]:#010x} {dis.get(s2[0], ''):34s} spike regs={sregs} "
                      f"csr={ {c: hex(v) for c, v in s2[3].items()} } mem={[(hex(x), hex(v)) for x, v in s2[4]]}")
                dregs2 = {f"x{x}": hex(v) for x, v in d2[2].items()}
                print(f"  {'':>{len(str(k)) + 2}} det: pc={d2[0]:#x} regs={dregs2} csr={d2[3]} "
                      f"mem={[(hex(x), hex(v)) for x, v in d2[4]]}")
            return 1
    print(f"no divergence in {min(len(sp), len(dt))} aligned steps (spike {len(sp)}, det {len(dt)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
