"""Build, run and compare: the machinery shared by the Spike differential tests.

setup()        checks the tools, prepares the work directory (Spike's device tree and a
               stub dtc) and builds the runner with `zig build spike-runner`
build()        assembles and links a program (GNU as/ld, no relaxation), makes the flat
               binary and reads its symbols
run_spike()    runs a program on Spike and returns its signature dump
run_runner()   runs a manifest of programs on the runner, decode cache on and off
compare()      Spike's final state against one runner record
compare_configs()  the runner's two records (decode cache on and off) against each other

Nothing is written outside the work directory.
"""
import dataclasses
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import mkdtb
from template import (DUMP_MARKER, ISA_AS, ISA_SPIKE, LOAD_ADDR, SPIKE_INSTRET_OFFSET, SPIKE_MEM,
                      SPIKE_MEM_BASE, SPIKE_MEM_SIZE)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LINK = os.path.join(HERE, "link.ld")
DEFAULT_WORK = os.path.join(tempfile.gettempdir(), "determinant-spike-diff")
MAX_STEPS = 200000
CONFIGS = ("cache", "nocache")

# Spike's mcause for each runner status
CAUSES = {
    "ebreak": {3},
    "ecall": {11},
    "IllegalInstruction": {2},
    "MisalignedAccess": {4, 6},
    "AddressOutOfBounds": {5, 7},
    "PCOutOfBounds": {1},
    "MisalignedPC": {0},
}
CAUSE_NAMES = {0: "insn-misaligned", 1: "insn-access-fault", 2: "illegal-insn", 3: "breakpoint",
               4: "load-misaligned", 5: "load-access-fault", 6: "store/amo-misaligned",
               7: "store/amo-access-fault", 11: "ecall-M"}

# Spike pipes the DTS it generates into `dtc -O dtb` and reads a DTB back (and may run
# `dtc -I dtb -O dts` the other way). This stub, first on Spike's PATH, ignores its input
# and returns the minimal DTB from mkdtb.py next to it: no CLINT, PLIC or UART.
DTC_STUB = """\
#!/bin/sh
# Stub dtc for Spike, written by tools/spike_diff/pipeline.py: returns ../spike.dtb.
here=$(cd "$(dirname "$0")" && pwd)
cat >/dev/null
case "$*" in
  *"-I dtb"*) printf '/dts-v1/;\\n/ { };\\n' ;;
  *) cat "$here/../spike.dtb" ;;
esac
"""


class BuildError(Exception):
    pass


@dataclasses.dataclass(frozen=True)
class Tools:
    work: str  # the work directory, absolute
    spike: str  # Spike executable
    cross: str  # GNU toolchain prefix, e.g. /opt/homebrew/bin/riscv64-unknown-elf-
    runner: str  # spike-runner executable
    spike_env: dict  # Spike's environment: the stub dtc first on PATH


def add_arguments(ap):
    """The options every script takes."""
    ap.add_argument("--work", default=DEFAULT_WORK,
                    help="directory for all outputs, outside the repository (default: %(default)s)")
    ap.add_argument("--spike", default="spike", help="Spike executable (default: spike on PATH)")
    ap.add_argument("--cross", default="riscv64-unknown-elf-",
                    help="GNU toolchain prefix, as in PREFIXas (default: %(default)s on PATH)")
    ap.add_argument("--runner", help="use this spike-runner instead of building one with "
                                     "`zig build spike-runner` into the work directory")


def fail(msg):
    sys.exit(f"error: {msg}")


def setup(args, subdir=None, need_runner=True):
    """Checks the tools, prepares the work directory and builds the runner. Returns the
    Tools and this script's output directory, WORK/subdir (None without a subdir)."""
    work = os.path.realpath(args.work)
    repo = os.path.realpath(REPO)
    if os.path.commonpath([work, repo]) == repo:
        fail(f"the work directory {work} is inside the repository; use one outside it")
    if any(c.isspace() for c in work):
        fail(f"the work directory must not contain whitespace: {work!r}")
    os.makedirs(work, exist_ok=True)

    spike = shutil.which(args.spike)
    if spike is None:
        fail(f"Spike not found: {args.spike} (use --spike)")
    found = [shutil.which(args.cross + t) for t in ("as", "ld", "objcopy", "nm")]
    if None in found:
        fail(f"GNU toolchain not found: {args.cross}as/ld/objcopy/nm (use --cross)")
    cross = found[0][:-len("as")]

    with open(os.path.join(work, "spike.dtb"), "wb") as f:
        f.write(mkdtb.build(ISA_SPIKE, SPIKE_MEM_BASE, SPIKE_MEM_SIZE))
    fakebin = os.path.join(work, "fakebin")
    os.makedirs(fakebin, exist_ok=True)
    stub = os.path.join(fakebin, "dtc")
    with open(stub, "w") as f:
        f.write(DTC_STUB)
    os.chmod(stub, 0o755)
    spike_env = dict(os.environ, PATH=fakebin + os.pathsep + os.environ.get("PATH", ""))

    if args.runner:
        runner = os.path.abspath(args.runner)
        if not os.access(runner, os.X_OK):
            fail(f"not an executable: {runner}")
    else:
        runner = build_runner(work) if need_runner else ""
    out = os.path.join(work, subdir) if subdir else None
    if out:
        os.makedirs(out, exist_ok=True)
    return Tools(work=work, spike=spike, cross=cross, runner=runner, spike_env=spike_env), out


def build_runner(work):
    """`zig build spike-runner` (-Doptimize=safe) from the repository, installed and cached in
    the work directory, so that the runner always matches the current sources."""
    if shutil.which("zig") is None:
        fail("zig not found on PATH (or pass --runner)")
    prefix = os.path.join(work, "runner")
    cmd = ["zig", "build", "spike-runner", "-Doptimize=safe", "--prefix", prefix,
           "--cache-dir", os.path.join(work, "zig-cache")]
    print(f"building the runner: {' '.join(cmd)}", file=sys.stderr, flush=True)
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"building the runner failed:\n{r.stdout}{r.stderr}")
    return os.path.join(prefix, "bin", "spike-runner")


def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise BuildError(f"{' '.join(cmd)}\n{r.stdout}{r.stderr}")
    return r.stdout


def symbols(elf, tools):
    syms = {}
    for line in sh([tools.cross + "nm", elf]).splitlines():
        parts = line.split()
        if len(parts) == 3:
            syms[parts[2]] = int(parts[0], 16)
    return syms


def build(asm_path, tools):
    """Returns (elf, bin, symbols) for an assembly file NAME.s."""
    stem = asm_path[:-2]
    obj, elf, binf = stem + ".o", stem + ".elf", stem + ".bin"
    sh([tools.cross + "as", f"-march={ISA_AS}", "-mabi=ilp32", asm_path, "-o", obj])
    sh([tools.cross + "ld", "-m", "elf32lriscv", "-T", LINK, "--no-relax", "--no-warn-rwx-segments",
        obj, "-o", elf])
    sh([tools.cross + "objcopy", "-O", "binary", elf, binf])
    return elf, binf, symbols(elf, tools)


def remove_artifacts(asm_path):
    stem = asm_path[:-2]
    for ext in (".s", ".o", ".elf", ".bin", ".sig"):
        try:
            os.remove(stem + ext)
        except FileNotFoundError:
            pass


def run_spike(elf, tools, extra=(), timeout=30):
    """Returns (words, note); words is None when Spike produced no signature."""
    sig = elf[:-4] + ".sig"
    if os.path.exists(sig):
        os.remove(sig)
    cmd = [tools.spike, f"--isa={ISA_SPIKE}", f"-m{SPIKE_MEM}", *extra, f"+signature={sig}",
           "+signature-granularity=4", elf]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, env=tools.spike_env, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "spike timeout"
    if not os.path.exists(sig):
        return None, f"spike rc={r.returncode} no signature: {r.stderr.strip()[:300]}"
    with open(sig) as f:
        words = [int(w, 16) for w in f.read().split()]
    return words, f"rc={r.returncode}"


def manifest_line(binf, syms, max_steps=MAX_STEPS):
    return f"{binf} {LOAD_ADDR:x} {syms['test_start']:x} {LOAD_ADDR:x} {syms['trap_dump']:x} {max_steps}"


def run_runner(manifest_path, tools):
    """Returns {bin_path: {config: record}}."""
    out = subprocess.run([tools.runner, manifest_path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"spike-runner failed rc={out.returncode}: {out.stderr[-2000:]}")
    res = {}
    for line in out.stdout.splitlines():
        path, config, status, epc, retired, final_pc, x0, resv, regs, mscratch, digest, memhex = line.split(" ")
        res.setdefault(path, {})[config] = {
            "status": status,
            "epc": int(epc, 16),
            "retired": int(retired),
            "final_pc": int(final_pc, 16),
            "x0": int(x0, 16),
            "reservation": resv,
            "regs": [int(x, 16) for x in regs.split(",")],
            "mscratch": int(mscratch, 16),
            "digest": digest,
            "mem": bytes.fromhex(memhex),
        }
    return res


def spike_state(words, syms):
    td = (syms["trap_dump"] - LOAD_ADDR) // 4
    mem = struct.pack(f"<{td}I", *words[:td])
    d = words[td:td + 37]
    return {
        "marker_ok": len(d) == 37 and d[0] == DUMP_MARKER,
        "regs": d[1:32],
        "mscratch": d[32] if len(d) > 32 else 0,
        "mcause": d[33] if len(d) > 33 else -1,
        "mepc": d[34] if len(d) > 34 else 0,
        "mtval": d[35] if len(d) > 35 else 0,
        "minstret": d[36] if len(d) > 36 else 0,
        "mem": mem,
    }


def compare(sp, det):
    """Human-readable differences between Spike's state and one runner record."""
    if not sp["marker_ok"]:
        return ["spike did not reach the trap handler (no dump marker)"]
    diffs = []
    want = CAUSES.get(det["status"])
    if want is None or sp["mcause"] not in want:
        diffs.append(f"outcome: spike mcause={sp['mcause']}({CAUSE_NAMES.get(sp['mcause'], '?')}) "
                     f"mepc={sp['mepc']:#x} vs det status={det['status']} epc={det['epc']:#x}")
    elif sp["mepc"] != det["epc"]:
        diffs.append(f"epc: spike mepc={sp['mepc']:#x} vs det epc={det['epc']:#x}")
    else:
        # ECALL and EBREAK retire on Determinant (step() returns normally) but trap on
        # Spike, where they do not retire. A fault retires on neither.
        want_retired = sp["minstret"] - SPIKE_INSTRET_OFFSET + (det["status"] in ("ebreak", "ecall"))
        if det["retired"] != want_retired:
            diffs.append(f"retired: det={det['retired']} vs spike-derived={want_retired}")
    if det["x0"] != 0:
        diffs.append(f"det regs[0] = {det['x0']:#x} (x0 written)")
    for i in range(31):
        if sp["regs"][i] != det["regs"][i]:
            diffs.append(f"x{i + 1}: spike={sp['regs'][i]:#010x} det={det['regs'][i]:#010x}")
    if sp["mscratch"] != det["mscratch"]:
        diffs.append(f"mscratch: spike={sp['mscratch']:#010x} det={det['mscratch']:#010x}")
    a, b = sp["mem"], det["mem"]
    if a != b:
        n = 0
        for off in range(0, min(len(a), len(b)), 4):
            if a[off:off + 4] != b[off:off + 4]:
                n += 1
                if n <= 8:
                    sw = struct.unpack("<I", a[off:off + 4])[0]
                    dw = struct.unpack("<I", b[off:off + 4])[0]
                    diffs.append(f"mem[{LOAD_ADDR + off:#x}]: spike={sw:#010x} det={dw:#010x}")
        if n > 8:
            diffs.append(f"... {n} differing memory words in total")
        if len(a) != len(b):
            diffs.append(f"mem length spike={len(a)} det={len(b)}")
    return diffs


def compare_configs(rec):
    """The runner's records with the decode cache on and off must be identical."""
    missing = [c for c in CONFIGS if c not in rec]
    if missing:
        return [f"runner record missing for {', '.join(missing)}"]
    a, b = rec["cache"], rec["nocache"]
    return [f"decode cache on/off differ on {k}" for k in a if a[k] != b[k]]
