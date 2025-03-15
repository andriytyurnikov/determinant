# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Determinant — a deterministic RISC-V VM. Written in Zig 0.15.2, structured as both a library and CLI executable. See `README.md` for architecture, public API, and conventions.

## Build Commands

- `zig build` — compile the project (output in `zig-out/`)
- `zig build run` — build and run the CLI executable
- `zig build test` — run all tests (library + executable)
- `zig build run -- <args>` — pass arguments to the executable

## Key Patterns

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- Tests live in `*_test.zig` companion files, pulled in via `test { _ = @import("foo_test.zig"); }` blocks
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- ISA extensions live in `src/instruction/` — each owns its own `Opcode` enum (with `name()` and `format()` methods), decode, and execute logic
- `instruction.zig` composes extensions via `Opcode = union(enum) { i: rv32i.Opcode, m: rv32m.Opcode, a: rv32a.Opcode, csr: zicsr.Opcode }`
- `instruction.Opcode` delegates `name()` and `format()` to extensions via `inline else`; `rv32a.name()` returns canonical dot notation (`"LR.W"`, `"AMOSWAP.W"`)
- `Format` enum lives in `format.zig` — extensions import it to provide their `format()` method; `instruction.zig` re-exports it
- Extension files (`rv32i.zig`, `rv32m.zig`, `rv32a.zig`, `zicsr.zig`) do NOT import `instruction.zig` — no circular deps
- CSR storage (`Csr` struct with `read`/`write`) lives in `zicsr.zig`, not `cpu.zig`
- Each extension's execution is delegated: `executeI()` (RV32I), `rv32m.execute()`, `rv32a.computeAmo()`, `zicsr.Csr.execute()`
- CPU dispatch methods named after tagged union fields: `executeI`, `executeA`, `executeCsr`; RV32M is inline (pure function)
- LR_W/SC_W orchestration stays in cpu.zig (needs reservation state + memory access); AMO computation is in `rv32a.zig`
- Shared test utilities live in `test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
- `rv32c.zig` imports `instruction.zig` (consumes types) — it expands 16-bit compressed to existing RV32I `Instruction`s; imported directly by `root.zig` (not via `instruction.zig`) to avoid circular dependency
- `rv32c.zig` has its own `Opcode` enum (26 variants) for decode/display purposes — NOT part of the `instruction.Opcode` tagged union (no execution path, no format); `decode()` maps bits→Opcode, `expand()` calls `decode()` then flat-switches to build `Instruction`
- `decoder.zig` sub-decoders use semantic names matching their rv32i counterparts: `decodeStore`, `decodeBranch`, `decodeLoad`, `decodeAtomic`, `decodeSystem`
- Decode return types: `rv32m.decodeR()` returns non-optional `Opcode` (all funct3 values valid); other decoders return `?Opcode` (some inputs invalid)
- No allocators in core VM — deterministic by construction
- FENCE is intentionally omitted (single-hart VM)
