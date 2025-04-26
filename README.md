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
  root.zig                — library root, re-exports all submodules and convenience aliases
  main.zig                — CLI entry point, imports the library as @import("determinant")
  vm/
    cpu.zig               — Cpu struct: registers, PC, 1 MB memory, step/run executor, memory helpers
    cpu_test.zig          — pipeline infrastructure tests (init, fetch, memory, run)
    decoder.zig           — pure routing: bit extraction + dispatch to extension decoders; wraps rv32c.Expanded → Instruction
    decoder_test.zig      — encode/decode round-trip tests for all instruction formats
    instruction.zig       — imports all extensions; tagged union Opcode (i | m | a | csr | zba | zbb | zbs), isCompressed(), Format re-export, Instruction
    rv32c_cross_test.zig  — cross-validation: rv32c.Expanded vs decoder.decode() Instruction equivalence
    instruction/
      format.zig          — Format enum (R/I/S/B/U/J), shared by all extensions
      rv32i.zig           — RV32I base integer opcodes (39 variants), decode helpers, format()
      rv32i_test.zig      — RV32I decode + execute tests
      rv32m.zig           — RV32M multiply/divide opcodes (8 variants), decodeR(), execute(), format()
      rv32m_test.zig      — RV32M decode + execute tests
      rv32a.zig           — RV32A atomic opcodes (11 variants), decodeR(), execute(), format()
      rv32a_test.zig      — RV32A decode + execute tests
      rv32c.zig           — RV32C compressed instruction Opcode (26 variants), decode(), expand() (16-bit → Expanded); sibling-only imports (rv32i, format)
      rv32c_test.zig      — RV32C expansion + CPU step tests
      zicsr.zig           — Zicsr CSR opcodes (6 variants), decodeSystem(), format(), Csr struct with read/write/execute
      zicsr_test.zig      — Zicsr decode + execute tests
      zba.zig             — Zba address-generation opcodes (3 variants: SH1ADD, SH2ADD, SH3ADD), decodeR(), execute()
      zba_test.zig        — Zba decode + execute tests
      zbb.zig             — Zbb basic bit-manipulation opcodes (18 variants), decodeR(), decodeIAlu(), execute()
      zbb_test.zig        — Zbb decode + execute tests
      zbs.zig             — Zbs single-bit opcodes (8 variants), decodeR(), decodeIAlu(), execute()
      zbs_test.zig        — Zbs decode + execute tests
      test_helpers.zig    — shared test utilities (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
build.zig                 — build system configuration (library module, executable, test and run steps)
build.zig.zon             — package metadata (name, version, dependencies, fingerprint)
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
- **`Opcode`** — tagged union of per-extension opcode enums (`i: rv32i.Opcode`, `m: rv32m.Opcode`, `a: rv32a.Opcode`, `csr: zicsr.Opcode`, `zba: zba.Opcode`, `zbb: zbb.Opcode`, `zbs: zbs.Opcode`), with `format()` and `name()` methods
- **`Format`** — instruction format enum (R/I/S/B/U/J)
- **`instruction.isCompressed(u32)`** — returns true if the raw bits represent a 16-bit compressed (RV32C) instruction
- **`decode(u32)`** — decode an instruction word (16-bit compressed or 32-bit), returns `Instruction` or `DecodeError`
- **`StepResult`** — enum: `Continue`, `Ecall`, `Ebreak`

## Conventions

- The library module is named `"determinant"` and is importable from `main.zig` via `@import("determinant")`
- Tests live in dedicated `*_test.zig` companion files, pulled in via `test { _ = @import("foo_test.zig"); }` blocks
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- No allocators in core VM — deterministic by construction
- FENCE is intentionally omitted (single-hart VM)
- RV32C compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `Opcode` tagged union)
- Zba/Zbb/Zbs bit manipulation extensions follow the same pattern as other extensions — each owns its `Opcode` enum, decode, and execute logic
