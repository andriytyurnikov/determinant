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

Library core in `src/vm/` with per-extension modules. See [STRUCTURE.md](STRUCTURE.md) for the full annotated file tree and module conventions.

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
- **`Opcode`** — tagged union of per-extension opcode enums (`i: rv32i.Opcode`, `m: rv32m.Opcode`, `a: rv32a.Opcode`, `csr: zicsr.Opcode`, `zba: zba.Opcode`, `zbb: zbb.Opcode`, `zbs: zbs.Opcode`), with `format()` and `name()` methods
- **`Format`** — instruction format enum (R/I/S/B/U/J)
- **`instructions.isCompressed(u32)`** — returns true if the raw bits represent a 16-bit compressed (RV32C) instruction
- **`decode(u32)`** — decode an instruction word (16-bit compressed or 32-bit), returns `Instruction` or `DecodeError`
- **`StepResult`** — enum: `Continue`, `Ecall`, `Ebreak`
