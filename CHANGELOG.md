# Changelog

## 0.4.0 — unreleased

The memory size can be chosen at run time, by the library and by the CLI's `--memory`. The VM's behavior is unchanged: SEMANTICS.md (semantics version 1, state encoding version 1) and every digest in `tests/digests.txt` are the same. [docs/design/memory-size.md](docs/design/memory-size.md) describes the design.

### Library API (additions)

- **`RuntimeCpuType(options)`** and **`RuntimeCpu`**: a VM whose memory is a buffer the host passes to `init(memory)` or `initInPlace(memory)`, of any size from 4 bytes to 4 GiB − 4 (a multiple of 4). The VM still never allocates. It behaves exactly like a `CpuType` of the same size: same results, same snapshots, same digests. Copying the struct shares the memory.
- **`memSize()`** and **`snapshotSize()`** on both kinds. `CpuType` keeps `mem_size` and `snapshot_size`, and its code is unchanged.
- **`validMemorySize()`**, **`snapshotMemorySize()`** (the size in a snapshot's header, to size a `RuntimeCpu` before restoring) and **`InitError`**.

### CLI

- **`--memory SIZE`**: bytes, or with a `KiB`, `MiB` or `GiB` suffix (`--memory 1MiB`). Default: 64 KiB. One binary now runs programs of every size; the C corpus ELF runs with `--memory 256KiB`. Memory that cannot be allocated is an error.
- **Messages.** A fault or load error outside memory points to `--memory` instead of `-Dmemory_size`. An odd `--load-addr` and one outside memory have their own messages, and both checks come after all the options, so `--memory` may follow `--load-addr` or `--dump-range`.
- **`--version`** no longer names a memory size (`determinant 0.4.0 (fast build)`), and `--help` no longer prints the initial `sp`, which depends on `--memory`.

### Build, tests and tooling

- **`-Dmemory_size` is removed** (breaking). It set the CLI's memory size and the `Cpu` alias. Use `--memory` for the CLI, and `CpuType(N, options)` or `RuntimeCpuType` in code; `Cpu` is now always 64 KiB.
- **Both kinds checked against each other.** The compliance suite runs every binary on both kinds of memory and requires the same result and final state. `test-digests` adds a third run, on a `RuntimeCpuType` (`corpus_digests --runtime-memory`). `cpu/memory_kinds_test.zig` checks every bound on both kinds with sizes from 4 bytes to 64 KiB, and `init`'s size checks.
- **CLI tests at several sizes in one build.** The whole-run goldens run with the default memory and with 64 B, 4100 B, 1 MiB and 256 MiB. No test skips for lack of memory. CI's three `-Dmemory_size` jobs are replaced by smoke runs with `--memory`.
- **Speed.** `zig build bench` reports both kinds. On an Apple M2, `CpuType` is unchanged (about 275–290 MIPS), and `RuntimeCpuType` is about 4% slower.
- **Mutation catalogue.** 24 mutants are re-anchored to `memSize()`, and 24 new ones cover the two kinds, `init`'s checks, the snapshot size helpers and `--memory`. The harness knows the third digest run (`digests_runtime`).

## 0.3.0 — 2026-10-09

The VM's behavior is unchanged. SEMANTICS.md (semantics version 1, state encoding version 1) is the same, and so is every compliance digest in `tests/digests.txt` (the C corpus lines changed only because its binaries were rebuilt): 0.2.0 and 0.3.0 compute identical results for the same program. The CLI's output and some of its arguments change; [docs/design/cli.md](docs/design/cli.md) describes the new CLI.

### CLI (breaking)

- **stdout carries only the program's output.** The report (the "Running" line, the result, the registers, faults, dumps) moves to stderr, where it keeps its order with the program's own stderr. `determinant prog > out.txt` now captures exactly what the program wrote. Scripts that read the report from stdout need `2>&1`.
- **No arguments print the usage** and exit with status 1. The demo runs with `--demo` (`zig build run -- --demo`).
- **The report is reworded.** `Stopped at EBREAK (0x...) after N cycles`; an ECALL stop names `a7`; `pc` heads the register table; registers show their ABI names, hex and signed decimal; counts are singular for 1 ("1 cycle"); an exit status prints signed. Faults give the error in words and by name, the instruction with its disassembly, and the data address; an address outside memory names the memory size and `-Dmemory_size`.
- **Disassembly** uses ABI register names, CSR names, and absolute branch and jump targets when the address is known (a signed offset otherwise).
- **Errors** are in words (`no such file`, `is a directory`) and name the file. Usage errors point to `--help`.
- **Stricter arguments.** A second file argument is an error (it was ignored with a warning). `--load-addr` with an ELF file or `--demo` is an error (it was ignored). `--dump-memory` takes its format only after `=` (`--dump-memory=raw`), so `--dump-memory raw` runs a file named `raw`.

### CLI (additions)

- **Argument syntax.** `--opt=value`; `--` ends the options; numbers are decimal, `0x`, `0o` or `0b`, with `_` separators, for every option (`--max-cycles` took decimal only).
- **`-q`, `--quiet`**: only the program's output, faults and errors.
- **`--input -`** reads the program's input from stdin, all of it before the run.
- **`--dump-range ADDR:LEN`** dumps part of memory; a dump now also follows a fault.
- **`--digest`** prints the SHA-256 of the final VM state, as in `tests/digests.txt`.
- **`--trace`** prints every instruction as it retires, with the register or memory it wrote.
- **`--disassemble`** lists a flat binary, or an ELF file's executable segments, without running it.
- **`--version`.**

### Library API (additions)

- **`loader.segments(image)`** iterates over an ELF file's `PT_LOAD` segments as `loader.Segment` values, with their flags (`loader.PF_X` marks code).

### Build, tests and tooling

- **Zig 0.17.0.** The project now needs Zig 0.17.0 (`minimum_zig_version`, `.mise.toml`, and so CI). Zig 0.16.0 can no longer build it. Every compliance digest in `tests/digests.txt` is the same.
- **C corpus rebuilt.** Zig 0.17.0's C compiler generates different code, so the 20 corpus binaries and `elf/crc32.elf` are rebuilt, and the 20 `programs/` lines of `tests/digests.txt` are regenerated. The programs' results (`expected/`) are unchanged. `crc32.elf` gains a read-only segment, because LLVM now turns the table-building bit loop into a constant table.
- **Build mode names.** CI and the docs use Zig 0.17's `-Doptimize` names: `debug`, `safe`, `fast` and `small`. Zig accepts the old names (`Debug`, `ReleaseFast`, ...) until 0.18. `tools/spike_diff` builds its runner with `-Doptimize=safe`.
- **Speed.** On an Apple M2, `zig build bench` gives about 282 MIPS, against about 293 when Zig 0.16.0 builds the VM, on the same corpus binaries. Without the decode cache it rises from about 158 to about 200 MIPS.
- **CLI tests rewritten.** Argument parsing is one table (`main/args_test.zig`), and whole runs are compared with their exact output (`main/report_test.zig`) at every memory size CI builds. The tests share a fixture with a fixed stdin and captured stdout and stderr (`main/test_helpers.zig`).
- **CI's CLI smoke runs** read the report from stderr.
- **Mutation catalogue.** The CLI mutants are re-anchored to the new code, with 30 new ones for the arguments, streams, report, trace and listing, and one (LD14) for `loader.segments()`.

### Verification

These checks were run for this release, in addition to CI. The decoder and Spike results are the same as for 0.2.0.

- **Decoder vs LLVM** (`zig build llvm-oracle`). Every 16-bit encoding and all 2^30 32-bit encodings were compared with the LLVM 23 and LLVM 22 disassemblers, and nothing differs outside the documented classes. The decoder accepts 224,997,378 of the 32-bit encodings. With LLVM 23:
  - 216,596,738 disassemble identically;
  - 8,388,350 are FENCE or FENCE.I with nonzero fields that the spec says to ignore, which LLVM rejects;
  - 12,290 get a different name (the Zicbop prefetch hints, FENCE.TSO, UNIMP).

  The 1,028 encodings that LLVM accepts and the decoder rejects are privileged instructions. LLVM 22 does not name the prefetch hints, so it renames only 2.
- **Decoder vs registry** (`zig build verify-decoder`). All 2^30 32-bit encodings: 0 differences.
- **Execution vs Spike** (`tools/spike_diff`):
  - 21,000 random programs in seven instruction mixes, ending in EBREAK, ECALL and every kind of fault: 0 differences;
  - 114 directed edge cases: 0 unexpected;
  - 8,000 single-instruction programs: 0 unexplained (40 use addresses outside Spike's memory, 2 read absolute counter values);
  - all 122 implemented instructions executed.
- **Mutation testing** (`tools/mutation`, all 291 mutants). 280 are killed. 10 are equivalent: no test can tell them from the original, and `mutants.EQUIVALENT` gives the reason for each. The last one, SO03, dropped the flush that shows the preamble before the program runs; a test added after the release (`8c59691`) kills it, so every mutant that is not equivalent is now killed.
- **Portability.** `zig build test-all`, digest checks included, passes in CI on:
  - macOS and Linux x86_64 (`debug` and `fast`);
  - big-endian s390x under qemu;
  - `-Dmemory_size` of 64 B, 1 MiB and 256 MiB.

  The CLI runs a compliance program on macOS and Linux, and a small program at every memory size, in `debug` and `fast` builds.
- **Compliance from source.** All 89 compliance binaries, rebuilt with GCC 13.2 (CI), pass.

## 0.2.0 — 2026-10-09

This release follows a review of the project on 2026-10-07. [SEMANTICS.md](SEMANTICS.md) is new and is the contract from now on.

### Guest-visible semantic changes

These change what a program computes or where it stops. A deployment that needs reproducible results, such as consensus, must switch versions in lockstep.

- **SC.W faults on a bad address** before it looks at the reservation. A misaligned or out-of-bounds SC.W used to write 1 to `rd` when no matching reservation existed. It now raises `MisalignedAccess` / `AddressOutOfBounds`, and the fault leaves the reservation unchanged. This matches the spec, Spike and Sail.
- **Reserved encodings trap.** ECALL/EBREAK with `rd` or `rs1` ≠ 0 (2,046 encodings) and LR.W with `rs2` ≠ 0 (126,976 encodings) used to execute and now raise `IllegalInstruction`.
- **Host writes clear the LR reservation.** `loadProgram()` over a reserved word now drops the reservation, so a following SC.W fails.

These were reviewed and kept, and are now documented in SEMANTICS.md:
- ECALL and EBREAK retire and leave `pc` past themselves. The new `stop_pc` gives their address (D3).
- `mscratch` stays as a plain guest scratch CSR; `cycle` and `instret` count retired instructions; `time` traps (D4).
- Misaligned data accesses are fatal (D5).

### Library API (breaking)

- **`CpuType(memory_size, options)`** replaces `CpuType(memory_size, decodeFn)`. `CpuOptions` has `.decode` and `.decode_cache_entries`.
- **One decoder.** The LUT decoder, `decodeBranch`, `branch_decoder`, `decoders.lut` and the `-Ddecoder` build option are gone. `decode` is the decoder, and `decoders.registry` is its executable specification.
- **`step()`, `run()` and `runFor()` return `StepError!StepResult`.** `StepError` is a named set of the five faults.

### Library API (additions)

- **`reset()`** zeroes a VM in place. Use it for heap-allocated VMs with large memories. `init()` no longer embeds a memory-sized constant in the binary.
- **`runFor(n)`** gives a relative step budget; the limit of `run()` stays absolute.
- **Faults and stops.** `describeFault(err)` reports the faulting instruction and address. `stop_pc` gives the address of the stopping ECALL/EBREAK.
- **`clearReservation()`**, for hosts that write `memory` directly.
- **State.** `stateDigest()` is the SHA-256 of a canonical, versioned, little-endian state encoding. `writeSnapshot()` and `restoreSnapshot()` save and load exactly that state.
- **Decode cache.** A per-PC cache gives about 1.75× speed and never changes results (`decode_cache_entries = 0` disables it).
- **`hostcall`** is the host-call ABI (read, write, exit with Linux RISC-V numbers). **`loader`** loads ELF32 executables.
- **`TestCpu`**, a fixed 64 KiB CPU for the unit tests.

### CLI

- **Exit status:**
  - 0: stopped at ECALL or EBREAK;
  - 1: a usage or I/O error;
  - 2: the cycle limit was reached;
  - 3: a VM fault;
  - or the program's own status when it calls `exit`.

  Before, the status was 0 or 1 for everything.
- **Output fixes.**
  - Output that cannot be written (a closed pipe, a full disk) now gives status 1 and a message. It used to exit 0 with the output lost.
  - With `> out.txt 2>&1` the two streams overwrote each other, and with `>> log.txt` the log's existing contents were overwritten. stdout and stderr now stream.
- **Large memory.** The VM is allocated on the heap. The CLI used to crash with a stack overflow from 8 MiB (Debug) or 16 MiB (ReleaseFast) of `-Dmemory_size`.
- **Loading.**
  - ELF executables are loaded by their segments and start at their entry point.
  - `--load-addr` sets where a flat binary goes.
  - Programs start with `sp` at the 16-byte-aligned top of memory.
- **I/O.** `--input FILE` provides the bytes for the program's `read` host call, and its `write` calls print to the CLI's stdout and stderr.
- **Fault reports** show the instruction, its disassembly and the faulting address.
- **The demo** honours `--max-cycles`.
- **Exact sizes.** Memory sizes are printed exactly (`64 KiB`, `100 bytes`).

### Build, tests and tooling

- **CI.** Zig is pinned from `build.zig.zon` (CI was still on Zig 0.15.2 and had been failing since April). CI runs:
  - Linux and macOS × Debug and ReleaseFast;
  - a big-endian s390x job under qemu;
  - memory sizes of 64 B, 1 MiB and 256 MiB;
  - the exhaustive decoder check;
  - `zig fmt`.
- **`-Dmemory_size`** works at every valid size, from 4 B to 4 GiB − 4. It used to work only from 4,100 to 65,536 bytes, and invalid values are now rejected.
- **New build steps:**
  - `zig build test-digests`: every corpus program's final state is checked against `tests/digests.txt` on every configuration, with the decode cache on and off;
  - `zig build verify-decoder`: the decoder against the registry on all 2^30 32-bit encodings;
  - `zig build bench`: about 280–290 MIPS on an Apple M2, up from about 138;
  - `zig build programs`: rebuilds the C program corpus with Zig's C compiler, checked against native runs.
- **Compliance.**
  - `fence_i` is added.
  - An ECALL stop no longer counts as a pass.
  - The suite runs with every configuration.
  - The Makefile no longer deletes the checked-in binaries on `make clean`.
- **Release checks.** These are not in CI and need local tools (see their READMEs):
  - `tools/llvm_oracle` compares the decoder with LLVM's disassembler;
  - `tools/spike_diff` compares execution with Spike;
  - `tools/mutation` checks that the tests catch injected bugs.
- **New tests.** A precise-fault table, an exhaustive CSR table, resume semantics, register aliasing, address wrap-around, decode-cache safety, snapshots, host calls and ELF loading.
- **Test cleanup.** One-instruction tests are now tables, and duplicated tests are removed.
- **Notices.** `THIRD_PARTY_NOTICES.md` covers riscv-tests (BSD-3-Clause) and Zig compiler-rt (MIT).

### Verification

These checks were run for this release, in addition to CI.

- **Decoder vs LLVM** (`zig build llvm-oracle`). Every 16-bit encoding and all 2^30 32-bit encodings were compared with the LLVM 23 and LLVM 22 disassemblers, and nothing differs outside the documented classes. The decoder accepts 224,997,378 of the 32-bit encodings. With LLVM 23:
  - 216,596,738 disassemble identically;
  - 8,388,350 are FENCE or FENCE.I with nonzero fields that the spec says to ignore, which LLVM rejects;
  - 12,290 get a different name (the Zicbop prefetch hints, FENCE.TSO, UNIMP).

  The 1,028 encodings that LLVM accepts and the decoder rejects are privileged instructions.
- **Decoder vs registry** (`zig build verify-decoder`). All 2^30 32-bit encodings: 0 differences.
- **Execution vs Spike** (`tools/spike_diff`):
  - 21,000 random programs in seven instruction mixes, ending in EBREAK, ECALL and every kind of fault: 0 differences;
  - 114 directed edge cases: 0 unexpected;
  - 8,000 single-instruction programs: 0 unexplained (40 use addresses outside Spike's memory, 2 read absolute counter values);
  - all 122 implemented instructions executed.
- **Portability.** `zig build test-all`, digest checks included, passes on:
  - macOS (Debug and ReleaseFast);
  - Linux aarch64 (Debug, ReleaseSafe and ReleaseFast);
  - big-endian s390x under qemu;
  - `-Dmemory_size` from 4 B to 256 MiB.

  The CLI runs the demo and programs with 64 KiB, 1 MiB and 256 MiB of memory.
- **Compliance from source.** Rebuilt with GCC 13, 86 of the 89 compliance binaries are byte-identical to the checked-in ones, and all 89 pass.

## 0.1.29 and earlier

No changelog was kept. The tag `v0.1.29` points at a commit that is not on `main`.
