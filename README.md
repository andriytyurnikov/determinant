# Determinant

A deterministic RISC-V execution substrate for sandboxed computation.

Determinant is a virtual machine that executes RISC-V code with guaranteed deterministic behavior. Same inputs always produce identical outputs, enabling perfect reproducibility, distributed verification, and trustworthy sandboxing.

## Why Determinant?

Traditional VMs introduce non-determinism through timing, memory layout randomization, and platform differences. Determinant eliminates these by design:

- Fixed memory layout
- Instruction counting instead of wall-clock time
- Deterministic I/O through controlled syscall interface
- No undefined behavior, no platform-specific quirks

## Use Cases

- **Smart contracts & blockchain** — deterministic execution required for consensus
- **Reproducible builds** — verify builds produce identical outputs
- **Security research** — record and replay exploits exactly
- **Distributed systems** — state machine replication with guaranteed consistency
- **Scientific computing** — bit-exact reproducibility across platforms

## Requirements

- [Zig](https://ziglang.org/) 0.15.2+

## Build

```sh
zig build
```

## Run

```sh
zig build run
```

## Test

```sh
zig build test
```

## Architecture

```
src/
  root.zig          — library root, re-exports all submodules and convenience aliases
  instruction.zig   — Opcode enum (all RV32I instructions), Format enum (R/I/S/B/U/J), Instruction struct
  decoder.zig       — decode(u32) → Instruction with full RV32I decoding and immediate extraction
  decoder_test.zig  — decoder tests and encoder helpers
  cpu.zig           — Cpu struct: registers (x0-x31), PC, 1 MB memory, step/run executor, memory helpers
  cpu_test.zig      — CPU tests (register, memory, step, run)
  main.zig          — CLI entry point, imports the library as @import("determinant")
build.zig           — build system configuration (library module, executable, test and run steps)
build.zig.zon       — package metadata (name, version, dependencies, fingerprint)
```

## Public API

The library is available via `@import("determinant")`.

- **`Cpu`** — VM state
  - `init()` — create a zeroed VM
  - `readReg(u5) → u32` / `writeReg(u5, u32)` — register access (x0 hardwired to zero)
  - `fetch() → u32` — read instruction word at PC
  - `loadProgram([]const u8, u32)` — load bytes into memory at offset
  - `step() → StepResult` — fetch, decode, execute one instruction
  - `run(max_cycles: u64) → StepResult` — execute until ECALL/EBREAK or cycle limit (0 = unlimited)
  - `readByte` / `readHalfword` / `readWord` — memory reads with bounds/alignment checks
  - `writeByte` / `writeHalfword` / `writeWord` — memory writes with bounds/alignment checks
- **`Instruction`** — decoded instruction: `op`, `rd`, `rs1`, `rs2`, `imm`, `raw`
- **`Opcode`** — enum of all RV32I opcodes, with `format()` method
- **`Format`** — instruction format enum (R/I/S/B/U/J)
- **`decode(u32)`** — decode a 32-bit instruction word, returns `Instruction` or `DecodeError`
- **`StepResult`** — enum: `Continue`, `Ecall`, `Ebreak`

## Conventions

- The library module is named `"determinant"` and is importable from `main.zig` via `@import("determinant")`
- Tests live in dedicated `*_test.zig` companion files, pulled in via `test { _ = @import("foo_test.zig"); }` blocks
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- No allocators in core VM — deterministic by construction
- FENCE is intentionally omitted (single-hart VM)
