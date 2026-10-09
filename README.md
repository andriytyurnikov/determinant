# Determinant

A deterministic RISC-V execution substrate for sandboxed computation.

Determinant is a virtual machine that executes RV32 RISC-V code deterministically. The same initial state and the same host actions produce bit-identical results on every host, in every build mode. This enables reproducibility, distributed verification and sandboxing. [SEMANTICS.md](SEMANTICS.md) is the precise contract.

## Why Determinant?

Traditional VMs introduce non-determinism through timing, memory layout randomization, and platform differences. Determinant eliminates these by design:

- Fixed, flat memory layout
- Instruction counting instead of wall-clock time
- No ambient inputs: no clock, no randomness and no access to the host. I/O goes through a small host-call ABI (read, write, exit) whose input is fixed before the run
- No undefined behavior and no platform-specific quirks: every configuration CI tests (Linux, macOS, `debug` and `fast` builds, big-endian) must reach the same final-state digests

## Use Cases

- **Smart contracts & blockchain** — deterministic execution required for consensus
- **Reproducible builds** — verify builds produce identical outputs
- **Security research** — record and replay exploits exactly
- **Distributed systems** — state machine replication with guaranteed consistency
- **Scientific computing** — bit-exact reproducibility across platforms

## Requirements

- [Zig](https://ziglang.org/) 0.17.0+

## Build

```sh
zig build
zig build -Dmemory_size=1048576  # use 1 MiB VM memory instead of default 64 KiB
```

## Run

```sh
# Run built-in demo program
zig build run

# Load and execute an ELF executable or a flat binary
zig build run -- program.elf
zig build run -- program.bin --load-addr 0x1000

# With a cycle limit, and bytes for the program's read() calls
zig build run -- program.elf --max-cycles 1000000 --input data.txt
```

### Program contract

The CLI runs a RISC-V program:
- **Loading.** The program is either an ELF32 executable (detected by its magic) or a flat binary.
  - An ELF is loaded by its `PT_LOAD` segments and starts at its entry point.
  - A flat binary is loaded at `--load-addr` (default 0) and starts there.

  Every register is zero except `sp`, which starts at the top of memory, 16-byte aligned.
- **Memory.** One flat region of `-Dmemory_size` bytes (default 64 KiB), zero-filled.
- **Host calls.** The program does I/O with ECALL, using the Linux RISC-V numbers in `a7`:
  - `read(0, buf, len)` (63) returns the bytes of `--input`;
  - `write(1 or 2, buf, len)` (64) prints to the CLI's stdout or stderr;
  - `exit(status)` (93, or 94 for `exit_group`) ends the program.

  See [docs/design/host-calls.md](docs/design/host-calls.md).
- **Stopping.** The program stops when it calls `exit`, at EBREAK, at an ECALL that is not a host call, or when `--max-cycles` is reached. The CLI then prints the stop reason, `pc` and the non-zero registers. Add `--dump-memory` (hexdump) or `--dump-memory raw` (hex digits) to also print the memory.
- **Faults.** On a fault (illegal instruction, misaligned or out-of-bounds access), it prints to stderr the error, `pc`, the instruction (with its disassembly), the faulting address and the registers.

The CLI's exit status tells how the run ended:
- If the program called `exit(status)`, the CLI exits with `status & 0xFF` and prints `Program exited with status N`.
- `0`: the program stopped at EBREAK, or at an ECALL that is not a host call.
- `1`: a usage or I/O error, including output that could not be written.
- `2`: the `--max-cycles` limit was reached.
- `3`: the VM raised a fault (illegal instruction, misaligned or out-of-bounds access).

`zig build run` reports any non-zero status as a failed step; run `zig-out/bin/determinant` directly to see the exact code.

## Test

```sh
zig build test              # run unit and CLI tests
zig build test-compliance   # run RISC-V compliance tests (riscv-tests suite)
zig build test-all          # run unit, CLI, compliance and digest tests (what CI runs)
zig build test-digests      # check corpus final-state digests against tests/digests.txt
zig build verify-decoder    # check the decoder against its spec on all 2^30 32-bit encodings
zig build bench             # MIPS on the C program corpus (always -Doptimize=fast)
```

Before a release, three more checks run against independent references. They need software CI does not install:
- [tools/llvm_oracle](tools/llvm_oracle/README.md) compares the decoder with LLVM's RISC-V disassembler on every encoding;
- [tools/spike_diff](tools/spike_diff/README.md) compares execution with Spike, the reference simulator, on random programs and edge cases;
- [tools/mutation](tools/mutation/README.md) runs the test suite against planted bugs.

### Performance

`zig build bench` runs the C program corpus. On an Apple M2 with Zig 0.17.0 (`-Doptimize=fast`) the VM executes about 275–285 million RISC-V instructions per second (geometric mean over the 20 corpus programs). About 1.4× of that comes from the per-PC decode cache; with `decode_cache_entries = 0` the figure is about 200. Compare numbers only from the same machine.

### Cross-platform determinism

`zig build test-digests` runs every corpus program (the compliance binaries, plus ten C programs such as SHA-256, CRC-32, quicksort and a bytecode interpreter, compiled two ways; see [tests/programs](tests/programs/README.md)), checks each C program's result against the same C run natively, and compares the SHA-256 of its final VM state (`stateDigest()`: pc, registers, counters, reservation, CSRs and all of memory, encoded little-endian) with `tests/digests.txt`. CI runs it on Linux and macOS, in `debug` and `fast` builds, and on a big-endian target, so every configuration must reach bit-identical final states.

### RISC-V Compliance

The VM passes 89 tests from the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) ISA test suite: RV32I (41, including `fence_i`), RV32M (8), RV32A (10), RV32C (1), Zba (3), Zbb (18), Zbs (8). Zicsr has no user-mode tests in the suite, so the CSR instructions are covered by unit tests only. `ma_data` is skipped because misaligned data accesses are fatal by design. Pre-compiled test binaries are checked in — no RISC-V toolchain needed to run them. See [tests/riscv-tests/README.md](tests/riscv-tests/README.md) for rebuild instructions.

## Architecture

Library core in `src/` with per-extension modules. See [STRUCTURE.md](STRUCTURE.md) for the layout, module dependencies and conventions, and [docs/design](docs/design) for the design notes. Changes are listed in [CHANGELOG.md](CHANGELOG.md), and third-party material in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Public API

The library is available via `@import("determinant")`. Execution semantics are specified in [SEMANTICS.md](SEMANTICS.md).

- **`Cpu`** — VM state (memory size follows the `-Dmemory_size` build option)
  - `init()` — return a zeroed VM by value (small memories only: the memory lives inside the struct)
  - `reset()` — zero a VM in place; use it on a heap-allocated VM for large memories
  - `readReg(u5) → u32` / `writeReg(u5, u32)` — register access (x0 hardwired to zero)
  - `fetch() → u32` — read instruction word at PC
  - `loadProgram([]const u8, u32)` — load bytes into memory at offset (drops an LR reservation on any word it overwrites)
  - `clearReservation()` — drop the LR reservation; call it after writing `memory` directly
  - `step() → StepError!StepResult` — fetch, decode and execute one instruction. A fault returns a `StepError` (`IllegalInstruction`, `MisalignedPC`, `PCOutOfBounds`, `MisalignedAccess`, `AddressOutOfBounds`) and leaves the state unchanged
  - `describeFault(StepError) → Fault` — after a fault: the instruction's address and bits and the faulting address
  - `stateDigest() → [32]u8` — SHA-256 of the full VM state in a canonical little-endian encoding (identical on every host)
  - `writeSnapshot(*Io.Writer)` / `restoreSnapshot(*Io.Reader)` — save and load the exact architectural state (`snapshot_size` bytes; the digest is the SHA-256 of the snapshot). A restore validates the header first and returns `error.InvalidSnapshot` on a mismatch. See [docs/design/snapshots.md](docs/design/snapshots.md)
  - `run(max_cycles: ?u64) → StepError!StepResult` — step until ECALL/EBREAK, a fault, or `cycle_count >= max_cycles`. The limit is absolute, not relative to this call; `null` means unlimited. Returns `.continue` when it stops at the limit. After `.ecall`/`.ebreak`, `pc` points past that instruction and `stop_pc` at it, so calling `run()` again continues
  - `runFor(steps: u64) → StepError!StepResult` — run at most `steps` more instructions
  - `pc`, `regs`, `memory`, `cycle_count` (retired instructions), `reservation`, `csrs` — the state, as public fields
  - `readByte` / `readHalfword` / `readWord` — memory reads with bounds/alignment checks
  - `writeByte` / `writeHalfword` / `writeWord` — memory writes with bounds/alignment checks
- **`CpuType(comptime memory_size: u32, comptime options: CpuOptions)`** — generic VM constructor. `CpuOptions` fields: `decode` (decoder function, default `decode`) and `decode_cache_entries` (size of the per-PC decode cache, a power of two or 0 to disable; default 4096). The cache never changes results; it only skips re-decoding unchanged instructions
- **`DecodeFn`** — decoder function pointer type (`*const fn (u32) DecodeError!Instruction`)
- **`Instruction`** — decoded instruction: `op`, `rd`, `rs1`, `rs2`, `imm`, `raw`, `compressed_op`
- **`Opcode`** — tagged union of per-extension opcode enums (`i: rv32i.Opcode`, `m: rv32m.Opcode`, `a: rv32a.Opcode`, `csr: zicsr.Opcode`, `zba: zba.Opcode`, `zbb: zbb.Opcode`, `zbs: zbs.Opcode`), with `format()` and `name()` methods
- **`Format`** — instruction format enum (R/I/S/B/U/J)
- **`instructions.isCompressed(u32)`** — returns true if the raw bits represent a 16-bit compressed (RV32C) instruction
- **`decode(u32)`** — decode a 32-bit word or a zero-extended 16-bit RV32C halfword, returns `Instruction` or `DecodeError`
- **`hostcall`** — the host-call ABI: `hostcall.handle(vm, &env)` performs the read/write/exit call that stopped `run()` with `.ecall` and returns `.resumed`, `.exit` or `.unknown` ([docs/design/host-calls.md](docs/design/host-calls.md))
- **`loader`** — `loader.loadElf(vm, image)` loads a RISC-V ELF32 executable and returns its entry point; `loader.isElf()` ([docs/design/program-loading.md](docs/design/program-loading.md))
- **`decoders`** — the decoder's parts: `branch` (the decoder), `expand` (RV32C expansion), `registry` (the specification of every 32-bit encoding, with `lookup()`), `bitfields`
- **`DecodeError`** — error set for decode failures
- **`StepResult`** — enum: `@"continue"` (still running, or stopped at the cycle limit), `ecall`, `ebreak`
- **`StepError`**, **`Fault`** — the fault error set, and `describeFault()`'s report
- **`default_memory_size`** — configured VM memory size in bytes (follows `-Dmemory_size` build option, default: 65536)
