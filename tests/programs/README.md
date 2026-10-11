# C program corpus

Ten freestanding C programs. They are the realistic part of the test corpus, and the workload for `zig build bench`.

| Program | Exercises |
|---|---|
| `arith64` | 64-bit division and multiplication through compiler-rt, `mulh`/`mulhsu`/`mulhu`, 64-bit modular arithmetic |
| `atomics` | AMOs, LR/SC loops (CAS, sub-word atomics through masked LR/SC), a spin lock, a Treiber stack |
| `bitops` | count leading/trailing zeros, popcount, byte swaps, rotates, min/max, sign and zero extension, single-bit operations |
| `crc32` | table-driven and bitwise CRC-32 |
| `interp` | a bytecode interpreter: dense `switch` (jump table) and function pointers |
| `memops` | `memcpy`/`memmove`/`memset` at odd offsets and sizes, struct copies, decimal formatting |
| `qsort` | quicksort, and a generic sort with a comparator function pointer |
| `recursion` | deep recursion (Ackermann, Fibonacci, Hanoi, a recursive-descent parser) |
| `sha256` | SHA-256 |
| `sieve` | byte-array and bit-array sieves of Eratosthenes |

Each program computes into `out[16]` and returns a checksum. `crt0.S` sets `gp` and `sp` (the stack top is 256 KiB, the corpus VM's memory size), calls `prog_main`, and stops with EBREAK, with `a0` = the checksum and `a1` = the address of `out`. `libmini.c` provides `memcpy`, `memmove`, `memset`, `memcmp` and `strlen`.

## Layout

- `src/` — the sources, plus `native_main.c`, which runs a program on the host and prints its result in the same format.
- `bin/<config>/<program>.bin` — flat binaries that load at address 0, checked in like the compliance binaries. There are two configurations:
  - `imac_zb-O2`: RV32IMAC with Zba/Zbb/Zbs, optimize mode `fast`
  - `ima-Os`: RV32IMA without compressed or bit-manipulation instructions, optimize mode `small`
- `expected/<program>.txt` — the result of the same C program run natively.
- `elf/crc32.elf` — the `imac_zb-O2` crc32 executable as an ELF file, for the ELF-loading test.

## How it is used

`zig build test-digests` (part of `test-all`) runs every binary. It checks that each program stops at EBREAK with the same `a0` and `out` as the native run, and that its final VM state matches `tests/digests.txt`.

## Rebuilding

```sh
zig build programs
```

This compiles every program with Zig's C compiler (no RISC-V toolchain needed) and re-runs the native builds. It writes `bin/` and `expected/` in place. Run it on a little-endian host. With Zig 0.17.0 the output is byte-identical on macOS and Linux. A newer Zig may generate different code, which changes the digests of the `programs/` entries in `tests/digests.txt`; regenerate that file afterwards with `zig build digests > tests/digests.txt`.
