# Host-call ABI

- **Status:** implemented in Determinant 0.2.0 (`src/hostcall.zig`; the CLI uses it).
- **Plan item:** P6.2.

## Problem

The guest has no input or output. It stops at ECALL or EBREAK, and the host has to invent a protocol to exchange data. The README used to claim a "controlled syscall interface" that did not exist.

## Goals

- **Deterministic.** A call's effect on the guest depends only on the VM state and on input fixed before the run. There is no time, no randomness and no environment.
- **Small and familiar.** A C program with a minimal libc stub can use it. It uses the Linux RISC-V calling convention and syscall numbers, so existing stubs work unchanged.
- **The core VM stays pure.** ECALL still just stops `run()` with `.ecall`. Handling the call is a host library function. Embedders can use it, extend it or ignore it.

## The ABI

The guest puts the call number in `a7` and the arguments in `a0`–`a2`, then executes ECALL. The result goes in `a0`. Errors are negative Linux errno values. The ECALL itself retires like any instruction (one cycle); the call costs no further cycles.

| `a7` | Call | Arguments | Result in `a0` |
|---|---|---|---|
| 63 | `read` | `a0` = fd (0), `a1` = buffer, `a2` = length | bytes copied: `min(length, input left)`, 0 at end of input |
| 64 | `write` | `a0` = fd (1 or 2), `a1` = buffer, `a2` = length | `length` |
| 93, 94 | `exit`, `exit_group` | `a0` = status | — (the program ends) |

- **`read`.** It copies from the run's input: a byte string fixed before execution (the CLI's `--input FILE`; empty by default). It advances an input position, which belongs to the host's call environment, not to the VM state. The bytes are written into guest memory the way `loadProgram()` writes them, so an LR reservation on an overwritten word is dropped.
- **`write`.** fd 1 is the program's standard output and fd 2 its standard error. A write is all-or-nothing.
- **Errors.** Nothing is copied when there is an error:
  - a bad fd gives `-9` (EBADF);
  - a buffer that does not lie entirely inside guest memory gives `-14` (EFAULT).
- **`exit`.** The status is the full 32-bit `a0`. The CLI exits with its low 8 bits, as a POSIX process would.
- **Any other `a7`.** It is not handled: `handle()` returns `.unknown` and the host decides. The CLI then stops, as ECALL always did. Programs that use a bare ECALL as "stop", such as the built-in demo and the compliance-style tests, keep working. An embedder that prefers Linux semantics can write `-38` (ENOSYS) to `a0` and resume.

## Library API

```zig
const hostcall = det.hostcall;
var env: hostcall.Env = .{ .input = input_bytes, .stdout = out, .stderr = err };
while (true) {
    switch (try vm.run(limit)) {
        .ecall => switch (try hostcall.handle(vm, &env)) {
            .resumed => continue,
            .exit => |status| break,  // the program called exit
            .unknown => |number| break, // not a host call
        },
        .ebreak, .@"continue" => break,
    }
}
```

`handle()` works on any `CpuType`. It fails only if the host's output writer fails (`error.WriteFailed`), which is a host problem, not a guest-visible result.

## CLI

- **`--input FILE`** sets the bytes that `read` returns.
- **Output.** Guest stdout and stderr go to the CLI's stdout and stderr, between the "executing" line and the result report.
- **Exit status.** When the program calls `exit`, the CLI prints `Program exited with status N` and exits with `N & 0xFF`. Otherwise the D6 statuses apply: 0 for an ECALL/EBREAK stop, 1 for a usage or I/O error, 2 at the cycle limit and 3 on a VM fault. A program exit of 1, 2 or 3 is told apart from those by the printed line.

## Alternatives considered

- **ENOSYS for unknown calls, in the CLI.** It is cleaner as a syscall interface, but it would break every existing program that ends with a bare ECALL, including the built-in demo.
- **A Determinant-specific numbering.** It would gain nothing, and it would rule out reusing existing newlib and picolibc syscall stubs.
- **Calls that cost guest cycles** (for example proportional to length). They would add a tuning knob with no determinism benefit. Embedders that meter work can account for host calls themselves.
