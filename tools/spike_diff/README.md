# Spike differential tests

These scripts run RISC-V programs on [Spike](https://github.com/riscv-software-src/riscv-isa-sim),
the reference ISA simulator, and on Determinant. They compare the final states: how each
program stopped and where, the retired instruction count, every register, `mscratch`,
and the program image and data region byte for byte. Spike is an independent
implementation of the same specifications, so every difference is a bug in one of the
two, or one of the [known divergences](#known-divergences).

| File | Contents |
|---|---|
| `fuzz.py` | random programs from `gen.py`, in seven instruction mixes; the main campaign |
| `directed.py` | 114 directed edge cases, each with its expected outcome |
| `encsweep.py` | programs that each execute one random instruction word |
| `trace.py` | finds the first differing instruction of a diverging program |
| `coverage.py` | which instructions, branch directions and HINTs the generator exercises (Spike's log) |
| `gen.py` | the seeded random program generator |
| `template.py` | the program skeleton and memory layout, and Spike's trap handler |
| `pipeline.py` | tool setup, building programs, running Spike and the runner, the comparison |
| `mkdtb.py` | the minimal device tree that Spike gets in place of a real `dtc` |
| `runner.zig` | the VM side: runs programs and prints their final state (`zig build spike-runner`) |
| `link.ld` | the linker script (everything at 0x10000) |

These tools need Spike and a RISC-V toolchain, so CI does not run them.

## Prerequisites

- Spike. Tested with Homebrew's `riscv-isa-sim` (1.1.1-dev).
- The GNU binutils for RISC-V: `riscv64-unknown-elf-as`, `-ld`, `-objcopy` and `-nm`.
  Tested with binutils 2.45 from Homebrew's `riscv-gnu-toolchain`. GCC itself is not
  used.
- Python 3.8 or later. Only the standard library is used.
- Zig 0.17.0, to build the runner.
- No `dtc`. Spike shells out to `dtc` to compile its device tree, so `pipeline.py`
  writes a stub `dtc` into the work directory and puts it first on Spike's `PATH`. The
  stub returns the blob `mkdtb.py` built: one rv32 hart and the memory, with no CLINT,
  PLIC or UART, so the programs see no timer and no interrupts. The stub is used even
  when a real `dtc` is installed.

## Running it

```sh
WORK=/tmp/determinant-spike-diff    # any directory outside the repository
python3 -I tools/spike_diff/directed.py --work $WORK                 # the directed tests (~15 s)
python3 -I tools/spike_diff/fuzz.py --work $WORK --count 100         # 100 programs per mix, 700 in all (~15 s)
python3 -I tools/spike_diff/encsweep.py --work $WORK --count 8000    # 8,000 single instructions (~2 min)
python3 -I tools/spike_diff/coverage.py --work $WORK --count 30      # generator coverage
python3 -I tools/spike_diff/trace.py $WORK/fuzz/alu/s17.elf --work $WORK   # localize a kept divergence
```

A release campaign is `directed.py`, `fuzz.py --count 3000` (21,000 programs),
`encsweep.py --count 8000` and `coverage.py`. To split the fuzzing over several runs,
use different `--start` seeds with the same `--work`.

Common options:

- `--work DIR`: where all output goes. The default is `determinant-spike-diff` under
  the system temporary directory. A directory inside the repository is refused, and so
  is a path containing whitespace.
- `--spike PATH` and `--cross PREFIX`: the Spike executable and the toolchain prefix.
  The defaults are `spike` and `riscv64-unknown-elf-` on `PATH`.
- `--runner PATH`: a prebuilt runner (see below).
- `--jobs N`: parallel build and Spike jobs for `fuzz.py` and `encsweep.py` (default 4).
- `fuzz.py` also takes `--count`, `--start`, `--items` (default 250), `--mix` (repeatable)
  and `--keep`. `directed.py` takes `-k SUBSTRING` and `-v`. See `--help`.

Each script except `coverage.py` first builds the runner from the repository:
`zig build spike-runner -Doptimize=safe --prefix WORK/runner --cache-dir WORK/zig-cache`.
This way the runner always matches the current sources, and its safety checks stay on.
The first build in a new work directory takes 10 to 20 seconds. With `--runner PATH`,
the scripts use that executable instead. For example, `zig build spike-runner` installs
one at `zig-out/bin/spike-runner`, and a runner built from a modified copy of the tree
checks that copy. The scripts never write into the repository; they even turn off
Python's `__pycache__`. Run one script at a time per work directory.

## How a comparison works

`template.py` describes the program layout. Everything is linked at 0x10000.

- **On Spike**, the whole ELF runs: Spike's boot ROM, then a preamble that sets `mtvec`,
  then the test from `test_start`. The test ends in EBREAK, C.EBREAK or ECALL, or in a
  fault. All of these trap to the handler, which dumps x1 to x31, `mscratch`, `mcause`,
  `mepc`, `mtval` and `minstret` into the signature region and exits.
- **On Determinant**, the runner loads the flat binary at 0x10000 into a 0x50000-byte
  VM and starts at `test_start`. It runs each program twice, with the decode cache on
  and off, for at most 200,000 steps.
- **`compare()`** checks the outcome: Spike's `mcause` against the runner's status
  (breakpoint/EBREAK, ecall/ECALL, illegal instruction/`IllegalInstruction`,
  misaligned/`MisalignedAccess`, access fault/`AddressOutOfBounds`, instruction access
  fault/`PCOutOfBounds`). It then checks `mepc` against the address of the stopping
  instruction (the runner's `stop_pc` for ECALL/EBREAK, the faulting pc for a fault)
  and the retired count. Spike's count is `minstret` minus 9 (boot ROM 5, preamble 3,
  handler 1), plus 1 for ECALL/EBREAK: Determinant retires them, while on Spike they
  trap. Last come x1 to x31 (x0 must still be 0), `mscratch` and the memory from 0x10000
  up to the dump area.
- **`compare_configs()`** requires the decode-cache-on and -off records to be
  identical, including the `stateDigest()` of all memory.
- `directed.py` also checks that `pc` ends past ECALL/EBREAK (by 2 or 4) and is
  unchanged after a fault.

The random programs follow rules that keep both simulators comparable (see `gen.py`):

- every register is set first;
- one base register points into a 2 KiB data region, and every memory access is in
  bounds and aligned;
- control flow goes forward only, apart from counted loops;
- LR.W and SC.W have no store between them;
- counters are only read as differences;
- every program ends in EBREAK/ECALL or in a fault both simulators raise (misaligned or
  unmapped loads, stores, AMOs, LR and SC; jumps to unmapped memory; writes to
  read-only counters; unimplemented CSRs; reserved 32-bit and RVC encodings).

The mixes `alu`, `amo`, `branch`, `comp`, `csr`, `mem` and `mixed` weight the
instruction categories differently.

## Reading the results

**fuzz.py** prints a progress line per batch:
`[elapsed] mix: done/total {counters}`. The counters are `programs`, `compared`,
`diverged`, `cache_on_off_differ`, `build_error` and `spike_error`. `long_program` counts
programs that retired more than 4,900 instructions (see the reservation quantum below).
At the end comes a JSON summary per mix, with `retired_min/max/mean`. Its `outcomes`
count how the programs stopped, as `<runner status>/mcause=<Spike mcause>`, for example
`ebreak/mcause=3` or `MisalignedAccess/mcause=6`. The last line gives the number of
programs and how many diverged or failed. The exit status is 1 if any did.

Each divergence is a JSON line in `WORK/fuzz/divergences.jsonl`. The file is appended
to across runs. Each line has `mix`, `seed`, `kind` (`spike_vs_det`, `cache_on_off`,
`build_error` or `spike_error`), `detail` (the differences) and `asm`. The program is
kept as `WORK/fuzz/<mix>/s<seed>.{s,elf,bin,sig}`; programs that pass are deleted unless
you pass `--keep`. To find the first differing instruction, run
`trace.py WORK/fuzz/<mix>/s<seed>.elf`. `gen.py --seed S --mix M --items 250` prints
the same program again.

**directed.py** prints `name MATCH|DIVERGE [expected]` for each test, with
`<-- UNEXPECTED` when the result differs from the expectation. It then shows Spike's
`mcause`/`mepc` against the runner's status and pc, and the registers the test names
(`spike/det` where they differ). The last line gives the number of tests and of
unexpected results. The exit status is 1 if any result was unexpected. The report is
also written to `WORK/directed/results.txt`.

**encsweep.py** counts `match`, `known: <class>` and `UNKNOWN divergence`, and prints
the outcomes. Every divergence is a line in `WORK/encsweep/divergences.jsonl`, with the
instruction `word` and its `known` class or null. Its program is kept as
`WORK/encsweep/e<seed>.*`. The exit status is 1 if any divergence is unknown.

**trace.py** prints the first step where the pc, a register write or `mscratch`
differs, with the steps before it from Spike's commit log and the runner's trace. It
ignores the constant offset in counter reads.

**coverage.py** lists the implemented mnemonics that were never executed (none,
normally) and the least executed ones. It also shows branches taken and not taken,
rd = x0 executions, and the RVC HINT forms. "Other mnemonics" are the reserved
encodings of the fault terminators, as Spike names them.

## Known divergences

| Tag or class | Where it shows | Reason |
|---|---|---|
| `same-hart-store` | `directed.py` (4 tests) | A store or AMO by the same hart to the reserved word between LR.W and SC.W. Determinant drops the reservation, so SC.W fails (SEMANTICS.md, "LR/SC"). Spike keeps it, so SC.W succeeds. The spec allows both. The generator never stores between LR and SC. |
| `spike-reservation-quantum` | `directed.py` | Spike drops LR reservations every 5,000 instructions (its multi-hart interleaving quantum). Determinant's reservations never expire. Random programs retire fewer than 2,000 instructions; `long_program` counts any that come close. |
| `spike-misaligned-emulation` | `directed.py` (run with `spike --misaligned`) | Determinant's misaligned data accesses always fault (SEMANTICS.md, "Faults"). Spike emulates them when started with `--misaligned`. Without that flag both fault, and the other tests check that. |
| `smc-no-fencei` | `directed.py` | A store over an instruction that already ran, without FENCE.I. Spike executes its stale decoded copy. Determinant executes the new instruction, because every fetch reads memory (the decode cache is validated by the fetched bits). The spec leaves this unspecified without FENCE.I. With FENCE.I both agree. |
| `unsupported-csr` | `directed.py` (`mstatus`, `misa`, `mhartid`, `sscratch`, `time`) | Spike runs the programs in M-mode and implements the machine and supervisor CSRs and `time`. Determinant implements only `cycle`, `instret` and their high halves, plus `mscratch`; every other CSR raises IllegalInstruction (SEMANTICS.md, "CSRs"). The generator and the sweep use only those CSRs plus a few that neither implements. |
| privileged instructions | excluded by construction | MRET, SRET, WFI, SFENCE.VMA and the rest execute on Spike in M-mode and raise IllegalInstruction on Determinant. |
| `memory-map artifact` | `encsweep.py` (tallied as known) | Determinant's memory is [0, 0x50000). Spike's RAM is [0x10000, 0x50000), with its debug module and boot ROM below it. An access or jump below 0x10000 works on Determinant and faults on Spike. Only the sweep's random addresses reach that low. |
| `absolute cycle/instret value` | `encsweep.py` (tallied as known) | Spike's counters also count its boot ROM and the preamble, so absolute reads differ by 8. The generator reads them only as differences. |
| boot ROM registers | handled by the programs | Spike's boot ROM leaves a0 = hart id, a1 = the device tree address and t0 = the entry point. Determinant starts with every register at 0. Every program sets all 31 registers before it uses them. |
| ECALL/EBREAK retire | handled by `compare()` | Determinant retires ECALL and EBREAK: `cycle_count` counts them and `pc` moves past them. On Spike they trap without retiring. |

Some divergences the review found have since been fixed, and these cases must now
match: SC.W to a misaligned or unmapped address faults even without a reservation, and
LR.W with rs2 ≠ 0, ECALL/EBREAK with rd or rs1 ≠ 0, JALR with funct3 ≠ 0 and shifts
with shamt[5] = 1 are illegal. Directed tests, fault terminators and the sweep cover
them.

## Sensitivity

The harness was checked with bugs planted in scratch copies of the tree, using
`--runner`. A decode cache that never re-decodes a filled slot fails 3 directed tests
(self-modifying code) and the cache on/off comparison. SLTU computing `<=` fails the
directed comparison test and 2 of 56 random programs. Bugs that need equal operands are
the hardest for random programs to hit, so `gen.py` reuses the first source register in
10% of the two-operand instructions. Mutation testing of the test suites themselves is
in `tools/mutation`.

## Runtime

Measured on an Apple M2 with 4 jobs:

- `directed.py`: about 15 seconds.
- `fuzz.py`: about 65 programs per second (the review measured 16 per second on a
  heavily loaded machine), so 21,000 programs take 5 to 25 minutes.
- `encsweep.py`: about 70 programs per second.
- `coverage.py`: about 20 programs per second.
