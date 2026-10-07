# Program loading

- **Status:** implemented in Determinant 0.2.0 (`src/loader.zig`; CLI `--load-addr`).
- **Plan item:** P6.4.

## Problem

The CLI only accepted a flat binary loaded at address 0. Execution started at 0 with `sp` = 0. That forced every program to be linked at 0 and to set up its own stack. It also meant toolchain output (ELF) had to be converted with `objcopy` first.

## Design

### ELF32

`loader.loadElf(vm, image) LoadError!u32` loads a RISC-V ELF executable and returns its entry point. It accepts:
- `ELFCLASS32` and `ELFDATA2LSB`;
- `e_machine = EM_RISCV` (243);
- `e_type = ET_EXEC`;
- `e_version` = 1.

For every `PT_LOAD` program header it copies `p_filesz` bytes from the file at `p_offset` to guest address `p_vaddr`, then zero-fills up to `p_memsz` (`.bss`). Other segment types are ignored.

The load is refused with `error.InvalidElf` in these cases:
- a segment's file range lies outside the image;
- `p_filesz > p_memsz`;
- the entry point is odd.

It is refused with `error.AddressOutOfBounds` if a segment's memory range does not fit inside the VM's memory.

All fields are read with explicit little-endian integer reads from the byte image. There are no struct casts, which keeps the endianness invariant. Bytes go into memory through `loadProgram()`, so LR reservations are respected.

### Flat binaries

`--load-addr ADDR` (decimal or `0x` hex, default 0) loads a flat binary at `ADDR` and starts execution there.

### Initial stack pointer

For both kinds of program, the CLI sets `sp` (x2) to the top of memory rounded down to 16 bytes, as the RISC-V psABI requires for stack alignment. Every other register stays 0.

The library's `reset()` still leaves every register 0. The initial stack pointer is a CLI policy, not VM semantics, so `tests/digests.txt` and SEMANTICS.md's initial state are unchanged.

### Detection

The CLI treats a file that starts with `\x7fELF` as ELF and anything else as a flat binary. `--load-addr` applies only to flat binaries.

## Alternatives considered

- **Supporting `ET_DYN`, relocations or `PT_INTERP`.** These are not needed for freestanding programs. Static executables linked at a fixed address are the norm for embedded RISC-V.
- **Setting `sp` in `reset()`.** That would change the VM's documented initial state and every state digest, for a convention that belongs to the program ABI.
