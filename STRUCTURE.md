# Project Structure

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

## Module Conventions

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- `src/` holds entry points (`root.zig`, `main.zig`); `src/vm/` holds the VM library implementation
- `vm.zig` is the namespace hub for the `vm/` directory module — `root.zig` imports it via `@import("vm.zig")` and re-exports `cpu`, `instruction`, `decoder`
- Tests live in dedicated `*_test.zig` companion files, pulled in via `test { _ = @import("foo_test.zig"); }` blocks
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Shared test utilities live in `test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers for all formats)
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- ISA extensions live in `src/vm/instruction/` — each owns its own `Opcode` enum, decode, and execute logic
- RV32C compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `Opcode` tagged union)
