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
- ISA extensions live in `src/instruction/` — each owns its own `Opcode` enum (with `name()`, `format()`, and comptime `meta()` methods), decode, and execute logic
- `format.zig` exports `Meta` struct (`name_str` + `fmt`) and generic `opcodeName`/`opcodeFormat` helpers; each extension's `Opcode` provides a `pub fn meta(comptime self)` and thin `name()`/`format()` wrappers that delegate to the generic helpers
- `instruction.zig` composes extensions via `Opcode = union(enum) { i: rv32i.Opcode, m: rv32m.Opcode, a: rv32a.Opcode, csr: zicsr.Opcode, zba: zba.Opcode, zbb: zbb.Opcode, zbs: zbs.Opcode }`
- `instruction.Opcode` delegates `name()` and `format()` to extensions via `inline else`; `rv32a.name()` returns canonical dot notation (`"LR.W"`, `"AMOSWAP.W"`)
- `format.zig` owns `Format` enum, `Meta` struct, and generic `opcodeName`/`opcodeFormat` helpers; extensions import it as `fmt`; `instruction.zig` re-exports `Format`
- CSR storage (`Csr` struct with `read`/`write`) lives in `zicsr.zig`, not `cpu.zig`
- Each extension's execution is delegated: `executeI()` (RV32I), `rv32m.execute()`, `rv32a.execute()`, `zicsr.Csr.execute()`, `zba.execute()`, `zbb.execute()`, `zbs.execute()`
- CPU dispatch methods named after tagged union fields: `executeI`, `executeM`, `executeA`, `executeCsr`, `executeZba`, `executeZbb`, `executeZbs`
- LR_W/SC_W orchestration stays in cpu.zig (needs reservation state + memory access); AMO computation is in `rv32a.zig`
- Shared test utilities live in `test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
- `rv32c.zig` imports `instruction.zig` (consumes types) — it expands 16-bit compressed to existing RV32I `Instruction`s; imported directly by `root.zig` (not via `instruction.zig`) to avoid circular dependency
- `rv32c.zig` has its own `Opcode` enum (26 variants) for decode/display purposes — NOT part of the `instruction.Opcode` tagged union (no execution path, no format); uses `meta()` with a comptime `dotName` transform (`C_LW` → `"C.LW"`); `decode()` maps bits→Opcode, `expand()` calls `decode()` then flat-switches to build `Instruction`
- `decoder.zig` sub-decoders use semantic names matching their rv32i counterparts: `decodeStore`, `decodeBranch`, `decodeLoad`, `decodeAtomic`, `decodeSystem`
- Decode return types: `rv32m.decodeR()` returns non-optional `Opcode` (all funct3 values valid); other decoders return `?Opcode` (some inputs invalid)
- No allocators in core VM — deterministic by construction
- FENCE is intentionally omitted (single-hart VM)
- `instruction.isCompressed(raw)` is the single source of truth for 16-bit vs 32-bit detection — used by decoder.zig, cpu.zig, and main.zig
- Memory write methods (`writeByte`, `writeHalfword`, `writeWord`) auto-call `invalidateReservation()` — store sites don't need to invalidate manually
- Reservation state is `reservation: ?u32` (null = no reservation) — eliminates impossible states
- `decoder_test.zig` contains encode/decode round-trip tests; `rv32c_cross_test.zig` cross-validates compressed expansion against 32-bit decode
