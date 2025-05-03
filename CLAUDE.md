# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Determinant — a deterministic RISC-V VM. Written in Zig 0.15.2, structured as both a library and CLI executable. See `README.md` for public API, [STRUCTURE.md](STRUCTURE.md) for file tree and module conventions.

## Build Commands

- `zig build` — compile the project (output in `zig-out/`)
- `zig build run` — build and run the CLI executable
- `zig build test` — run all tests (library + executable)
- `zig build run -- <args>` — pass arguments to the executable

## Determinism Invariants

These are load-bearing constraints — violating any one breaks deterministic execution:

- **Wrapping arithmetic everywhere** — all VM arithmetic uses `+%`, `-%`, `*%` (wrapping operators). Zig's default `+`, `-`, `*` panic on overflow in debug mode and are undefined in release. Every ADD, SUB, address calculation, and PC update must wrap.
- **Explicit little-endian** — every `std.mem.readInt`/`writeInt` call uses `.little`. Never `.native` or `.big`.
- **No allocators in core VM** — all state is fixed-size (registers, memory array, CSR struct). Zero allocation failure modes.
- **No floating-point** — intentional; FP non-determinism (rounding modes, NaN payloads) is avoided entirely.
- **Single-hart** — no threading, no FENCE (intentionally omitted).

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

### Module Structure

See [STRUCTURE.md](STRUCTURE.md) for the full file tree, module conventions, and import patterns. Key insight: `vm.zig` is the namespace hub — `root.zig` imports it and re-exports `cpu`, `instructions`, `decoder`.

### ISA Extension Architecture

- ISA extensions live in `src/vm/instructions/` — each owns its own `Opcode` enum (with `name()`, `format()`, and comptime `meta()` methods), decode, and execute logic
- `instructions.zig` imports all extensions including rv32c; composes execution extensions via `Opcode = union(enum) { i: rv32i.Opcode, m: rv32m.Opcode, a: rv32a.Opcode, csr: zicsr.Opcode, zba: zba.Opcode, zbb: zbb.Opcode, zbs: zbs.Opcode }`
- `instructions.Opcode` delegates `name()` and `format()` to extensions via `inline else`
- CPU dispatch methods named after tagged union fields: `executeI`, `executeM`, `executeA`, `executeCsr`, `executeZba`, `executeZbb`, `executeZbs`
- Each extension's execution is delegated: `executeI()` (RV32I in cpu.zig), `rv32m.execute()`, `rv32a.execute()`, `zicsr.Csr.execute()`, `zba.execute()`, `zbb.execute()`, `zbs.execute()`

### Comptime Metadata System

- `format.zig` owns `Format` enum (R/I/S/B/U/J), `Meta` struct (`name_str` + `fmt`), and generic `opcodeName`/`opcodeFormat` helpers
- Extensions import format.zig as `fmt` and provide `pub fn meta(comptime self: Opcode) fmt.Meta` — this compiles to a perfect dispatch table with zero runtime cost via `inline else`
- `rv32a.zig` uses explicit name strings in `meta()` for dot notation (`"LR.W"`, `"AMOSWAP.W"`) — other extensions use `@tagName(self)` directly
- `rv32c.zig` uses a comptime `dotName` transform (`C_LW` → `"C.LW"`) for its own naming convention

### Compressed Instructions (RV32C)

- `rv32c.zig` is a normal sibling extension — it only imports `rv32i.zig` and `format.zig` (no upward dependency on `instructions.zig`)
- `rv32c.zig` has its own `Opcode` enum (26 variants) for decode/display purposes — NOT part of the `instructions.Opcode` tagged union (no execution path, no format)
- `expand()` returns `rv32c.Expanded` (struct with `op: rv32i.Opcode`, register fields, imm, raw) — the decoder wraps this into a full `Instruction` with `.op = .{ .i = exp.op }` via `expandCompressed()` in `decoder.zig`
- `decode()` identifies the opcode; `expand()` validates constraints and builds the `Expanded` — keep identification and validation separate
- Some compressed instructions encode reserved values (e.g., C.ADDI4SPN with nzuimm=0, C.LUI with imm=0) that must be rejected as `IllegalInstruction` in `expand()`
- `instructions.isCompressed(raw)` is the single source of truth for 16-bit vs 32-bit detection — used by decoder.zig, cpu.zig, and main.zig

### Decoder Dispatch Priority

- `decoder.zig` sub-decoders use semantic names matching their rv32i counterparts: `decodeStore`, `decodeBranch`, `decodeLoad`, `decodeAtomic`, `decodeSystem`
- **R-type dispatch order matters**: M-extension (funct7=0b0000001) must be checked BEFORE RV32I — both share opcode 0b0110011 and RV32I would false-match on funct3 alone. Order is: M → RV32I → Zba → Zbb → Zbs
- **I-type ALU shift special case**: for shifts (funct3=001 or 101), the immediate comes from the rs2 field [24:20] (5-bit shamt), NOT the full 12-bit I-immediate. `decodeIAlu()` handles this with a conditional extraction.
- Decode return types: `rv32m.decodeR()` returns non-optional `Opcode` (all funct3 values valid); other decoders return `?Opcode` (some inputs invalid)

### Atomic Operations & Reservation

- LR_W/SC_W orchestration stays in cpu.zig (needs reservation state + memory access); AMO computation is in `rv32a.zig`
- Reservation state is `reservation: ?u32` (null = no reservation) — Option type eliminates impossible states that a separate bool+address pair would allow
- Memory write methods (`writeByte`, `writeHalfword`, `writeWord`) auto-call `invalidateReservation()` — store sites don't need to invalidate manually. If new write methods are added, they MUST call `invalidateReservation()`.
- `invalidateReservation()` checks word-aligned overlap (addr & 0xFFFFFFFC), not exact byte match

### CSR Implementation

- CSR storage (`Csr` struct with `read`/`write`) lives in `zicsr.zig`, not `cpu.zig` — cpu.zig embeds `csrs: zicsr.Csr`
- Cycle counters (0xC00, 0xC80) are read-only; writes rejected with `IllegalInstruction` (checked via bits [11:10] = 0b11)
- CSR reads receive `cycle_count` as a parameter from step() — reads see the pre-step value per the pipeline invariant

### Testing Patterns

- Each extension has comprehensive execute tests with edge cases (overflow, sign-extension boundaries, spec-mandated special cases like DIV-by-zero → -1)

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

### Zig 0.15.2 Memory Slice Syntax
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

## Adding a New Extension

1. Create `src/vm/instructions/newext.zig` with `Opcode` enum, `meta()`, `name()`, `format()`, `decodeR()`/`decodeIAlu()`, and `execute()`
2. Create `src/vm/instructions/newext_test.zig` with decode + execute tests
3. Add `test { _ = @import("newext_test.zig"); }` in the source file
4. Add variant to `instructions.zig` `Opcode` tagged union
5. Add decode dispatch in `decoder.zig` — respect priority order in `decodeR()`/`decodeIAlu()`
6. Add `executeNewext()` method in `cpu.zig` and dispatch case in `step()`
7. Add disassembly case in `main.zig` `printInstruction()`
8. Ensure all arithmetic uses wrapping operators, all memory access uses `.little`
