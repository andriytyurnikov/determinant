# Project Structure

## Layout

```
src/
  root.zig                — library root: re-exports cpu, instructions, decoders, hostcall, loader, decode() and the common types
  main.zig, main/         — the CLI, which imports the library as @import("determinant"), and its tests
  cpu.zig, cpu/           — CpuType: state, step/run, memory, reservations, decode cache; exec_i.zig executes RV32I,
                            state.zig is the canonical state encoding (stateDigest, snapshots)
  instructions.zig, instructions/
                          — the Opcode tagged union and Instruction; one module per extension (rv32i, with rv32c
                            beneath it, rv32m, rv32a, zicsr, zba, zbb, zbs); format.zig; test_helpers.zig
  decoders.zig, decoders/ — the decoder (branch.zig), compressed expansion (expand.zig), bit fields (bitfields.zig),
                            and the opcode registry, the decoder's specification (registry.zig)
  hostcall.zig            — the host-call ABI: read, write and exit for the ECALL that stopped run()
  loader.zig              — ELF32 loader
  compliance.zig, compliance/
                          — riscv-tests runner and suites; bin/ holds the checked-in binaries
tools/
  verify_decoder.zig      — decoder vs. registry on all 2^30 32-bit encodings (`zig build verify-decoder`)
  corpus_digests.zig      — runs the corpus and prints or checks its digests (`zig build digests`, `test-digests`)
  bench.zig               — benchmark on the C corpus (`zig build bench`)
  llvm_oracle/, spike_diff/, mutation/
                          — opt-in release checks, each with a README
tests/
  digests.txt             — golden final-state digests of the corpus
  programs/               — C program corpus: sources, checked-in binaries, native results (README)
  riscv-tests/            — rebuilds the compliance binaries from source: submodule, test environment, Makefile (README)
docs/design/              — design notes: host calls, snapshots, program loading, memory protection
```

At the top level: README.md (overview, CLI, API), SEMANTICS.md (the execution contract), CHANGELOG.md, THIRD_PARTY_NOTICES.md, CLAUDE.md (guidance for working on the code), build.zig and build.zig.zon.

Every non-test source file starts with a `//!` comment that says what it is. A module's test files are listed in its `tests.zig` hub.

## Module Dependencies

All edges point downward. There are no cycles, and none should be introduced.

```
main.zig ─→ root.zig ─→ hostcall.zig, loader.zig (generic over CpuType: no imports of cpu.zig)
                │
main.zig ─→ root.zig ─→ cpu.zig ─→ instructions.zig ─→ [extensions] ─→ format.zig
                │          ↓
                └──→ decoders.zig ─→ branch.zig ─→ bitfields.zig, expand.zig
                                  ↘ registry.zig ─→ bitfields.zig
```

- `cpu.zig` imports `decoders.zig` (the default decoder for `Options.decode`, and `DecodeError`). `cpu/exec_i.zig` and `cpu/state.zig` have no upward dependency
- `compliance.zig` and the programs in `tools/` import the `determinant` library module, not relative paths: they are separate modules, not part of the library
- Extensions (rv32i, rv32m, rv32a, zicsr, zba, zbb, zbs) import only `format.zig`, never cpu, decoders or instructions. This holds for their non-test files; their tests may import cpu.zig, the decoder and `instructions/test_helpers.zig`
- RV32C imports only `rv32i.zig` and `format.zig` (a decode-time front end, no upward dependency). `rv32c/expand.zig` imports `rv32c.zig`, `rv32i.zig` and `imm.zig`; `rv32c/imm.zig` imports nothing

## Module Conventions

- The library module is named `"determinant"`; the CLI imports it with `@import("determinant")`
- **Companion file pattern**: `foo.zig` is the module root and `foo/` holds its submodules and tests, as in the Zig standard library (`std/os.zig` + `std/os/`)
- `src/` holds the entry points (`root.zig`, `main.zig`) alongside the top-level modules (`cpu.zig`, `instructions.zig`, `decoders.zig`)
- `decoders.zig` re-exports `branch`, `expand`, `registry` and `bitfields`, plus `decode` and `DecodeError`
- Each ISA extension has a companion file (`instructions/ext.zig` + `instructions/ext/tests.zig`); its tests are pulled in with a `test { _ = @import("ext/tests.zig"); }` block
- **Test hub pattern**: inside each module directory the test hub is named `tests.zig`. Test files drop the directory prefix (`cpu/atomic_test.zig`, not `cpu/cpu_atomic_test.zig`)
- Submodules are imported with `@import("file.zig")` relative to the importing file, so adding one needs no `build.zig` change
- Shared test utilities live in `instructions/test_helpers.zig`: memory helpers for any CpuType (loadInst, storeWordAt, readWordAt, storeHalfAt), encoders for every format (encodeR/I/S/B/U/J, encodeOp, encodeOpImmShift, encodeAtomic, encodeCsr), and `expectSteps()`, the table runner for one-instruction tests (`StepCase` rows: set up registers, memory and CSRs, take one step, check registers, memory, pc, cycles or the error). `decoders/branch/test_helpers.zig` has the decoder round-trip helpers
- One-instruction execute tests are rows of a `test "step: table (<file>)"` per file; scenario tests (several steps, interacting state) stay as individual tests
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- RV32C lives under `rv32i/rv32c.zig` + `rv32i/rv32c/` (accessed as `rv32i.rv32c`) because it is a decode-time front end to rv32i, not a peer extension. Compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly), and the decoder wraps that into a full `Instruction`; `rv32c.Opcode` is for decoding and display only (it is not in the `instructions.Opcode` tagged union)
