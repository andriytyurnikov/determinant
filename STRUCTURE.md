# Project Structure

```
src/
  root.zig                — library root, re-exports all submodules and convenience aliases
  main.zig                — CLI entry point, imports the library as @import("determinant")
  vm.zig                  — namespace hub for vm/ directory; re-exports cpu, instructions, decoder, comptime_lut
  vm/
    cpu.zig               — Cpu struct: registers, PC, 1 MB memory, step/run executor, memory helpers
    cpu_test.zig          — pipeline infrastructure tests (init, fetch, memory, run)
    bitfields.zig         — shared bit-field extraction (rd, rs1, rs2, funct3/5/7/12, immI/S/B/U/J)
    registry.zig          — opcode registry: Entry struct, 94-entry registry array, Strategy enum, strategyFor()
    comptime_lut.zig      — primary decoder: comptime LUT tables (level1 strategy → format-specific tables) derived from registry.zig
    comptime_lut_test.zig — LUT unit tests + conformance suite (field-by-field match vs decoder.zig)
    decoder.zig           — reference decoder: branch-based dispatch to extension decoders; wraps rv32c.Expanded → Instruction
    decoder_test.zig      — encode/decode round-trip tests for all instruction formats
    instructions.zig      — imports all extensions; tagged union Opcode (i | m | a | csr | zba | zbb | zbs), isCompressed(), Format re-export, Instruction
    rv32c_cross_test.zig  — cross-validation: rv32c.Expanded vs decoder.decode() Instruction equivalence
    instructions/
      format.zig          — Format enum (R/I/S/B/U/J), shared by all extensions
      test_helpers.zig    — shared test utilities (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
      rv32i/
        rv32i.zig         — RV32I base integer opcodes (40 variants, incl. FENCE), decode helpers, format(); re-exports rv32c
        rv32i_test.zig    — RV32I decode + execute tests
        rv32c/
          rv32c.zig       — RV32C compressed instruction Opcode (26 variants), decode(), expand() (16-bit → Expanded); imports rv32i and format only
          rv32c_test.zig  — RV32C expansion + CPU step tests
      rv32m/
        rv32m.zig         — RV32M multiply/divide opcodes (8 variants), decodeR(), execute(), format()
        rv32m_test.zig    — RV32M decode + execute tests
      rv32a/
        rv32a.zig         — RV32A atomic opcodes (11 variants), decodeR(), execute(), format()
        rv32a_test.zig    — RV32A decode + execute tests
      zicsr/
        zicsr.zig         — Zicsr CSR opcodes (6 variants), decodeSystem(), format(), Csr struct with read/write/execute
        zicsr_test.zig    — Zicsr decode + execute tests
      zba/
        zba.zig           — Zba address-generation opcodes (3 variants: SH1ADD, SH2ADD, SH3ADD), decodeR(), execute()
        zba_test.zig      — Zba decode + execute tests
      zbb/
        zbb.zig           — Zbb basic bit-manipulation opcodes (18 variants), decodeR(), decodeIAlu(), execute()
        zbb_test.zig      — Zbb decode + execute tests
      zbs/
        zbs.zig           — Zbs single-bit opcodes (8 variants), decodeR(), decodeIAlu(), execute()
        zbs_test.zig      — Zbs decode + execute tests
build.zig                 — build system configuration (library module, executable, test and run steps)
build.zig.zon             — package metadata (name, version, dependencies, fingerprint)
```

## Module Conventions

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- `src/` holds entry points (`root.zig`, `main.zig`); `src/vm/` holds the VM library implementation
- `vm.zig` is the namespace hub for the `vm/` directory module — `root.zig` imports it via `@import("vm.zig")` and re-exports `cpu`, `instructions`, `decoder`, `registry`
- Each ISA extension owns a subdirectory (`ext/ext.zig` + `ext/ext_test.zig`); tests are pulled in via `test { _ = @import("ext_test.zig"); }` blocks
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Shared test utilities live in `test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers for all formats)
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- RV32C lives under `rv32i/rv32c/` (accessed as `rv32i.rv32c`) because it's a decode-time front-end to rv32i, not an independent peer extension. Compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `instructions.Opcode` tagged union)
