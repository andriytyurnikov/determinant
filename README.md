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
zig build -Ddecoder=branch   # use reference branch-based decoder instead of LUT (default: lut)
zig build -Dmemory_size=1048576  # use 1 MB VM memory instead of default 64 KB
```

## Run

```sh
# Run built-in demo program
zig build run

# Load and execute a flat binary
zig build run -- program.bin

# Load with custom cycle limit
zig build run -- program.bin --max-cycles 1000
```

## Test

```sh
zig build test          # run tests with default decoder backend
zig build test-all      # run tests with both decoder backends (LUT + branch)
```

## Architecture

Library core in `src/` with per-extension modules. See [STRUCTURE.md](STRUCTURE.md) for the full annotated file tree and module conventions.

## Public API

The library is available via `@import("determinant")`.

- **`Cpu`** — VM state (decoder backend follows `-Ddecoder` build option, default: LUT)
  - `init()` — create a zeroed VM
  - `readReg(u5) → u32` / `writeReg(u5, u32)` — register access (x0 hardwired to zero)
  - `fetch() → u32` — read instruction word at PC
  - `loadProgram([]const u8, u32)` — load bytes into memory at offset
  - `step() → StepResult` — fetch, decode, execute one instruction
  - `run(max_cycles: u64) → StepResult` — execute until ECALL/EBREAK or cycle limit (0 = unlimited)
  - `readByte` / `readHalfword` / `readWord` — memory reads with bounds/alignment checks
  - `writeByte` / `writeHalfword` / `writeWord` — memory writes with bounds/alignment checks
- **`CpuType(comptime memory_size: u32, comptime decodeFn: DecodeFn)`** — generic VM constructor for custom memory size and decoder
- **`DecodeFn`** — decoder function pointer type (`*const fn (u32) DecodeError!Instruction`)
- **`Instruction`** — decoded instruction: `op`, `rd`, `rs1`, `rs2`, `imm`, `raw`, `compressed_op`
- **`Opcode`** — tagged union of per-extension opcode enums (`i: rv32i.Opcode`, `m: rv32m.Opcode`, `a: rv32a.Opcode`, `csr: zicsr.Opcode`, `zba: zba.Opcode`, `zbb: zbb.Opcode`, `zbs: zbs.Opcode`), with `format()` and `name()` methods
- **`Format`** — instruction format enum (R/I/S/B/U/J)
- **`instructions.isCompressed(u32)`** — returns true if the raw bits represent a 16-bit compressed (RV32C) instruction
- **`decode(u32)`** — decode using the primary comptime LUT decoder (fast, branchless), returns `Instruction` or `DecodeError`
- **`decodeBranch(u32)`** — decode using the reference branch-based decoder (for conformance testing and readability)
- **`decoders`** — access to both decoder modules (`decoders.branch`, `decoders.lut`)
- **`branch_decoder`** — direct access to the reference branch-based decoder module
- **`DecodeError`** — error set for decode failures
- **`StepResult`** — enum: `@"continue"`, `ecall`, `ebreak`
- **`default_memory_size`** — configured VM memory size in bytes (follows `-Dmemory_size` build option, default: 65536)
