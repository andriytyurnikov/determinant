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
- ISA extensions live in `src/instruction/` — each owns its own `Opcode` enum and decode/execute logic
- `instruction.zig` composes extensions via `Opcode = union(enum) { i: rv32i.Opcode, m: rv32m.Opcode }`
- Extension files (`rv32i.zig`, `rv32m.zig`) do NOT import `instruction.zig` — no circular deps
- `rv32c.zig` imports `instruction.zig` (consumes types) — it expands 16-bit compressed to existing RV32I `Instruction`s
- No allocators in core VM — deterministic by construction
- FENCE is intentionally omitted (single-hart VM)
