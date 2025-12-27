# Project Structure

```
src/
  root.zig                — library root; decode() = LUT primary, decodeBranch() = reference; re-exports cpu, instructions, decoders, branch_decoder
  main.zig                — CLI entry point: runDemo() (built-in program) or runFile() (load flat binary), imports the library as @import("determinant") (companion file for main/)
  main/
    test_helpers.zig      — SliceIterator (fake arg iterator for mainInner tests)
    tests.zig             — hub → disassembly, result, demo, args, file
      disassembly_test.zig      — printInstruction output for all extension families (RV32I/M/A, Zicsr, Zba/Zbb/Zbs, compressed)
      result_test.zig           — printResult: ecall/ebreak/continue, register dump, PC format, zero omission
      demo_test.zig             — runDemo deterministic output, reproducibility
      args_test.zig             — mainInner arg parsing: help, flag errors, missing/invalid --max-cycles
      file_test.zig             — runFile: empty/large/nonexistent files, successful execution, cycle limits
  cpu.zig                 — CpuType(comptime memory_size, comptime decodeFn) generic, Cpu default (64KB), step/run executor, memory helpers (companion file for cpu/)
  cpu/
    exec_i.zig            — RV32I execute logic (free function using anytype for CPU); Result enum (ecall/ebreak/continue)
    tests.zig             — hub → init, memory, pipeline, run, determinism, dispatch, boundary, store_upper, atomic, csr, invariant, integration, recovery
      init_test.zig             — init and register tests
      memory_test.zig           — memory read/write tests
      pipeline_test.zig         — pipeline infrastructure, branch/error path tests
      run_test.zig              — run() behavior (ECALL/EBREAK termination, max_cycles, unlimited, non-zero initial cycle_count)
      determinism_test.zig      — determinism: identical programs → identical state
      dispatch_test.zig         — CSR pipeline invariant, extension dispatch (MUL, SH1ADD, CLZ, BSET)
      boundary_test.zig         — boundary-value tests (overflow, sign-extension, shift masking, JALR bit[0], LHU zero-extension)
      store_upper_test.zig      — CPU-level SB, SH, LUI, AUIPC tests
      atomic_test.zig           — LR/SC scenarios, AMO operations, reservation invalidation
      csr_test.zig              — CSRRW, CSRRC, CSRRWI/CSRRSI, read-only CSR error
      invariant_test.zig        — x0 hardwired zero, wrapping ADD+CSR pipeline, C.NOP, C.ADDI dispatch
      integration_test.zig      — multi-instruction programs, realistic execution sequences
      recovery_test.zig         — error recovery: continued execution after decode/load/store errors, reservation preservation
  instructions.zig        — imports all extensions; tagged union Opcode (i | m | a | csr | zba | zbb | zbs), isCompressed(), Format re-export, Instruction (companion file for instructions/)
  instructions/
    format.zig            — Format enum (R/I/S/B/U/J), shared by all extensions
    test_helpers.zig      — shared test utilities (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers)
    rv32i.zig             — RV32I base integer opcodes (41 variants, incl. FENCE/FENCE.I), decode helpers, format(); re-exports rv32c (companion file for rv32i/)
    rv32i/
      tests.zig           — hub → decode, exec_alu, exec_mem, exec_branch, exec_jump, exec_system, boundary
        decode_test.zig         — decode round-trip tests
        exec_alu_test.zig       — ALU execute tests
        exec_mem_test.zig       — load/store execute tests (LW, SW, LB, LBU, LH, LHU, SB, SH)
        exec_branch_test.zig    — branch execute tests (BEQ, BNE, BLT, BGE, BLTU, BGEU)
        exec_jump_test.zig      — upper-immediate and jump tests (LUI, AUIPC, JAL, JALR)
        exec_system_test.zig    — system instruction tests (ECALL, EBREAK, FENCE)
        boundary_test.zig       — boundary-value tests
      rv32c.zig           — RV32C compressed instruction Opcode (26 variants), decode() (16-bit → Opcode); re-exports expand (companion file for rv32c/)
      rv32c/
        expand.zig        — expand() function: maps Opcode + halfword → Expanded (validates constraints, builds fields)
        imm.zig           — pure stateless immediate extraction helpers (10 functions) + cReg() + funct3()
        tests.zig         — hub → expand_q01, expand_q2, maxrange, imm, cpu_alu, cpu_flow, cpu_loadstore, cpu_branch, cpu_misc
          expand_q01_test.zig       — Q0+Q1 expand tests
          expand_q2_test.zig        — Q2 expand tests
          maxrange_test.zig         — max-range bit extraction tests
          imm_test.zig              — cReg mapping, funct3 extraction, immediate extraction helpers
          cpu_alu_test.zig          — C.ADD, C.SUB, C.AND, etc. CPU execution
          cpu_flow_test.zig         — C.LI, C.ADDI, C.JAL, C.JALR, C.J, mixed 16/32-bit sequence
          cpu_loadstore_test.zig    — C.LW, C.SW, C.LWSP, C.SWSP, compact register variants
          cpu_branch_test.zig       — C.BEQZ taken/not-taken, C.BNEZ taken/not-taken
          cpu_misc_test.zig         — C.MV, C.EBREAK
    rv32m.zig             — RV32M multiply/divide opcodes (8 variants), decodeR(), execute(), format() (companion file for rv32m/)
    rv32m/
      tests.zig           — hub → mul_test.zig, div_test.zig
        mul_test.zig            — multiply tests
        div_test.zig            — divide tests
    rv32a.zig             — RV32A atomic opcodes (11 variants), decodeR(), execute(), format() (companion file for rv32a/)
    rv32a/
      tests.zig           — hub → decode_lrsc_test.zig, amo_test.zig
        decode_lrsc_test.zig    — LR/SC decode tests
        amo_test.zig            — AMO decode + execute tests
    zicsr.zig             — Zicsr CSR opcodes (6 variants), decodeSystem(), format(), Csr struct with read/write/execute (companion file for zicsr/)
    zicsr/
      tests.zig           — hub → decode_exec_test.zig, counter_error_test.zig
        decode_exec_test.zig    — CSR decode + execute tests
        counter_error_test.zig  — CSR counter and error path tests
    zba.zig               — Zba address-generation opcodes (3 variants: SH1ADD, SH2ADD, SH3ADD), decodeR(), execute() (companion file for zba/)
    zba/
      tests.zig           — Zba decode + execute tests
    zbb.zig               — Zbb basic bit-manipulation opcodes (18 variants), decodeR(), decodeIAlu(), execute() (companion file for zbb/)
    zbb/
      tests.zig           — hub → arith_test.zig, bitcount_test.zig, sext_test.zig, rotate_test.zig
        arith_test.zig          — ANDN, ORN, XNOR, MAX, MIN tests
        bitcount_test.zig       — decode + CLZ/CTZ/CPOP tests
        sext_test.zig           — SEXT_B/SEXT_H/ZEXT_H execute tests
        rotate_test.zig         — ROL/ROR/RORI tests
    zbs.zig               — Zbs single-bit opcodes (8 variants), decodeR(), decodeIAlu(), execute() (companion file for zbs/)
    zbs/
      tests.zig           — hub → decode_exec_test.zig, boundary_test.zig
        decode_exec_test.zig    — decode + execute tests
        boundary_test.zig       — boundary-value tests
  decoders.zig            — namespace for decoders/; re-exports branch, lut, expand, registry, bitfields; canonical DecodeError with comptime divergence assertion (companion file for decoders/)
  decoders/
    bitfields.zig         — shared bit-field extraction (opcode7, rd, rs1, rs2, funct3/5/7/12, immI/S/B/U/J)
    bitfields_test.zig    — standalone bit-field extraction tests (register fields, immediate extractors)
    expand.zig            — shared expandCompressed(): wraps rv32c.Expanded → Instruction (used by both decoders)
    registry.zig          — opcode registry: Entry struct, 95-entry registry array, Strategy enum, strategyFor()
    conformance_test.zig  — conformance suite (field-by-field match vs branch decoder)
    rv32c_cross_test.zig  — cross-validation hub: Q2 + max-range tests; imports rv32c_cross_q01_test.zig for Q0+Q1
    rv32c_cross_q01_test.zig — Q0+Q1 cross-validation tests
    branch.zig            — reference decoder: branch-based dispatch to extension decoders (companion file for branch/)
    branch/
      test_helpers.zig    — shared branch decoder test helpers (expectRoundTripI/S/B/U/Csr)
      tests.zig           — hub → rtype, alu, shift, load_store, branch, jump, atomic, system, edge
        rtype_test.zig          — R-type round-trip tests (RV32I, M, Zba, Zbb, Zbs)
        alu_test.zig            — I-type ALU round-trip tests (ADDI, SLTI, XORI, ORI, SLTIU, ANDI)
        shift_test.zig          — shift instruction round-trip tests
        load_store_test.zig     — load/store round-trip tests (LB, LW, SB, SH, SW)
        branch_test.zig         — B-type branch round-trip tests (BEQ, BNE, BLT, BGE, BLTU, BGEU)
        jump_test.zig           — U/J-type and JALR round-trip tests (LUI, AUIPC, JAL, JALR)
        atomic_test.zig         — RV32A atomic round-trip tests (all 11 opcodes)
        system_test.zig         — CSR and FENCE round-trip tests
        edge_test.zig           — edge cases, invalid encodings, load variants, ZEXT_H, operand isolation
    lut.zig               — primary decoder: comptime LUT tables (level1 strategy → format-specific tables) derived from registry.zig (companion file for lut/)
    lut/
      test_helpers.zig    — shared LUT test encoding helpers and assertion utilities
      tests.zig           — hub → rtype, ialu, load_store_branch, jump, system, operand, edge
        rtype_test.zig          — R-type LUT tests (base, M, Zba, Zbb, Zbs)
        ialu_test.zig           — I-type ALU LUT tests (shifts, Zbb, Zbs)
        load_store_branch_test.zig — load/store/branch valid+invalid LUT tests
        jump_test.zig           — LUI/AUIPC, JAL, JALR LUT tests
        system_test.zig         — atomic/system/FENCE/misc LUT tests
        operand_test.zig        — R-format operand field extraction and isolation tests
        edge_test.zig           — edge cases: invalid encodings, operand isolation, zero instruction
  compliance.zig            — RISC-V compliance tests companion file (imports compliance/tests.zig)
  compliance/
    runner.zig              — ComplianceCpu (256KB, LUT decoder), runTest(), expectPass()
    tests.zig               — hub → rv32ui, rv32um, rv32ua, rv32uc, rv32uzba, rv32uzbb, rv32uzbs
      rv32ui_test.zig       — RV32I base integer tests (~39 tests)
      rv32um_test.zig       — RV32M multiply/divide tests (8 tests)
      rv32ua_test.zig       — RV32A atomic tests (10 tests)
      rv32uc_test.zig       — RV32C compressed test (1 test)
      rv32uzba_test.zig     — Zba address generation tests (3 tests)
      rv32uzbb_test.zig     — Zbb bit manipulation tests (18 tests)
      rv32uzbs_test.zig     — Zbs single-bit tests (8 tests)
    bin/                    — pre-compiled flat binaries from riscv-tests (checked in)
      rv32ui/               — RV32I test binaries (add.bin, sub.bin, ...)
      rv32um/               — RV32M test binaries (mul.bin, div.bin, ...)
      rv32ua/               — RV32A test binaries (amoadd_w.bin, lrsc.bin, ...)
      rv32uc/               — RV32C test binary (rvc.bin)
      rv32uzba/             — Zba test binaries (sh1add.bin, ...)
      rv32uzbb/             — Zbb test binaries (clz.bin, cpop.bin, ...)
      rv32uzbs/             — Zbs test binaries (bclr.bin, bext.bin, ...)
tests/
  riscv-tests/
    riscv-tests-src/        — git submodule (riscv-software-src/riscv-tests)
    env/determinant/
      riscv_test.h          — custom test environment (user-mode, EBREAK termination)
      link.ld               — custom linker script (origin at 0x0)
    Makefile                — builds flat binaries from riscv-tests sources
    README.md               — rebuild instructions and toolchain setup
build.zig                 — build system configuration (library module, executable, test, test-compliance, and test-all steps)
build.zig.zon             — package metadata (name, version, dependencies, fingerprint)
```

## Module Dependencies

All edges point downward — no cycles exist and none should be introduced.

```
main.zig ─→ root.zig ─→ cpu.zig ─→ instructions.zig ─→ [extensions] ─→ format.zig
                       ↘ decoders.zig ─→ lut / branch
                                      ↘ bitfields.zig, expand.zig, registry.zig
```

- `cpu.zig` is the companion file; `cpu/exec_i.zig` handles RV32I execute logic (no upward dependency)
- `compliance.zig` imports the `determinant` library module (not relative paths) — it's a separate test module, not part of the library
- Extensions (rv32i, rv32m, rv32a, zicsr, zba, zbb, zbs) import only `format.zig` — never cpu, decoders, or instructions
- RV32C imports only `rv32i.zig` and `format.zig` (decode-time frontend, no upward dependency)
- `rv32c/expand.zig` imports `rv32c.zig`, `rv32i.zig`, and `imm.zig` — no upward dependency
- `rv32c/imm.zig` has zero dependencies (pure stateless helpers)

## Module Conventions

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- **Companion file pattern**: `foo.zig` is the module root, `foo/` holds submodules and tests. This mirrors the Zig standard library convention (`std/os.zig` + `std/os/`). No pure hub-only files.
- `src/` holds entry points (`root.zig`, `main.zig`) alongside the top-level modules (`cpu.zig`, `instructions.zig`, `decoders.zig`)
- `decoders.zig` re-exports `branch`, `lut`, `expand`, `registry`, `bitfields`
- Each ISA extension has a companion file (`instructions/ext.zig` + `instructions/ext/tests.zig`); tests are pulled in via `test { _ = @import("ext/tests.zig"); }` blocks
- **Test hub pattern**: inside each module directory, the test hub is always named `tests.zig`. Semantic test files drop the directory prefix (e.g., `cpu/boundary_test.zig` not `cpu/cpu_boundary_test.zig`)
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Shared test utilities live in `instructions/test_helpers.zig` (loadInst, storeWordAt, readWordAt, storeHalfAt, encode helpers for all formats)
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- RV32C lives under `rv32i/rv32c.zig` + `rv32i/rv32c/` (accessed as `rv32i.rv32c`) because it's a decode-time front-end to rv32i, not an independent peer extension. Compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `instructions.Opcode` tagged union)
