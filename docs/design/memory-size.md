# Memory size at run time

- **Status:** implemented for Determinant 0.4.0 (`src/cpu.zig`, `src/cpu/state.zig`; CLI `--memory`).

## Problem

The memory size is a comptime parameter of `CpuType`, and the CLI's comes from the build option `-Dmemory_size`. That costs more than it saves:

- A program that needs more than the default 64 KiB faults until the user rebuilds. The repo's own `tests/programs` binaries need 256 KiB.
- A host cannot take the size from a configuration file, from the program, or from a snapshot header.
- One binary cannot run programs that need different sizes, and CI builds once per size.

## What does not change

The size is already part of the state: the snapshot header stores it (offset 8), and `stateDigest()` hashes that header. A run with 1 MiB of memory gives the same snapshot and digest whether the size was fixed at compile time or chosen at run time. SEMANTICS.md keeps semantics version 1 and state encoding version 1, and `tests/digests.txt` does not change.

## Design

### Two kinds of memory

```zig
pub fn CpuType(comptime memory_size: u32, comptime options: Options) type  // as today
pub fn RuntimeCpuType(comptime options: Options) type                       // new
```

- **`CpuType(N, options)`** keeps the memory inside the VM struct, as now. Every bounds check compares with a constant. Existing code compiles unchanged.
- **`RuntimeCpuType(options)`** borrows a buffer from the host: `memory: []u8`. The VM still never allocates; the host owns the buffer and must keep it alive.
- **One implementation.** Both are the same generic struct, parameterized by the kind of memory. All code goes through `memSize()`: for `CpuType` it returns the constant, so the generated code is the same as now. Slicing (`memory[addr..][0..4]`) is the same for an array and a slice.

### API

- **`memSize()`** on both. `CpuType` also keeps `mem_size` and `snapshot_size`; `snapshotSize()` is new on both.
- **`RuntimeCpuType.init(memory) InitError!Self`** checks the size and resets the VM. `initInPlace(self, memory)` does the same for a VM placed on the heap (for a large decode cache, which would not fit on the stack). The size must be at least 4, a multiple of 4, and at most 2^32 - 4 bytes: every address is a `u32`. `error.InvalidMemorySize` otherwise. The bounds checks rely on this (`size - 4` must not wrap).
- **`reset()`** zeroes the memory, as now, and keeps the buffer.
- **Snapshots.** `restoreSnapshot` requires the snapshot's size to equal `memSize()`, as now. `snapshotMemorySize(header)` reads the size from a snapshot's header, so a host can allocate exactly that much before restoring.
- **Copying.** Copying a `RuntimeCpuType` value copies the registers but shares the memory. A snapshot is the way to fork a VM.
- **Generic code.** `hostcall.handle`, `loader.loadElf` and `loader.segments` take either kind (`anytype`), using `memSize()`.

### CLI

- **`--memory SIZE`**: bytes, or with a `KiB`, `MiB` or `GiB` suffix (`--memory 1MiB`). Same limits as `init`. Default: 64 KiB.
- **The CLI uses `RuntimeCpuType`**, so one binary serves every size. A size that cannot be allocated is an error ("cannot allocate 3 GiB of VM memory"), exit status 1.
- **The initial `sp`** is the top of the chosen memory, rounded down to 16 bytes, as now.
- **Order-independent checks.** `--load-addr` and `--dump-range` are checked against the memory size after all arguments are parsed, so `--load-addr 0x20000 --memory 1MiB` works.
- **Messages.** A fault outside memory points to `--memory` instead of `-Dmemory_size`. `--version` no longer names a memory size. `--help` gives the default.

### Build

`-Dmemory_size` is removed: it only set the CLI's size and the `det.Cpu` alias. `det.Cpu` becomes `CpuType(64 * 1024, .{})`, and `det.RuntimeCpu` is `RuntimeCpuType(.{})`.

## Testing

- **Unit tests** keep `TestCpu`, a 64 KiB `CpuType`. The memory and bounds tests also run on a 64 KiB `RuntimeCpuType`, together with sizes at the edges (4 bytes, a size not a power of two).
- **New tests** for `init` (every invalid size), `initInPlace`, `snapshotMemorySize`, and restoring a snapshot into a VM of another size.
- **Both kinds against each other.** The compliance suite and `test-digests` run every binary on both kinds, as they already run with the decode cache on and off. The digests must be identical.
- **CLI tests** choose their memory with `--memory`. Programs that needed a larger build no longer skip; the goldens run at several sizes in one build. CI's three `-Dmemory_size` jobs are removed.
- **Mutation catalogue.** The bounds-check mutants are re-anchored to `memSize()`, with new ones for `init`'s checks and `--memory`.
- **Speed.** `zig build bench` reports both kinds. On an Apple M2, `CpuType` is unchanged (about 275–290 MIPS, within the noise of the 0.3.0 numbers), and `RuntimeCpuType` is about 4% slower: every bounds check loads the size.

## Room for later

- **Instruction-set variability.** `Options` stays the one compile-time configuration of both kinds, so a later option that selects extensions applies to both. Like the memory size, the instruction set changes what a program does, so it would go into the state header too (state encoding version 2), so that VMs with different instruction sets never share a digest.
- **Loader verification.** The loader takes either kind through `memSize()`, so checks added to it later work for both.

## Alternatives considered

- **Only `RuntimeCpuType`.** Simpler, but an embedder with a fixed size would pay for run-time bounds checks for nothing. Both are kept.
- **One `CpuType` with a `Memory` parameter** (`CpuType(.{ .fixed = N }, ...)` and `CpuType(.runtime, ...)`). One name, but it breaks every existing `CpuType(N, ...)` call.
- **A few fixed sizes in the CLI**, chosen with a switch. It leaves the VM alone, but multiplies the CLI's code and still gives a fixed menu.
- **Memory allocated on demand** across the whole 4 GiB address space. It needs allocation or a page pool inside the VM. A separate design if it is ever needed.
