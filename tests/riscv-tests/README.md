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
make            # builds the test binaries that are out of date
make -B         # rebuilds every test binary
make rv32ui     # builds only RV32I base integer tests
make clean      # removes the ELF intermediates in build/ (never the checked-in binaries)
make list       # shows all test names and count
```

Output goes to `src/compliance/bin/<extension>/<test>.bin`. With GCC 15.1 / binutils 2.45 (Homebrew `riscv-gnu-toolchain`) at submodule commit `f443f44`, the rebuild is byte-identical to the checked-in binaries. The linker warns that the ELF has an RWX `LOAD` segment; that is expected, because the test image is one flat, writable, executable region.

Other toolchain versions can encode a few tests differently. Ubuntu 24.04's GCC 13.2 / binutils 2.42 differs on `rvc`, `auipc` and `fence_i`. So CI does not compare bytes. Instead, its `compliance-rebuild` job rebuilds the whole suite from the submodule with the distro GCC and requires every rebuilt binary to pass:

```bash
make BIN_DIR=/tmp/rebuilt BUILD_DIR=/tmp/build
zig build test-compliance-rebuild -Drebuilt_compliance=/tmp/rebuilt   # from the repository root
```

## Custom test environment

The `env/determinant/` directory contains a custom test harness that adapts riscv-tests to our VM:

- **`riscv_test.h`** — replaces the standard `p/riscv_test.h` which does M-mode privilege setup. Our version starts at address 0x0 and uses EBREAK for termination. A test that stops at an ECALL fails: some tests execute ECALL themselves, so it is never a valid end of test.
- **`link.ld`** — linker script with origin at 0x0 (not 0x80000000).

### Pass/fail convention

- `gp` (x3) register = 1: **PASS**
- `gp` (x3) register = (N << 1 | 1): **FAIL** at test case N

## Skipped tests

- `ma_data` — checks that misaligned loads and stores return the right values, which requires them to complete (in hardware, or in a trap handler that emulates them). Determinant reports every misaligned data access to the host as a fatal `MisalignedAccess` error instead, so this test cannot pass by design. That policy is allowed by the spec: an execution environment may raise an exception for any misaligned access.

`fence_i` is included. It tests self-modifying code: Determinant fetches every instruction from memory as it executes, so stores are visible to fetch at once and `FENCE.I` can be a no-op.

## Extensions covered

| Extension | Tests | Description |
|-----------|-------|-------------|
| rv32ui | 41 | RV32I base integer: 38 instruction tests (including `fence_i`), plus `simple`, `ld_st` and `st_ld` |
| rv32um | 8 | RV32M multiply/divide |
| rv32ua | 10 | RV32A atomic operations |
| rv32uc | 1 | RV32C compressed instructions |
| rv32uzba | 3 | Zba address generation |
| rv32uzbb | 18 | Zbb bit manipulation |
| rv32uzbs | 8 | Zbs single-bit operations |
