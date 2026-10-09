#!/usr/bin/env python3
"""Random differential testing: Spike vs Determinant on generated programs.

  python3 -I tools/spike_diff/fuzz.py [--count N] [--start S] [--items K] [--mix MIX ...]
                                      [--jobs J] [--keep] [--work DIR] [tool options]

For every mix (gen.MIXES, all by default) and every seed in [S, S+N): generate a program
(gen.py), build it, run it on Spike and on the runner (decode cache on and off), and
compare the final state: outcome (stop or fault, and where), retired instruction count,
registers, mscratch, and the whole program image and data region. The generator only
emits programs on which the two must agree (README.md), so every difference is a
divergence. Divergences go to WORK/fuzz/divergences.jsonl and their programs are kept in
WORK/fuzz/<mix>/; other programs are deleted unless --keep. The exit status is 1 if a
program diverged or could not be built or run.
"""
import argparse
import collections
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

sys.dont_write_bytecode = True  # never write a __pycache__ into the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python3 -I omits it

import gen  # noqa: E402
import pipeline  # noqa: E402


def prepare(task):
    """Generate, build and run on Spike (in a worker process)."""
    tools, out, mix, seed, items = task
    d = os.path.join(out, mix)
    os.makedirs(d, exist_ok=True)
    asm = os.path.join(d, f"s{seed}.s")
    with open(asm, "w") as f:
        f.write(gen.Gen(seed, mix).program(items))
    try:
        elf, binf, syms = pipeline.build(asm, tools)
    except pipeline.BuildError as e:
        return dict(mix=mix, seed=seed, asm=asm, error="build: " + str(e)[:3000])
    words, note = pipeline.run_spike(elf, tools)
    return dict(mix=mix, seed=seed, asm=asm, elf=elf, bin=binf, syms=syms, words=words, note=note)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mix", action="append", choices=sorted(gen.MIXES), help="repeatable; default: all mixes")
    ap.add_argument("--count", type=int, default=100, help="programs per mix (default: %(default)s)")
    ap.add_argument("--start", type=int, default=0, help="first seed (default: %(default)s)")
    ap.add_argument("--items", type=int, default=250, help="items per program (default: %(default)s)")
    ap.add_argument("--jobs", type=int, default=4, help="parallel build/Spike jobs (default: %(default)s)")
    ap.add_argument("--batch", type=int, default=250, help="programs per runner call (default: %(default)s)")
    ap.add_argument("--keep", action="store_true", help="keep the artifacts of passing programs")
    pipeline.add_arguments(ap)
    a = ap.parse_args()
    tools, out = pipeline.setup(a, "fuzz")
    mixes = a.mix or sorted(gen.MIXES)
    divlog = open(os.path.join(out, "divergences.jsonl"), "a")
    summary = {}
    bad_total = 0
    t0 = time.time()

    for mix in mixes:
        st = collections.Counter()
        retired = []
        outcomes = collections.Counter()
        seeds = list(range(a.start, a.start + a.count))
        for b0 in range(0, len(seeds), a.batch):
            batch = seeds[b0:b0 + a.batch]
            with ProcessPoolExecutor(a.jobs) as ex:
                recs = list(ex.map(prepare, [(tools, out, mix, s, a.items) for s in batch]))
            runnable = [r for r in recs if "error" not in r and r["words"] is not None]
            manifest = os.path.join(out, mix, f"manifest_{batch[0]}.txt")
            with open(manifest, "w") as f:
                for r in runnable:
                    f.write(pipeline.manifest_line(r["bin"], r["syms"]) + "\n")
            det = pipeline.run_runner(manifest, tools) if runnable else {}
            for r in recs:
                st["programs"] += 1
                if "error" in r:
                    st["build_error"] += 1
                    bad_total += 1
                    divlog.write(json.dumps(dict(mix=mix, seed=r["seed"], kind="build_error",
                                                 detail=r["error"])) + "\n")
                    continue
                if r["words"] is None:
                    st["spike_error"] += 1
                    bad_total += 1
                    divlog.write(json.dumps(dict(mix=mix, seed=r["seed"], kind="spike_error",
                                                 detail=r["note"], asm=r["asm"])) + "\n")
                    continue
                st["compared"] += 1
                rec = det[r["bin"]]
                sp = pipeline.spike_state(r["words"], r["syms"])
                bad = False
                dd = pipeline.compare_configs(rec)
                if dd:
                    st["cache_on_off_differ"] += 1
                    bad = True
                    divlog.write(json.dumps(dict(mix=mix, seed=r["seed"], kind="cache_on_off",
                                                 detail=dd, asm=r["asm"])) + "\n")
                diffs = pipeline.compare(sp, rec["cache"])
                if diffs:
                    st["diverged"] += 1
                    bad = True
                    divlog.write(json.dumps(dict(mix=mix, seed=r["seed"], kind="spike_vs_det",
                                                 detail=diffs, asm=r["asm"])) + "\n")
                if bad:
                    bad_total += 1
                retired.append(rec["cache"]["retired"])
                outcomes[f"{rec['cache']['status']}/mcause={sp['mcause']}"] += 1
                if rec["cache"]["retired"] > 4900:
                    # Spike drops LR reservations every 5000 instructions (README.md)
                    st["long_program(>4900 insns)"] += 1
                if not bad and not a.keep:
                    pipeline.remove_artifacts(r["asm"])
            if not a.keep:
                os.remove(manifest)
            divlog.flush()
            print(f"[{time.time() - t0:7.1f}s] {mix}: {b0 + len(batch)}/{len(seeds)} {dict(st)}", flush=True)
        if retired:
            st["retired_min"] = min(retired)
            st["retired_max"] = max(retired)
            st["retired_mean"] = sum(retired) // len(retired)
        summary[mix] = dict(stats=dict(st), outcomes=dict(outcomes))
    divlog.close()
    print(json.dumps(summary, indent=1))
    with open(os.path.join(out, f"summary_{int(time.time())}.json"), "w") as f:
        json.dump(dict(args={k: v for k, v in vars(a).items()}, summary=summary), f, indent=1)
    n = sum(s["stats"].get("programs", 0) for s in summary.values())
    print(f"{n} programs, {bad_total} diverged or failed (details: {os.path.join(out, 'divergences.jsonl')})")
    return 1 if bad_total else 0


if __name__ == "__main__":
    sys.exit(main())
