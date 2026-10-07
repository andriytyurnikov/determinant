#!/usr/bin/env python3
"""Random-encoding sweep: each program executes ONE random instruction word.

  python3 -I tools/spike_diff/encsweep.py [--count N] [--start S] [--jobs J] [--work DIR] [tool options]

32-bit words get a real major opcode (OP, OP-IMM, LOAD, STORE, MISC-MEM, AMO,
SYSTEM/CSR, LUI, AUIPC, BRANCH, JALR) or a random one, with all other fields random
(biased toward the funct7 values the implemented extensions use); 16-bit words are
random RVC halfwords. Registers hold 4-byte-aligned pointers into an 8 KiB data region
(so most memory accesses are in bounds) or random values. The instruction sits at
>= 0x11000, between two 4 KiB zero pads, so PC-relative targets stay in Spike's RAM.

Excluded by construction, as known divergences or memory-map artifacts (README.md):
JAL (+-1 MiB reaches below 0x10000, where only Determinant has RAM), the privileged
instructions of SYSTEM funct3=0 (only the ECALL and EBREAK encodings are generated, with
any rd and rs1), and CSR numbers other than the implemented ones plus a few that neither
implements. Divergences of a known class are tallied as such; any other is UNKNOWN.
Results go to WORK/encsweep/divergences.jsonl, and the programs of divergences are kept.
The exit status is 1 if any divergence is UNKNOWN.
"""
import argparse
import collections
import json
import os
import random
import sys
from concurrent.futures import ProcessPoolExecutor

sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

import pipeline  # noqa: E402
from template import HEADER, LOAD_ADDR, indent, signature_tail, trap_handler  # noqa: E402

DATA_WORDS = 2048  # 8 KiB
CSRS = [0xC00, 0xC02, 0xC80, 0xC82, 0x340, 0x7C0, 0xC03, 0x8FF]
F7S = [0x00, 0x20, 0x01, 0x05, 0x04, 0x10, 0x14, 0x24, 0x30, 0x34]
MAX_STEPS = 20000


def rand_word(rng):
    if rng.random() < 0.3:  # RVC
        while True:
            h = rng.getrandbits(16)
            if h & 3 != 3:
                return h, 2
    op = rng.choice([0x33, 0x33, 0x13, 0x13, 0x03, 0x23, 0x0F, 0x2F, 0x2F, 0x73, 0x37, 0x17, 0x63, 0x67,
                     rng.getrandbits(7) | 3])
    w = rng.getrandbits(32) & ~0x7F | op
    if op in (0x33, 0x13) and rng.random() < 0.7:
        w = (w & 0x01FFFFFF) | rng.choice(F7S) << 25
    if op == 0x2F and rng.random() < 0.7:
        w = (w & ~0x7000) | 0x2000  # funct3 = .W
    if op == 0x73:
        f3 = rng.choice([1, 2, 3, 5, 6, 7, 0])
        w = (w & 0x000F8F80) | rng.choice(CSRS) << 20 | f3 << 12 | 0x73
    if (w & 0x7F) == 0x6F:  # never JAL (see the module doc)
        w ^= 0x10
    if (w & 0x7F) == 0x73 and (w >> 12) & 7 == 0:
        # SYSTEM funct3=0: only the ECALL/EBREAK encodings, mostly canonical, otherwise
        # with random rd/rs1 (reserved: illegal in both)
        w = rng.choice([0x00000073, 0x00100073])
        if rng.random() < 0.3:
            w |= rng.getrandbits(5) << 7 | rng.getrandbits(5) << 15
    return w, 4


def build_one(task):
    tools, wd, seed = task
    rng = random.Random(f"enc:{seed}")
    word, size = rand_word(rng)
    lines, init = [], {0: ("val", 0)}
    for r in range(1, 32):
        if rng.random() < 0.65:
            off = 4 * rng.randint(-200, 200)
            init[r] = ("ptr", off)
            lines.append(f"la x{r}, data_mid+{off}")
        else:
            v = rng.getrandbits(32) if rng.random() < 0.7 else rng.choice([0, 1, 0xFFFFFFFF, 0x80000000])
            init[r] = ("val", v)
            lines.append(f"li x{r}, 0x{v:x}")
    # zero padding (illegal in both) on both sides: B-type/C.J targets (+-4 KiB) can reach
    # neither the prologue nor Spike's trap handler, which Determinant cannot execute
    lines += ["j 1f", ".skip 4096", "1:", "test_insn:",
              f".2byte 0x{word:04x}" if size == 2 else f".4byte 0x{word:08x}", "ebreak", ".skip 4096"]
    data = [0] * DATA_WORDS
    for i in rng.sample(range(DATA_WORDS), 64):
        data[i] = rng.getrandbits(32)
    out = ["  .data", "  .align 6", "data_region:"]
    for i in range(0, DATA_WORDS, 8):
        out.append("  .word " + ", ".join(f"0x{x:08x}" for x in data[i:i + 8]))
        if i == DATA_WORDS // 2 - 8:
            out.append("data_mid:")
    src = HEADER + "\n".join(indent(lines)) + "\n" + trap_handler() + "\n".join(out) + "\n" + signature_tail()
    asm = os.path.join(wd, f"e{seed}.s")
    with open(asm, "w") as f:
        f.write(src)
    try:
        elf, binf, syms = pipeline.build(asm, tools)
    except pipeline.BuildError as e:
        return dict(seed=seed, word=word, size=size, asm=asm, error=str(e)[:500])
    words, note = pipeline.run_spike(elf, tools, timeout=5)
    regs = [v if k == "val" else (syms["data_mid"] + v) & 0xFFFFFFFF for k, v in (init[r] for r in range(32))]
    return dict(seed=seed, word=word, size=size, asm=asm, bin=binf, syms=syms, words=words, note=note,
                init_regs=regs)


def sext(v, bits):
    return v - (1 << bits) if v >> (bits - 1) & 1 else v


def effective_address(word, size, regs):
    """The data address or jump target the instruction uses (None if it has none)."""
    if size == 2:
        op, f3 = word & 3, word >> 13
        if op == 0 and f3 in (2, 6):  # C.LW / C.SW: base x8-x15, offset <= 124
            return regs[8 + ((word >> 7) & 7)]
        if op == 2 and f3 in (2, 6):  # C.LWSP / C.SWSP: base sp, offset <= 252
            return regs[2]
        if op == 2 and f3 == 4 and (word >> 2) & 31 == 0:  # C.JR / C.JALR
            return regs[(word >> 7) & 31]
        return None
    op, rs1 = word & 0x7F, (word >> 15) & 31
    if op in (0x03, 0x67):
        return (regs[rs1] + sext(word >> 20, 12)) & 0xFFFFFFFF
    if op == 0x23:
        return (regs[rs1] + sext(((word >> 25) << 5) | ((word >> 7) & 31), 12)) & 0xFFFFFFFF
    if op == 0x2F:
        return regs[rs1]
    return None


def known_class(r, sp, d, diffs):
    """The known divergence class a divergence belongs to, or None."""
    w = r["word"]
    if r["size"] == 4 and w & 0x7F == 0x73 and (w >> 12) & 3 in (2, 3) and (w >> 20) in (0xC00, 0xC02):
        rd = (w >> 7) & 31
        if len(diffs) == 1 and rd and (sp["regs"][rd - 1] - d["regs"][rd - 1]) & 0xFFFFFFFF == 8:
            return "absolute cycle/instret value (Spike also counts 8 boot ROM and preamble insns)"
    ea = effective_address(w, r["size"], r["init_regs"])
    if ea is not None and ea < LOAD_ADDR + 256:
        # Determinant's RAM is [0, 0x50000); Spike's is [0x10000, 0x50000) (its boot ROM
        # and debug module live below 0x10000), so only Determinant can access these
        return "memory-map artifact (address below 0x10000)"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=1000, help="programs (default: %(default)s)")
    ap.add_argument("--start", type=int, default=0, help="first seed (default: %(default)s)")
    ap.add_argument("--jobs", type=int, default=4, help="parallel build/Spike jobs (default: %(default)s)")
    ap.add_argument("--batch", type=int, default=400, help="programs per runner call (default: %(default)s)")
    pipeline.add_arguments(ap)
    a = ap.parse_args()
    tools, out = pipeline.setup(a, "encsweep")
    st = collections.Counter()
    outcomes = collections.Counter()
    log = open(os.path.join(out, "divergences.jsonl"), "a")
    for b0 in range(a.start, a.start + a.count, a.batch):
        seeds = range(b0, min(b0 + a.batch, a.start + a.count))
        with ProcessPoolExecutor(a.jobs) as ex:
            recs = list(ex.map(build_one, [(tools, out, s) for s in seeds]))
        ok = [r for r in recs if "error" not in r and r["words"] is not None]
        man = os.path.join(out, f"manifest_{b0}.txt")
        with open(man, "w") as f:
            for r in ok:
                f.write(pipeline.manifest_line(r["bin"], r["syms"], MAX_STEPS) + "\n")
        det = pipeline.run_runner(man, tools) if ok else {}
        for r in recs:
            st["programs"] += 1
            if "error" in r:
                st["build_error"] += 1
                log.write(json.dumps(dict(seed=r["seed"], word=hex(r["word"]), kind="build_error", detail=r["error"])) + "\n")
                continue
            if r["words"] is None:
                st["spike_error"] += 1
                log.write(json.dumps(dict(seed=r["seed"], word=hex(r["word"]), kind="spike_error", note=r["note"])) + "\n")
                continue
            sp = pipeline.spike_state(r["words"], r["syms"])
            rec = det[r["bin"]]
            dd = pipeline.compare_configs(rec)
            diffs = pipeline.compare(sp, rec["cache"])
            outcomes[f"{rec['cache']['status']}/mcause={sp['mcause']}"] += 1
            if dd:
                st["UNKNOWN: decode cache on/off differ"] += 1
                log.write(json.dumps(dict(seed=r["seed"], word=hex(r["word"]), kind="cache_on_off", detail=dd)) + "\n")
            if diffs:
                k = known_class(r, sp, rec["cache"], diffs)
                st["known: " + k if k else "UNKNOWN divergence"] += 1
                log.write(json.dumps(dict(seed=r["seed"], word=hex(r["word"]), size=r["size"], known=k,
                                          detail=diffs[:6])) + "\n")
            elif not dd:
                st["match"] += 1
                pipeline.remove_artifacts(r["asm"])
        os.remove(man)
        log.flush()
        print(f"{b0 + len(seeds) - a.start}/{a.count} {dict(st)}", flush=True)
    log.close()
    print(json.dumps(dict(stats=dict(st), outcomes=dict(outcomes.most_common())), indent=1))
    unknown = sum(v for k, v in st.items() if k.startswith("UNKNOWN") or k.endswith("_error"))
    print(f"{st['programs']} programs, {unknown} unknown divergences or errors "
          f"(details: {os.path.join(out, 'divergences.jsonl')})")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
