# Determinant

A deterministic RISC-V execution substrate for sandboxed computation.

Determinant is a virtual machine that executes RISC-V code with guaranteed deterministic behavior. Same inputs always produce identical outputs, enabling perfect reproducibility, distributed verification, and trustworthy sandboxing.

## Why Determinant?

Traditional VMs introduce non-determinism through timing, memory layout randomization, and platform differences. Determinant eliminates these by design:

- Fixed memory layout
- Instruction counting instead of wall-clock time
- Deterministic I/O through controlled syscall interface
- No undefined behavior, no platform-specific quirks

## Use Cases

- **Smart contracts & blockchain** — deterministic execution required for consensus
- **Reproducible builds** — verify builds produce identical outputs
- **Security research** — record and replay exploits exactly
- **Distributed systems** — state machine replication with guaranteed consistency
- **Scientific computing** — bit-exact reproducibility across platforms

## Requirements

- [Zig](https://ziglang.org/) 0.15.2+

## Build

```sh
zig build
```

## Run

```sh
zig build run
```

## Test

```sh
zig build test
```

## Project Structure

```
src/
  root.zig   — library root module
  main.zig   — CLI entry point
build.zig     — build system configuration
build.zig.zon — package metadata
```
