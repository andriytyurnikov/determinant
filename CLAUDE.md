# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Determinant — a deterministic RISC-V VM. Written in Zig 0.16.0, structured as both a library and CLI executable. See `README.md` for public API, [STRUCTURE.md](STRUCTURE.md) for file tree and module conventions.

## Build Commands

- `zig build` — compile the project (output in `zig-out/`)
- `zig build run` — build and run the CLI executable
- `zig build test` — run the unit tests (library) and CLI tests (executable)
- `zig build test-compliance` — run the riscv-tests compliance suite
- `zig build test-all` — run unit, CLI, compliance and digest tests (what CI runs)
- `zig build test-digests` — run the corpus (compliance binaries and the C programs in `tests/programs`), check each C program's result against a native run, and check every final-state digest against `tests/digests.txt`; `zig build digests > tests/digests.txt` regenerates it after an intended change in guest-visible behavior (review the diff)
- `zig build bench` — benchmark the VM on the C corpus (always ReleaseFast; `-- --runs N`); measure before and after any change to the step loop or decoder
- `zig build programs` — rebuild the C corpus binaries and their expected results with Zig's C compiler (see `tests/programs/README.md`)
- `zig build verify-decoder` — check the decoder against the opcode registry on all 2^30 32-bit encodings (always ReleaseFast, ~10 s); run it after any decoder or registry change
- `zig build run -- <args>` — pass arguments to the executable
- `-Dmemory_size=N` — VM memory size in bytes for the CLI and the `Cpu` alias (default: `65536`). Must be >= 4 and divisible by 4; build.zig rejects other values. Unit tests use the fixed 64 KiB `TestCpu` and compliance tests a fixed 256 KiB CPU, so only the CLI tests depend on it (they skip explicitly when a program does not fit). Example: `zig build run -Dmemory_size=1048576`
- `zig fmt src/` — format all source files (run after editing)

## Determinism Invariants

These are load-bearing constraints — violating any one breaks deterministic execution:

- **Wrapping arithmetic everywhere** — all VM arithmetic uses `+%`, `-%`, `*%` (wrapping operators). Zig's default `+`, `-`, `*` panic on overflow in debug mode and are undefined in release. Every ADD, SUB, address calculation, and PC update must wrap.
- **Explicit little-endian** — every `std.mem.readInt`/`writeInt` call uses `.little`. Never `.native` or `.big`. Never use `std.mem.sliceAsBytes` on typed arrays — it reinterprets in native byte order. See "Endianness" in Traps to Avoid.
- **No allocators in core VM** — all state is fixed-size (registers, memory array, CSR struct). Zero allocation failure modes.
- **No floating-point** — intentional; FP non-determinism (rounding modes, NaN payloads) is avoided entirely.
- **Single-hart** — no threading, FENCE/FENCE.I are no-ops.

## Pipeline Invariant

The `step()` method in `cpu.zig` follows a strict order that is **load-bearing**:

1. `fetch()` — read raw instruction bits at current PC
2. `decode()` — parse into Instruction struct
3. read rs1, rs2 — register reads happen BEFORE execution
4. execute — modify registers/memory (may update next_pc for branches/jumps)
5. update PC — written AFTER execution so branches see the old PC
6. increment cycle — AFTER everything, so CSR reads of cycle see the pre-step count

Reordering any of these breaks correctness. CSR cycle reads would be off-by-one; branches would compute wrong targets.

## Key Patterns

See [STRUCTURE.md](STRUCTURE.md) for file locations, module hierarchy, and naming conventions.

### ISA Extension Architecture

- Each extension has its own `Opcode` enum with `name()`, `format()`, and comptime `meta()` methods, plus decode and execute logic
- `instructions.zig` imports all execution extensions; composes `Opcode = union(enum) { i: rv32i.Opcode, m: rv32m.Opcode, a: rv32a.Opcode, csr: zicsr.Opcode, zba: zba.Opcode, zbb: zbb.Opcode, zbs: zbs.Opcode }` (rv32c is accessed via `rv32i.rv32c`, not directly from instructions.zig)
- `instructions.Opcode` delegates `name()` and `format()` to extensions via `inline else`
- CPU dispatch methods named after tagged union fields: `executeI`, `executeM`, `executeA`, `executeCsr`, `executeZba`, `executeZbb`, `executeZbs`
- Each extension's execution is delegated: `cpu_exec_i.executeI()` (RV32I in cpu/exec_i.zig), `rv32m.execute()`, `rv32a.execute()`, `zicsr.Csr.execute()`, `zba.execute()`, `zbb.execute()`, `zbs.execute()`

### Comptime Metadata System

- `format.zig` owns `Format` enum (R/I/S/B/U/J), `Meta` struct (`name_str` + `fmt`), and generic `opcodeName`/`opcodeFormat` helpers
- Extensions import format.zig as `fmt` and provide `pub fn meta(comptime self: Opcode) fmt.Meta` — this compiles to a perfect dispatch table with zero runtime cost via `inline else`
- `rv32a.zig` uses explicit name strings in `meta()` for dot notation (`"LR.W"`, `"AMOSWAP.W"`) — other extensions use `@tagName(self)` directly
- `rv32c.zig` uses a comptime `dotName` transform (`C_LW` → `"C.LW"`) for its own naming convention

### Compressed Instructions (RV32C)

- RV32C is a decode-time front-end to rv32i, not an independent extension — it imports only `rv32i.zig` and `format.zig` (no upward dependency on `instructions.zig`)
- `rv32c.zig` has its own `Opcode` enum (26 variants) for decode/display purposes — NOT part of the `instructions.Opcode` tagged union (no execution path, no format)
- `expand()` (in `rv32c/expand.zig`, re-exported by `rv32c.zig`) returns `rv32c.Expanded` (struct with `op: rv32i.Opcode`, register fields, imm) — the decoder wraps this into a full `Instruction` with `.op = .{ .i = exp.op }` via `expandCompressed()` in `decoders/expand.zig`
- `decode()` identifies the opcode; `expand()` validates constraints and builds the `Expanded` — keep identification and validation separate
- Immediate extraction helpers live in `rv32c/imm.zig` — pure stateless functions with no dependencies
- Some compressed instructions encode reserved values (e.g., C.ADDI4SPN with nzuimm=0, C.LUI with imm=0) that must be rejected as `IllegalInstruction` in `expand()`
- `instructions.isCompressed(raw)` is the single source of truth for 16-bit vs 32-bit detection — used by decoders/branch.zig, cpu.zig, and main.zig

### Decoder

- One decoder: `decoders/branch.zig`, exported as `decode()` from `decoders.zig` and `root.zig`. It switches on opcode[6:0], then asks each extension's `decodeR()`/`decodeIAlu()`/... by funct3/funct7 (and rs2 where an instruction fixes it)
- `CpuType(comptime memory_size: u32, comptime decodeFn: DecodeFn)` — the decoder is a comptime parameter (default `decoders.decode`), no runtime dispatch. `DecodeFn = *const fn (u32) DecodeError!Instruction`
- Sub-decoders use semantic names matching their rv32i counterparts: `decodeStore`, `decodeBranch`, `decodeLoad`, `decodeAtomic`, `decodeSystem`
- The order in which extensions are tried (M → RV32I → Zba → Zbb → Zbs for R-type) does not affect results: the registry test proves no two encodings overlap
- **I-type ALU shift special case**: for opcode 0b0010011 with funct3=001 or 101, the immediate comes from the rs2 field [24:20], NOT the 12-bit I-immediate. This covers SLLI/SRLI/SRAI, RORI, the Zbs immediate forms, and the Zbb unary ops (whose `imm` is the rs2 selector). `decodeIAlu()` handles this with a conditional extraction
- ECALL/EBREAK/FENCE/FENCE.I carry no operand fields
- **Reserved encodings trap** (IllegalInstruction): ECALL/EBREAK with rd or rs1 ≠ 0, LR.W with rs2 ≠ 0, JALR with funct3 ≠ 0. FENCE and FENCE.I ignore their other fields, as the spec requires
- Decode return types: `rv32m.decodeR()` returns non-optional `Opcode` (all funct3 values valid); other decoders return `?Opcode` (some inputs invalid)

### Opcode Registry (decoders/registry.zig)

- The registry is the **specification** of the 32-bit encodings the decoder accepts: one `Entry` per opcode with its identifying fields (opcode7, f3, f7, f5, f12, and fixed rs2/rd/rs1 values). `Entry.mask()`/`match()` give the constrained bits; `lookup(raw)` finds the matching entry; `instruction(entry, raw)` is the exact `Instruction` (operands included) the decoder must return
- `registry_test.zig` checks: no two entries overlap, every `Opcode` variant has exactly one entry, every entry decodes correctly with random operand bits, and a sweep over all identifying-field values. `zig build verify-decoder` checks all 2^30 32-bit encodings
- A decoder change must keep both green; a new instruction needs a registry entry. 16-bit RV32C encodings are outside the registry (covered by rv32c tests and compliance)

### Atomic Operations & Reservation

- LR_W/SC_W orchestration stays in cpu.zig (needs reservation state + memory access); AMO computation is in `rv32a.zig`
- SC_W checks alignment and bounds (`checkWordAccess`) BEFORE it looks at the reservation: a misaligned or out-of-bounds SC.W faults even when it would have failed, and the fault leaves the reservation unchanged (spec: no SC.W retires unless it passes memory permission checks; Spike and Sail agree)
- Reservation state is `reservation: ?u32` (null = no reservation) — Option type eliminates impossible states that a separate bool+address pair would allow
- Memory write methods (`writeByte`, `writeHalfword`, `writeWord`) auto-call `invalidateReservation()` — store sites don't need to invalidate manually. `loadProgram()` drops a reservation on any word it overwrites (`invalidateReservationRange()`). If new write methods are added, they MUST do the same. Hosts that write `memory` directly must call `clearReservation()` afterwards (the CLI's `runFile` does).
- `invalidateReservation()` checks word-aligned overlap (addr & 0xFFFFFFFC), not exact byte match

### CSR Implementation

- CSR storage (`Csr` struct with `read`/`write`) lives in `zicsr.zig`, not `cpu.zig` — cpu.zig embeds `csrs: zicsr.Csr`
- Cycle counters (0xC00, 0xC80) are read-only; writes rejected with `IllegalInstruction` (checked via bits [11:10] = 0b11)
- CSR reads receive `cycle_count` as a parameter from step() — reads see the pre-step value per the pipeline invariant

### Testing Patterns

- Each extension has comprehensive execute tests with edge cases (overflow, sign-extension boundaries, spec-mandated special cases like DIV-by-zero → -1)
- Test files are grouped semantically (by topic, not by size): `*_branch_test.zig`, `*_atomic_test.zig`, `*_csr_test.zig`, etc.
- CPU tests use `cpu/tests.zig` as a hub; extension tests use `ext/tests.zig` hubs — source files import only the hub

## Traps to Avoid

### Wrapping Arithmetic (Critical)
```zig
// WRONG — panics on overflow:
.ADD => self.writeReg(inst.rd, rs1_val + rs2_val),
// RIGHT:
.ADD => self.writeReg(inst.rd, rs1_val +% rs2_val),
```
Applies to ALL arithmetic: ADD, SUB, address calculations, PC updates, MUL.

### Shift Amount Masking (Critical)
RISC-V masks shift amounts to 5 bits (RV32). Shifts by ≥32 are undefined without masking.
```zig
// WRONG:
rs1_val << rs2_val
// RIGHT:
rs1_val << @truncate(rs2_val & 0x1F)
```
For rotates, the complement uses wrapping subtraction: `const compl: u5 = 0 -% shamt;`

### Sign Extension via Cascading Bitcasts (Critical)
Loads and SEXT operations must cast through the narrower signed type:
```zig
// WRONG — doesn't sign-extend:
self.writeReg(inst.rd, @as(u32, byte));
// RIGHT — u8 → i8 (bitcast) → i32 (sign-extends) → u32 (bitcast):
self.writeReg(inst.rd, @bitCast(@as(i32, @as(i8, @bitCast(byte)))));
```

### Endianness (Critical)
RISC-V is little-endian. All multi-byte data must be serialized explicitly — never rely on host byte order.
```zig
// WRONG — reinterprets [_]u32 in native byte order (breaks on big-endian hosts):
const program = [_]u32{ 0x06400093, 0x00A00113 };
const bytes = std.mem.sliceAsBytes(&program);

// RIGHT — define as explicit LE bytes:
const program = [_]u8{
    0x93, 0x00, 0x40, 0x06, // ADDI x1, x0, 100
    0x13, 0x01, 0x0A, 0x00, // ADDI x2, x0, 10
};

// RIGHT — or write per-word with explicit endianness:
std.mem.writeInt(u32, buf[0..][0..4], 0x06400093, .little);
```
Banned APIs in VM/CLI code: `std.mem.sliceAsBytes`, `std.mem.bytesAsSlice`, `@ptrCast` on byte buffers, `.native` endianness. These all depend on host byte order and silently break determinism on big-endian targets.

### Memory Slice Syntax
```zig
// WRONG — returns variable-length slice:
std.mem.readInt(u32, memory[addr..addr+4], .little)
// RIGHT — returns fixed-size array pointer:
std.mem.readInt(u32, memory[addr..][0..4], .little)
```

### JALR Bit [0] Clearing
RISC-V spec requires JALR to clear the LSB of the computed target address:
```zig
next_pc.* = (rs1_val +% imm_u) & 0xFFFFFFFE;
```

### Cycle Limits
`run(null)` means unlimited cycles (runs until ECALL/EBREAK) and is the default for both the library and CLI. `run(0)` executes zero steps (returns `.continue` immediately). Use `--max-cycles N` to set a finite limit.
```zig
// Default — unlimited (runs until ECALL/EBREAK):
const result = try vm.run(null);
// Finite limit:
const result = try vm.run(10_000);
// Zero steps — returns .continue without executing:
const result = try vm.run(0);
```

## Adding a New Extension

1. Create `src/instructions/newext.zig` (companion file) with `Opcode` enum, `meta()`, `name()`, `format()`, `decodeR()`/`decodeIAlu()`, and `execute()`
2. Create `src/instructions/newext/tests.zig` with decode + execute tests. Split into semantic files by topic (e.g., `decode_test.zig`, `exec_test.zig`) and use the hub pattern with `comptime { _ = @import("split.zig"); }` blocks
3. Add `test { _ = @import("newext/tests.zig"); }` in the companion file
4. Add variant to `instructions.zig` `Opcode` tagged union
5. Add decode dispatch in `decoders/branch.zig` (`decodeR()`/`decodeIAlu()`/...)
6. Add opcode entries to `decoders/registry.zig` — one `Entry` per opcode with its identifying fields (opcode7, f3, f7, and optional rs2_eq/f5/f12/rd_eq/rs1_eq). The registry is the decoder's specification: `zig build test` and `zig build verify-decoder` must pass
7. Add `executeNewext()` method in `cpu.zig` and dispatch case in `step()`
8. Add disassembly case in `main.zig` `printInstruction()`
9. Ensure all arithmetic uses wrapping operators, all memory access uses `.little`
10. Update [STRUCTURE.md](STRUCTURE.md) file tree and conventions if files were added, renamed, or moved
