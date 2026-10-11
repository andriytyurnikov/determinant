# Determinant execution semantics

This is the contract a deployment that needs reproducible execution, such as consensus, can rely on. It states what the VM does wherever the RISC-V specifications leave a choice, wherever Determinant deliberately differs from a hardware hart, and what "deterministic" covers. Where it says nothing, the ratified RISC-V unprivileged specification applies.

- **Semantics version:** 1, for Determinant 0.2.0.
- **State encoding version:** 1 (see [State and digests](#state-and-digests)).

Any change to guest-visible behavior described here is a breaking change. It is listed in the changelog and changes `tests/digests.txt`.

## Supported instruction set

One hart, RV32 (XLEN = 32), little-endian, with:

| Extension | Contents |
|---|---|
| RV32I | the base integer ISA: 37 computational, memory and control instructions, plus FENCE, ECALL and EBREAK |
| M | multiply and divide |
| A | Zalrsc (LR.W, SC.W) and Zaamo (the nine AMO*.W instructions) |
| C (Zca) | the 16-bit encodings of the above, expanded to their 32-bit equivalents |
| Zicsr | the six CSR instructions; for the CSRs that exist, see [CSRs](#csrs) |
| Zifencei | FENCE.I |
| Zba, Zbb, Zbs | bit manipulation |

Everything else is absent and its encodings raise `IllegalInstruction`. That includes floating point (F, D, Q, Zfh), vectors, every privileged instruction (MRET, SRET, WFI, SFENCE.VMA, and so on), and the `time`/`timeh` CSRs.

Determinant has no privilege modes, no trap handlers, no interrupts and no virtual memory. A fault is reported to the host (see [Faults](#faults)); it never transfers control inside the guest.

## Decoding

- **Instruction length.** An instruction whose low two bits are not `0b11` is a 16-bit RV32C instruction; otherwise it is 32 bits. Longer encodings do not exist and raise `IllegalInstruction`.
- **The legal 32-bit encodings** are exactly those listed in `src/decoders/registry.zig`. Every other 32-bit encoding raises `IllegalInstruction`. `zig build verify-decoder` checks this on all 2^30 32-bit encodings.
- **Reserved encodings trap.** These are rejected even though some implementations accept them:
  - ECALL and EBREAK with `rd` ≠ 0 or `rs1` ≠ 0;
  - LR.W with `rs2` ≠ 0;
  - JALR with `funct3` ≠ 0;
  - shift-immediates with `imm[5]` = 1 (`shamt` ≥ 32), and every other encoding that differs from a listed one in a fixed field;
  - the reserved RV32C forms: the all-zero halfword, C.ADDI4SPN with `nzuimm` = 0, C.ADDI16SP and C.LUI with a zero immediate, C.LWSP with `rd` = 0, C.JR with `rs1` = 0, and C.SRLI/C.SRAI/C.SLLI with `shamt[5]` = 1.

  Accepting a reserved encoding and rejecting it later would change what existing programs do, so these trap from the start.
- **FENCE and FENCE.I ignore their unused fields.** These are `fm`, `pred`, `succ`, `rs1` and `rd` for FENCE, and `imm`, `rs1` and `rd` for FENCE.I. The specification requires base implementations to ignore them, so encodings such as FENCE.TSO and PAUSE execute as FENCE.
- **HINTs execute as their base instruction.** Examples are:
  - ADDI/ORI/LUI and friends with `rd` = x0, including the `prefetch.*` hints;
  - C.NOP with a non-zero immediate, and C.ADDI with `rd` ≠ 0 and immediate 0;
  - C.LI/C.MV/C.ADD/C.SLLI with `rd` = x0;
  - C.SRLI/C.SRAI/C.SLLI with `shamt` = 0.

  Each either writes x0 or writes a register with its own value, so none has any effect beyond retiring.

## Execution model

Each `step()` does, in this order:

1. fetches the instruction at `pc`;
2. decodes it;
3. reads its source registers;
4. executes it, which may write `rd`, memory, the reservation and CSRs;
5. sets `pc` to the next instruction (`pc + 2` for a 16-bit instruction, `pc + 4` otherwise) or the branch or jump target;
6. increments `cycle_count`.

An instruction either completes all of these steps (it *retires*) or raises a fault and changes nothing.

- **x0** always reads as zero. Writes to it are discarded.
- **Arithmetic** wraps modulo 2^32, as RISC-V specifies. That includes address computation (`rs1 + imm`), branch targets and `pc + 4`.
- **Division** follows the M specification exactly:
  - division by zero gives all ones (DIV/DIVU) or the dividend (REM/REMU);
  - `INT_MIN / -1` gives `INT_MIN` with remainder 0.
- **Shifts** use the low 5 bits of the shift amount. JALR clears bit 0 of its target.
- **FENCE and FENCE.I** are no-ops: there is one hart and no cache to synchronize.
- **The AMO `aq` and `rl` bits** are ignored, for the same reason.

## Faults

Execution stops with an error from the `StepError` set, and the VM state is left exactly as it was before the instruction: `pc`, all registers, memory, `cycle_count`, the reservation and the CSRs. The faulting instruction does not retire.

The host sees the error from `step()` or `run()`.
- **Details.** `describeFault(err)` reports the instruction's address and bits, and the faulting address (data address or `pc`). Call it before changing the state.
- **Continuing.** The host can inspect the state, change it (for example, skip the instruction by advancing `pc`), and continue.

| Error | Raised when |
|---|---|
| `IllegalInstruction` | the instruction does not decode (see [Decoding](#decoding)); it accesses a CSR that does not exist; or it writes a read-only CSR |
| `MisalignedPC` | `pc` is odd |
| `PCOutOfBounds` | the instruction at `pc` does not lie entirely inside memory |
| `MisalignedAccess` | a halfword access is not 2-byte aligned, or a word, LR.W, SC.W or AMO access is not 4-byte aligned |
| `AddressOutOfBounds` | any byte of a data access lies outside memory |

- **Check order.** For a data access, alignment is checked before bounds. The address is computed with wrapping arithmetic, so `rs1 + imm` past `0xFFFFFFFF` wraps to a low address, which may be valid.
- **The guest cannot make `pc` odd.** Branch and jump offsets are even, and JALR clears bit 0. Only the host can set an odd `pc`.
- **Misaligned data accesses are fatal.** A misaligned access is never split into smaller accesses or emulated: it always faults. The RISC-V specification allows an execution environment to do this. (`ma_data` from riscv-tests, which needs misaligned accesses to succeed, is therefore not run.)

## LR/SC

- **LR.W** loads a word and sets the reservation to its (aligned) address, replacing any earlier reservation. A faulting LR.W leaves the reservation as it was.
- **SC.W** first checks alignment and then bounds. It faults on a bad address whether or not it would have succeeded, and the fault leaves the reservation unchanged. On a valid address:
  - if the reservation holds exactly that address, SC.W stores the word and writes 0 to `rd`;
  - otherwise it stores nothing and writes 1 to `rd`.

  Either way, the reservation is then cleared.
- **What clears the reservation.** These are all byte-exact on the reserved word:
  - SC.W;
  - any guest store or AMO that writes at least one byte of the reserved word;
  - `loadProgram()` overwriting at least one byte of it;
  - `clearReservation()` and `reset()`.

  A host that writes `memory` directly must call `clearReservation()`.
- **What does not clear it.** Writes to other words, faults, and the passing of time: a reservation never expires on its own.

## ECALL and EBREAK

ECALL and EBREAK stop execution. `step()` returns `.ecall` or `.ebreak`, and `run()` returns with that result.

- **They retire.** `cycle_count` is incremented and `pc` already points past the instruction: `pc + 4`, or `pc + 2` for C.EBREAK. There is no C.ECALL.
- **Continuing.** Calling `run()` again continues with the next instruction.
- **The host's role.** The host is responsible for whatever the call means, for example reading arguments from `a0`–`a7` and writing results back. The standard convention is the host-call ABI in `docs/design/host-calls.md` (`hostcall.handle()`): `read`, `write` and `exit`, with Linux RISC-V numbers in `a7`. Its effects depend only on the VM state and input fixed before the run.
- **The stopping instruction's address** is in `stop_pc`: `pc - 4` for ECALL and EBREAK, `pc - 2` for C.EBREAK. `stop_pc` is host-facing metadata, not part of the architectural state or the digest.

## CSRs

| CSR | Number | Access | Value |
|---|---|---|---|
| `cycle`, `instret` | 0xC00, 0xC02 | read-only | low 32 bits of `cycle_count` |
| `cycleh`, `instreth` | 0xC80, 0xC82 | read-only | high 32 bits of `cycle_count` |
| `mscratch` | 0x340 | read/write | a 32-bit scratch register for the guest; 0 after `reset()` |

- **`cycle_count` counts retired instructions.** Every instruction, compressed or not, takes one "cycle", so `cycle` and `instret` are always equal.
- **What a CSR instruction sees.** A CSR instruction reads the count from before it retires.
- **Not wall-clock time.** There is no source of time: `time`/`timeh` (0xC01, 0xC81) and every other CSR number raise `IllegalInstruction`.
- **`mscratch`** has a machine-mode CSR number. It is exposed here because Determinant has a single privilege level, and it is plain storage.
- **Writes.** A write to a read-only CSR raises `IllegalInstruction`. These are CSRs with bits [11:10] = `0b11`, so this includes CSRRW and CSRRWI with `rd` = x0.
  - CSRRS, CSRRC, CSRRSI and CSRRCI do not write when `rs1` is x0 or `uimm` is 0, so these forms can read read-only CSRs.
  - CSRRW and CSRRWI with `rd` = x0 do not read the CSR.

## Running

- **`run(max_cycles)` repeats `step()`** until an ECALL or EBREAK, a fault, or `cycle_count >= max_cycles`. In the last case it returns `.continue`, possibly without executing anything.
  - The limit is absolute: it is compared with `cycle_count`, which keeps counting across calls. It is not a budget for this call.
  - `run(null)` has no limit, and `run(0)` executes nothing.
  - `runFor(n)` is `run(cycle_count + n)`, saturating: at most `n` more instructions.
- **Initial state.** After `init()` or `reset()`, `pc` = 0, all registers are 0 (including `sp`), memory is all zero, `cycle_count` = 0, there is no reservation, and `mscratch` = 0.
- **The CLI.** These are host conventions layered on top of the VM, so the state digests above don't depend on them:
  - it loads an ELF32 executable at its segments, or a flat binary at `--load-addr`;
  - it starts at the entry point with `sp` at the 16-byte-aligned top of memory;
  - it implements the host-call ABI (`docs/design/host-calls.md`, `docs/design/program-loading.md`).

## Memory

- **Layout.** One flat, zero-initialized region of `mem_size` bytes at address 0, with no protection: code is writable and data is executable.
- **Endianness.** Little-endian on every host.
- **Self-modifying code.** Stores to code take effect for the next instruction fetched, because every fetch reads memory. The decode cache only skips re-decoding identical instruction bits, so it is invisible to the guest.
- **Nothing else.** There is no MMIO, no memory-mapped timer and no device.

## State and digests

The architectural state is: `pc`, the 32 registers, the memory image, `cycle_count`, the reservation and `mscratch`. `stateDigest()` is the SHA-256 of a canonical, versioned, explicitly little-endian encoding of exactly that state (`src/cpu/state.zig`). The same bytes are the snapshot that `writeSnapshot()` produces and `restoreSnapshot()` loads (`docs/design/snapshots.md`). The decode cache and `stop_pc` are not part of it.

## What "deterministic" covers

Take the same initial state and the same sequence of host actions (state changes between steps, and the number of steps or the `run()` limits). The VM then reaches the same architectural state, so the same `stateDigest()`:
- on every host OS and CPU architecture, either endianness;
- in every build mode;
- with any decode cache size.

CI checks this on every change: Linux and macOS, `debug` and `fast` builds, a big-endian s390x target, and the decode cache on and off, all against `tests/digests.txt`.

Outside the guarantee:
- how long execution takes;
- anything the host does in response to ECALL or EBREAK;
- host resource failures, such as being unable to allocate a VM.

The guest has no access to time, randomness, the host environment or any other source of nondeterminism.
