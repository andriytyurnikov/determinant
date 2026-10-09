# State snapshots

- **Status:** implemented in Determinant 0.2.0 (`src/cpu/state.zig`, `CpuType.writeSnapshot` / `restoreSnapshot`).
- **Plan item:** P6.3.

## Problem

Replay, checkpointing and verification need to save a VM's exact state and load it again, possibly on another host. They also need a short fingerprint to compare. `stateDigest()` provided the fingerprint, but there was no way to save or restore state.

## Format (version 1)

The snapshot is the canonical state encoding that `stateDigest()` hashes. The digest is therefore the SHA-256 of the snapshot bytes, and two VMs have equal digests exactly when their snapshots are byte-identical.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `"DTRM"` |
| 4 | 4 | version = 1 (u32 LE) |
| 8 | 4 | memory size in bytes (u32 LE) |
| 12 | 4 | `pc` |
| 16 | 128 | `regs[0..32]`, u32 LE each (`regs[0]` must be 0) |
| 144 | 8 | `cycle_count` (u64 LE) |
| 152 | 4 | reservation valid: 0 or 1 |
| 156 | 4 | reservation address (0 when there is none) |
| 160 | 4 | `mscratch` |
| 164 | `memory size` | the memory image |

- **Byte order.** Everything is explicitly little-endian. Nothing depends on the host's byte order or struct layout: the encoder writes each field with `std.mem.writeInt(.little)` and never reinterprets memory.
- **What is left out.** The decode cache and `stop_pc` are not architectural state and are not saved. Restoring empties the decode cache and sets `stop_pc` to 0.
- **Keeping the format complete.** A comptime check in `state.zig` fails the build if `CpuType` or `zicsr.Csr` gains a field that the encoding neither covers nor explicitly excludes. Any change to the encoding bumps `version`.

## API

```zig
pub fn snapshotSize(self: *const Self) usize;            // state.header_len + memSize()
pub const snapshot_size: usize;                           // the same, for a CpuType
pub fn writeSnapshot(self: *const Self, w: *std.Io.Writer) std.Io.Writer.Error!void;
pub fn restoreSnapshot(self: *Self, r: *std.Io.Reader) RestoreError!void;
pub fn snapshotMemorySize(snapshot_start: []const u8) error{InvalidSnapshot}!u32; // in root.zig
```

The calls take Zig's `Io` reader and writer interfaces. A snapshot can go to a file, a socket or a fixed buffer (`std.Io.Writer.fixed`) without the VM allocating, which keeps the no-allocator invariant.

Both kinds of memory (`CpuType` and `RuntimeCpuType`, [memory-size.md](memory-size.md)) write the same bytes for the same state, and a snapshot of one restores into the other. `snapshotMemorySize` reads the size from a snapshot's first 12 bytes (for example with `Io.Reader.peek`), so that a host can allocate a `RuntimeCpuType`'s memory before restoring.

## Validation on restore

`restoreSnapshot` returns `error.InvalidSnapshot` in these cases:
- the magic, the version or the memory size differs from this VM's;
- `regs[0]` ≠ 0;
- the reservation flag is not 0 or 1;
- a flag of 0 comes with a non-zero address;
- the reservation address is unaligned or outside memory.

The header is validated in full before any VM state changes. Only after that is the memory image read, directly into `memory`. If the reader fails in the middle of the image, the VM is partly overwritten; `reset()` it or restore again. This avoids holding a second copy of a memory that can be up to 4 GiB.

## Alternatives considered

- **A compressed or sparse format.** That would be smaller for mostly-zero memories, but the format would no longer be the digest pre-image. A transport layer can compress if it needs to.
- **Including the decode cache.** It is not state, it is large, and including it would make the digest depend on the cache size.
