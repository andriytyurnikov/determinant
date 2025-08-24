# Project Structure

```
src/
  root.zig                — library root; decode() = LUT primary, decodeBranch() = reference; re-exports cpu, instructions, decoders, branch_decoder
  main.zig                — CLI entry point: runDemo() (built-in program) or runFile() (load flat binary), imports the library as @import("determinant")
  vm.zig                  — namespace hub for vm/ directory; re-exports cpu, instructions, decoders
  vm/
    cpu.zig               — CpuType(comptime memory_size: u32, comptime decodeFn: DecodeFn) generic, Cpu = CpuType(default_memory_size, default_decode) default (64KB via -Dmemory_size), step/run executor, memory helpers
    cpu_init_test.zig     — init and register tests
    cpu_memory_test.zig   — memory read/write tests
    cpu_pipeline_test.zig — pipeline infrastructure, run(), branch/error path tests
    cpu_determinism_test.zig — determinism: identical programs → identical state
    cpu_boundary_test.zig — boundary-value tests
    cpu_integration_test.zig — integration tests (extension dispatch, compressed instructions)
    instructions.zig      — imports all extensions; tagged union Opcode (i | m | a | csr | zba | zbb | zbs), isCompressed(), Format re-export, Instruction
    decoders.zig          — namespace hub for decoders/; re-exports branch_decoder, lut_decoder, expand, registry, bitfields; canonical DecodeError with comptime divergence assertion
    decoders/
      bitfields.zig           — shared bit-field extraction (opcode7, rd, rs1, rs2, funct3/5/7/12, immI/S/B/U/J)
      expand.zig              — shared expandCompressed(): wraps rv32c.Expanded → Instruction (used by both decoders)
      registry.zig            — opcode registry: Entry struct, 95-entry registry array, Strategy enum, strategyFor()
      lut_conformance_test.zig — conformance suite (field-by-field match vs branch_decoder)
      rv32c_cross_test.zig    — cross-validation hub: Q2 + max-range tests; imports rv32c_cross_q01_test.zig for Q0+Q1
        rv32c_cross_q01_test.zig — Q0+Q1 cross-validation tests
      branch_decoder/
        branch_decoder.zig      — reference decoder: branch-based dispatch to extension decoders; wraps rv32c.Expanded → Instruction
        branch_decoder_test.zig — hub → rtype, itype, shift, uj, edge split files
          branch_decoder_rtype_test.zig  — R-type round-trip tests (RV32I, M, Zba, Zbb, Zbs)
          branch_decoder_itype_test.zig  — I-type round-trip tests (ALU, loads, CSR, system)
          branch_decoder_shift_test.zig  — shift instruction round-trip tests
          branch_decoder_uj_test.zig     — U/J-type and store round-trip tests
          branch_decoder_edge_test.zig   — edge cases, error paths, FENCE, atomics
      lut_decoder/
        lut_decoder.zig         — primary decoder: comptime LUT tables (level1 strategy → format-specific tables) derived from registry.zig
        lut_decoder_test.zig    — hub → rtype, ialu, mem, system split files
          lut_decoder_rtype_test.zig   — R-type LUT tests (base, M, Zba, Zbb, Zbs)
          lut_decoder_ialu_test.zig    — I-type ALU LUT tests (shifts, Zbb, Zbs)
          lut_decoder_mem_test.zig     — load/store/branch/U/J/FENCE LUT tests
          lut_decoder_system_test.zig  — atomic/system/misc LUT tests
        lut_test_helpers.zig    — shared LUT test encoding helpers and assertion utilities
    instructions/
      format.zig          — Format enum (R/I/S/B/U/J), shared by all extensions
      test_helpers.zig    — shared test utilities (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
      rv32i/
        rv32i.zig         — RV32I base integer opcodes (41 variants, incl. FENCE/FENCE.I), decode helpers, format(); re-exports rv32c
        rv32i_test.zig    — hub → decode, exec_alu, exec_mem, boundary split files
        rv32c/
          rv32c.zig       — RV32C compressed instruction Opcode (26 variants), decode(), expand() (16-bit → Expanded); imports rv32i and format only
          rv32c_test.zig  — hub → rv32c_expand_q01_test, rv32c_expand_q2_test, rv32c_maxrange_test, rv32c_cpu_test, rv32c_cpu_alu_test
      rv32m/
        rv32m.zig         — RV32M multiply/divide opcodes (8 variants), decodeR(), execute(), format()
        rv32m_test.zig    — hub → rv32m_mul_test.zig, rv32m_div_test.zig
      rv32a/
        rv32a.zig         — RV32A atomic opcodes (11 variants), decodeR(), execute(), format()
        rv32a_test.zig    — hub → rv32a_decode_lrsc_test.zig, rv32a_amo_test.zig
      zicsr/
        zicsr.zig         — Zicsr CSR opcodes (6 variants), decodeSystem(), format(), Csr struct with read/write/execute
        zicsr_test.zig    — hub → zicsr_decode_exec_test.zig, zicsr_counter_error_test.zig
      zba/
        zba.zig           — Zba address-generation opcodes (3 variants: SH1ADD, SH2ADD, SH3ADD), decodeR(), execute()
        zba_test.zig      — Zba decode + execute tests
      zbb/
        zbb.zig           — Zbb basic bit-manipulation opcodes (18 variants), decodeR(), decodeIAlu(), execute()
        zbb_test.zig      — hub → zbb_arith_test.zig, zbb_bitcount_test.zig, zbb_rotate_test.zig
          zbb_bitcount_test.zig — decode + CLZ/CTZ/CPOP tests; imports zbb_sext_test.zig
          zbb_sext_test.zig     — SEXT_B/SEXT_H/ZEXT_H execute tests
      zbs/
        zbs.zig           — Zbs single-bit opcodes (8 variants), decodeR(), decodeIAlu(), execute()
        zbs_test.zig      — hub → zbs_decode_exec_test.zig, zbs_boundary_test.zig
build.zig                 — build system configuration (library module, executable, test and run steps)
build.zig.zon             — package metadata (name, version, dependencies, fingerprint)
```

## Module Conventions

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- `src/` holds entry points (`root.zig`, `main.zig`); `src/vm/` holds the VM library implementation
- `vm.zig` is the namespace hub for the `vm/` directory module — `root.zig` imports it via `@import("vm.zig")` and re-exports `cpu`, `instructions`, `decoders`
- `decoders.zig` is the namespace hub for the `decoders/` directory — re-exports `branch_decoder`, `lut_decoder`, `expand`, `registry`, `bitfields`
- Each ISA extension owns a subdirectory (`ext/ext.zig` + `ext/ext_test.zig`); tests are pulled in via `test { _ = @import("ext_test.zig"); }` blocks
- **Test hub pattern**: large test files are split into semantic groups under a 250-line hard limit. The original `*_test.zig` becomes a hub with only `comptime { _ = @import("split_test.zig"); }` blocks — source files keep their single `@import("..._test.zig")` unchanged
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Shared test utilities live in `test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers for all formats)
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- RV32C lives under `rv32i/rv32c/` (accessed as `rv32i.rv32c`) because it's a decode-time front-end to rv32i, not an independent peer extension. Compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `instructions.Opcode` tagged union)
