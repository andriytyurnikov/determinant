# Changelog

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
