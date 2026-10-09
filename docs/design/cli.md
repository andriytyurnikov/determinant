# The CLI

- **Status:** implemented after 0.2.0 (`src/main.zig`, `src/main/`). It changes the CLI's output and some of its arguments, not the VM: `tests/digests.txt` and SEMANTICS.md are unchanged.

## Problem

The 0.2.0 CLI worked, but it was awkward to use beyond a demo:

- **Mixed output.** The program's own output and the CLI's report shared stdout. `determinant prog > out.txt` captured the banner, the result and the registers with the program's output, so the CLI could not run a program in a pipeline.
- **Argument parsing.** There was no `--opt=value`, no `--`, no `--version`, and no way to read `--input` from stdin. `--dump-memory`'s optional `raw` swallowed a program file named `raw`. `--load-addr` was silently ignored for an ELF file, and an extra argument only gave a warning, which was printed after the whole report.
- **Messages.** Errors used Zig error names (`FileNotFound`, `IsDir`). A fault outside memory did not say that memory was the limit, although the repo's own `tests/programs` binaries need 256 KiB and fault in the default 64 KiB build.
- **Debugging.** Registers and the disassembly used `x` numbers only, branches showed offsets instead of targets, a memory dump was skipped on a fault and always covered all of memory, and there was no way to trace execution, list a program or print the state digest.
- **No arguments ran a demo**, which is unusual for a CLI.

## Streams

- **stdout belongs to the program** (its fd 1). The CLI writes nothing else to it when it runs a program.
- **stderr carries the program's fd 2 and the CLI's report**: the preamble, the result, the registers, a fault, `--trace`, `--dump-memory` and `--digest`.
- **The order is kept.** The CLI flushes the other stream before a program write switches streams, and stdout before every part of the report, so a terminal (or `> log 2>&1`) shows everything in the order it happened.
- **`-q` / `--quiet`** drops the preamble and the result report. Faults, usage and I/O errors, and the output of `--trace`, `--dump-memory` and `--digest` still print.
- **`--help`, `--version` and `--disassemble` write to stdout**: there is no program output to keep apart.

## Arguments

```
determinant [options] <program>
determinant --demo [options]
```

| Option | Meaning |
|---|---|
| `--max-cycles N` | Stop after N cycles (retired instructions). Default: no limit |
| `--input FILE` | The bytes the program's `read` returns; `-` reads all of stdin before the run. Default: none |
| `--load-addr ADDR` | Where a flat binary is loaded and starts. Default: 0. An error with an ELF file or `--demo` |
| `--dump-memory[=FMT]` | After the run, or after a fault, dump memory as `hexdump` (default) or `raw` |
| `--dump-range ADDR:LEN` | Dump only LEN bytes from ADDR (implies `--dump-memory`) |
| `--digest` | Print the SHA-256 digest of the final VM state (`stateDigest()`), as in `tests/digests.txt` |
| `--trace` | Print each instruction as it retires, with the register it wrote |
| `--disassemble` | List the program's instructions instead of running it: a flat binary from its load address, an ELF file's executable segments |
| `-q`, `--quiet` | See Streams |
| `--demo` | Run the built-in demo program instead of a file |
| `-h`, `--help`, `--version` | Show the help, or the version and build configuration |
| `--` | End of options: the next argument is the program even if it starts with `-` |

- **Values.** A value follows its option as the next argument or after `=` (`--max-cycles=1000`). `--dump-memory` takes its format only after `=`, so `--dump-memory raw` means a program file named `raw`.
- **Numbers** are decimal, or hexadecimal, octal or binary with a `0x`, `0o` or `0b` prefix, with optional `_` separators.
- **Errors.** An unknown option, a missing or invalid value, a second program argument, or an option that does not apply (`--load-addr` with an ELF file or `--demo`, a program with `--demo`, a dump range outside memory) is a usage error: exit status 1, a message and a pointer to `--help`.
- **Repeated options.** The last one wins.
- **No arguments** print the usage on stderr and exit with status 1.
- **Program arguments** (argv) are not supported: they need an ABI for the initial stack. Rejecting extra arguments keeps that open.

## Report

The report shows the result, then the registers with `pc` first (only the non-zero ones), then any memory dump and the digest. The exact text is fixed by the CLI tests (`src/main/report_test.zig`). In outline:

```
Running hello.bin (42 bytes at 0x00000000) in 64 KiB of VM memory, no cycle limit
hello                                                    <- the program's stdout

Program exited with status 7 after 9 cycles

Registers:
  pc        0x00000024
  x2   sp   0x00010000  65536
  x10  a0   0x00000007  7
```

- **Stops.** `Stopped at EBREAK (0x...) after N cycles`; `Stopped at ECALL (0x...) after N cycles: a7 = 0 is not a host call`; `Cycle limit reached after N cycles`; `Program exited with status N after M cycles`.
- **Faults** give the error in words and by name, the instruction (address, bits, disassembly) and the faulting address. An address outside memory names the memory size and `-Dmemory_size`.
- **Disassembly** uses ABI register names (`ra`, `sp`, `a0`), CSR names (`cycle`, `mscratch`), and absolute targets for branches and jumps when the instruction's address is known (`BEQ a0, a1, 0x00000050`). Without an address, the offset has an explicit sign (`+16`).

## Exit status

Unchanged from 0.2.0: 0 when the program stopped at ECALL or EBREAK, 1 for a usage or I/O error, 2 at the cycle limit, 3 on a VM fault, otherwise the low 8 bits of the status the program passed to `exit`. `--help`, `--version` and `--disassemble` exit 0 on success.

## Alternatives considered

- **Keep the report on stdout and add only `-q`.** Without `-q` the program's output would still be mixed with the report, so the default would stay wrong for pipelines. Debuggers and profilers (`time`, valgrind, Spike's log) report on stderr for the same reason.
- **A runtime `--memory` option.** The memory size is a comptime parameter of `CpuType`. Instantiating several sizes in the CLI would multiply its code for a build-time setting; the fault message points to `-Dmemory_size` instead.
- **Snapshots from the CLI** (`--save-snapshot`, `--resume`). The library supports them, but the host-call input position is not VM state, so resuming a program that reads input needs more design. Left for later.
