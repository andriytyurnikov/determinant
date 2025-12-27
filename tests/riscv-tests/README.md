# RISC-V Compliance Test Binaries

Pre-compiled test binaries from the [riscv-tests](https://github.com/riscv-software-src/riscv-tests) suite, adapted for the Determinant VM.

## Quick start

The pre-compiled binaries are checked into `src/compliance/bin/`. You only need to rebuild if you modify the test environment or want to update to a newer riscv-tests commit.

```bash
zig build test-compliance    # run compliance tests (uses pre-compiled binaries)
```

## Rebuilding binaries

### Prerequisites

Install a RISC-V cross-compiler. On macOS:

```bash
brew tap riscv-software-src/riscv
brew install riscv-tools
```

On Ubuntu/Debian:

```bash
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
```

### Initialize submodule

```bash
git submodule update --init --recursive
```

### Build

```bash
cd tests/riscv-tests
make            # builds all test binaries
make rv32ui     # builds only RV32I base integer tests
make clean      # removes build artifacts
make list       # shows all test names and count
```

Output goes to `src/compliance/bin/<extension>/<test>.bin`.

## Custom test environment

The `env/determinant/` directory contains a custom test harness that adapts riscv-tests to our VM:

- **`riscv_test.h`** — replaces the standard `p/riscv_test.h` which does M-mode privilege setup. Our version starts at address 0x0 and uses EBREAK for termination.
- **`link.ld`** — linker script with origin at 0x0 (not 0x80000000).

### Pass/fail convention

- `gp` (x3) register = 1: **PASS**
- `gp` (x3) register = (N << 1 | 1): **FAIL** at test case N

## Skipped tests

- `fence_i` — tests self-modifying code via I-cache invalidation
- `ma_data` — tests misaligned data access traps; our VM traps on misaligned access (spec-valid)

## Extensions covered

| Extension | Tests | Description |
|-----------|-------|-------------|
| rv32ui | ~39 | RV32I base integer |
| rv32um | 8 | RV32M multiply/divide |
| rv32ua | 10 | RV32A atomic operations |
| rv32uc | 1 | RV32C compressed instructions |
| rv32uzba | 3 | Zba address generation |
| rv32uzbb | 18 | Zbb bit manipulation |
| rv32uzbs | 8 | Zbs single-bit operations |
