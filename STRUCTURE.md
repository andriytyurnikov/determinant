# Project Structure

```
src/
  root.zig                — library root; re-exports cpu, instructions, decoders, decode(), DecodeError, CpuType/Cpu and the common types
  main.zig                — CLI entry point: run() maps the outcome to an exit status (ExitStatus) and flushes output; runDemo() (built-in program) or runFile() (load flat binary); imports the library as @import("determinant") (companion file for main/)
  main/
    tests.zig             — hub → disassembly, result, demo, args, file, dump, exit, program
      disassembly_test.zig      — printInstruction output for all extension families (RV32I/M/A, Zicsr, Zba/Zbb/Zbs, compressed)
      result_test.zig           — printResult: ecall/ebreak/continue, register dump, PC format, zero omission
      demo_test.zig             — runDemo deterministic output, reproducibility
      args_test.zig             — mainInner arg parsing: help, flag errors, missing/invalid --max-cycles
      file_test.zig             — runFile: empty/large/nonexistent files, successful execution, cycle limits
      dump_test.zig             — dumpMemory: hexdump and raw format output
      exit_test.zig             — run(): every exit status (0/1/2/3), unwritable stdout, stdio writers append
      program_test.zig          — host calls and --input, guest exit status, ELF loading, --load-addr, initial sp
  hostcall.zig            — host-call ABI: handle() performs the read/write/exit ECALL that stopped run() (docs/design/host-calls.md)
  hostcall_test.zig       — each call, its error codes, reservations, an echo program end to end
  loader.zig              — ELF32 RISC-V executable loader: loadElf(), isElf() (docs/design/program-loading.md)
  loader_test.zig         — segments and .bss, entry point, every rejection leaves the VM unchanged
  cpu.zig                 — CpuType(comptime memory_size, comptime options) generic (Options: decoder, decode cache size), Cpu default (follows -Dmemory_size), TestCpu (fixed 64 KiB, for unit tests), init/reset, step/run executor, memory helpers (companion file for cpu/)
  cpu/
    exec_i.zig            — RV32I execute logic (free function using anytype for CPU); Result enum (ecall/ebreak/continue)
    state.zig             — canonical little-endian state encoding (versioned header + memory) and its SHA-256 digest
    tests.zig             — hub → init, memory, pipeline, run, determinism, atomic, csr, invariant, integration, recovery, state, decode_cache, fault, csr_table, aliasing, wraparound, host_api
      init_test.zig             — init and register tests
      memory_test.zig           — memory read/write tests
      pipeline_test.zig         — pipeline infrastructure: cycle counting, multi-instruction sequences, branch/jump targets beyond memory
      run_test.zig              — run() behavior (ECALL/EBREAK termination, max_cycles, unlimited, non-zero initial cycle_count)
      determinism_test.zig      — determinism: identical programs → identical state
      atomic_test.zig           — LR/SC scenarios, AMO operations, reservation invalidation
      csr_test.zig              — CSRRW, CSRRC, CSRRWI/CSRRSI, read-only CSR error
      invariant_test.zig        — x0 hardwired zero, wrapping ADD+CSR pipeline, C.NOP, C.ADDI dispatch
      integration_test.zig      — multi-instruction programs, realistic execution sequences
      recovery_test.zig         — error recovery: continued execution after decode/load/store errors, reservation preservation
      state_test.zig            — state encoding layout, fixed power-on digest, every field affects the digest
      decode_cache_test.zig     — decode cache: self-modifying code, host writes, slot sharing, hit counts, size never changes results
      fault_test.zig            — precise faults: a table of every fault kind, each leaving the full state digest unchanged
      csr_table_test.zig        — all 4096 CSR numbers × 6 CSR instructions × rd/source, against a model of SEMANTICS.md
      aliasing_test.zig         — rd = rs1/rs2 for loads, AMOs, LR/SC, CSRRW, JALR (sources read before execution)
      wraparound_test.zig       — address, branch, JALR and AUIPC arithmetic wraps modulo 2^32
      host_api_test.zig         — StepError set, describeFault(), runFor(), stop_pc
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
  decoders.zig            — namespace for decoders/: decode() (= branch.decode), DecodeError; re-exports branch, expand, registry, bitfields (companion file for decoders/)
  decoders/
    bitfields.zig         — shared bit-field extraction (opcode7, rd, rs1, rs2, funct3/5/7/12, immI/S/B/U/J)
    bitfields_test.zig    — standalone bit-field extraction tests (register fields, immediate extractors)
    expand.zig            — expandCompressed(): wraps rv32c.Expanded → Instruction
    registry.zig          — opcode registry: the specification of every 32-bit encoding (Entry with mask()/match(), 95 entries, lookup(), instruction())
    registry_test.zig     — decoder vs. registry: no overlaps, one entry per Opcode, random operands, sweep of all identifying fields
    rv32c_cross_test.zig  — cross-validation hub: Q2 + max-range tests; imports rv32c_cross_q01_test.zig for Q0+Q1
    rv32c_cross_q01_test.zig — Q0+Q1 cross-validation tests
    branch.zig            — the decoder: switch on opcode, then extension decoders by funct3/funct7 (companion file for branch/)
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
  compliance.zig            — RISC-V compliance tests companion file (imports compliance/tests.zig)
  compliance/
    runner.zig              — ComplianceCpu (256KB), runTest(), expectPass()
    tests.zig               — hub → rv32ui, rv32um, rv32ua, rv32uc, rv32uzba, rv32uzbb, rv32uzbs
      rv32ui_test.zig       — RV32I base integer tests (41 tests, including fence_i)
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
tools/
  verify_decoder.zig      — decoder vs. opcode registry on all 2^30 32-bit encodings (`zig build verify-decoder`)
  bench.zig               — benchmark: best-of-N time and MIPS per C corpus program, geometric mean (`zig build bench`)
  corpus_digests.zig      — runs every corpus program (compliance binaries and C programs) and prints/checks final-state digests and C program results (`zig build digests` / `test-digests`)
tests/
  digests.txt             — golden final-state digests of the corpus; every CI configuration must match it
  programs/               — C program corpus (see tests/programs/README.md)
    src/                  — freestanding C programs, crt0.S, link.ld, libmini.c, native_main.c
    bin/<config>/         — checked-in flat binaries built by `zig build programs` (imac_zb-O2, ima-Os)
    expected/             — results of the same C run natively
    elf/crc32.elf         — one ELF executable from the same build, for the ELF-loading test
docs/
  design/                 — design notes: host-calls.md, snapshots.md, program-loading.md, memory-protection.md
  riscv-tests/
    riscv-tests-src/        — git submodule (riscv-software-src/riscv-tests)
    env/determinant/
      riscv_test.h          — custom test environment (user-mode, EBREAK termination)
      link.ld               — custom linker script (origin at 0x0)
    Makefile                — builds flat binaries from riscv-tests sources
    README.md               — rebuild instructions and toolchain setup
build.zig                 — build system configuration (library module, executable, test, test-compliance, test-digests, test-all, verify-decoder, bench and programs steps)
build.zig.zon             — package metadata (name, version, dependencies, fingerprint)
README.md                 — overview, CLI, program contract, public API
SEMANTICS.md              — execution semantics: the contract (ISA subset, decoding, faults, LR/SC, CSRs, determinism)
CHANGELOG.md              — release notes; guest-visible semantic changes listed first
THIRD_PARTY_NOTICES.md    — licenses of material derived from riscv-tests and Zig compiler-rt
STRUCTURE.md              — this file
CLAUDE.md                 — guidance for working on the code (invariants, patterns, traps)
```

## Module Dependencies

All edges point downward — no cycles exist and none should be introduced.

```
main.zig ─→ root.zig ─→ hostcall.zig, loader.zig (generic over CpuType: no imports of cpu.zig)
                │
main.zig ─→ root.zig ─→ cpu.zig ─→ instructions.zig ─→ [extensions] ─→ format.zig
                │          ↓
                └──→ decoders.zig ─→ branch.zig ─→ bitfields.zig, expand.zig
                                  ↘ registry.zig ─→ bitfields.zig
```

- `cpu.zig` imports `decoders.zig` (the default decoder for `Options.decode`, and `DecodeError`); `cpu/exec_i.zig` handles RV32I execute logic and `cpu/state.zig` the state encoding (no upward dependency)
- `compliance.zig` and the programs in `tools/` import the `determinant` library module (not relative paths) — they are separate modules, not part of the library
- Extensions (rv32i, rv32m, rv32a, zicsr, zba, zbb, zbs) import only `format.zig` — never cpu, decoders, or instructions. This holds for their non-test files; their tests may import cpu.zig, the decoder and `instructions/test_helpers.zig`
- RV32C imports only `rv32i.zig` and `format.zig` (decode-time frontend, no upward dependency)
- `rv32c/expand.zig` imports `rv32c.zig`, `rv32i.zig`, and `imm.zig` — no upward dependency
- `rv32c/imm.zig` has zero dependencies (pure stateless helpers)

## Module Conventions

- The library module is named `"determinant"` — CLI imports it via `@import("determinant")`
- **Companion file pattern**: `foo.zig` is the module root, `foo/` holds submodules and tests. This mirrors the Zig standard library convention (`std/os.zig` + `std/os/`). No pure hub-only files.
- `src/` holds entry points (`root.zig`, `main.zig`) alongside the top-level modules (`cpu.zig`, `instructions.zig`, `decoders.zig`)
- `decoders.zig` re-exports `branch`, `expand`, `registry`, `bitfields`, plus `decode` and `DecodeError`
- Each ISA extension has a companion file (`instructions/ext.zig` + `instructions/ext/tests.zig`); tests are pulled in via `test { _ = @import("ext/tests.zig"); }` blocks
- **Test hub pattern**: inside each module directory, the test hub is always named `tests.zig`. Semantic test files drop the directory prefix (e.g., `cpu/boundary_test.zig` not `cpu/cpu_boundary_test.zig`)
- Submodules are resolved via `@import("file.zig")` relative to the importing file — no `build.zig` changes needed
- Shared test utilities live in `instructions/test_helpers.zig`: memory helpers for any CpuType (loadInst, storeWordAt, readWordAt, storeHalfAt), encoders for every format (encodeR/I/S/B/U/J, encodeOp, encodeOpImmShift, encodeAtomic, encodeCsr), and `expectSteps()`, the table runner for one-instruction tests (`StepCase` rows: setup registers/memory/CSRs, one step, expected registers/memory/pc/cycles/errors). `decoders/branch/test_helpers.zig` has the decoder round-trip helpers
- One-instruction execute tests are rows of a `test "step: table (<file>)"` per file; scenario tests (several steps, interacting state) stay as individual tests
- Build artifacts go to `.zig-cache/` and `zig-out/` (gitignored)
- RV32C lives under `rv32i/rv32c.zig` + `rv32i/rv32c/` (accessed as `rv32i.rv32c`) because it's a decode-time front-end to rv32i, not an independent peer extension. Compressed instructions expand to `rv32c.Expanded` (using `rv32i.Opcode` directly); the decoder wraps this into a full `Instruction` — `rv32c.Opcode` is for decode/display only (not in the `instructions.Opcode` tagged union)
