# LLVM decoder oracle

The oracle compares the decoder with LLVM's RISC-V disassembler on every 16-bit
encoding and on all (or part) of the 2^30 32-bit encodings. `zig build verify-decoder`
checks the decoder against its own specification, the opcode registry. This tool checks
the registry against an independent reading of the ISA manuals. Where the two disagree,
one of them is wrong, or the encoding is one where Determinant deliberately differs.

| File | Contents |
|---|---|
| `oracle.zig` | the driver: loads libLLVM at run time, compares on N threads, classifies the divergences and prints the report |
| `render.zig` | prints a decoded `Instruction` the way LLVM's printer does with `-riscv-no-aliases` |

The tool needs LLVM, so it is an opt-in build step. CI does not run it, and no other
step needs LLVM.

## Prerequisites

- Zig 0.16.0.
- A shared libLLVM built with the RISC-V target. Tested with Homebrew's LLVM 23.1
  (`/opt/homebrew/opt/llvm/lib/libLLVM.dylib`) and 22.1
  (`/opt/homebrew/opt/llvm@22/lib/libLLVM.dylib`) on macOS. On Linux, a distribution's
  `libLLVM-NN.so` should work, but this is untested. The library is opened with
  `dlopen`, so the executable links libc.

## Running it

```sh
LLVM=/opt/homebrew/opt/llvm/lib/libLLVM.dylib   # an absolute path
zig build llvm-oracle -Dllvm_lib=$LLVM -- self-test              # the harness catches planted bugs (~1 s)
zig build llvm-oracle -Dllvm_lib=$LLVM -- c16                    # all 49,152 16-bit encodings (< 1 s)
zig build llvm-oracle -Dllvm_lib=$LLVM -- c32 4 > c32.txt        # all 2^30 32-bit encodings, 4 threads (~2 min)
zig build llvm-oracle -Dllvm_lib=$LLVM -- c32 4 0 4000000        # only x in [0, 4,000,000)
zig build llvm-oracle -Dllvm_lib=$LLVM -- probe 8330000f 0x0000  # both decodes of some encodings
```

The step always builds ReleaseFast. Its arguments, after `--`, are:

- `c16 [THREADS]`: every halfword whose low two bits are not `0b11`.
- `c32 [THREADS [LO [N]]]`: the 32-bit encodings `raw = (x << 2) | 0b11` for x in
  `[LO, LO+N)` (decimal or `0x` hex). The default is all 2^30.
- `probe HEX...`: prints LLVM's text and Determinant's for each encoding.
- `self-test [THREADS]`: see [Self-test](#self-test).
- `--features F`: LLVM's target features (default
  `+m,+a,+c,+zba,+zbb,+zbs,+zicsr,+zifencei`, the extensions Determinant implements).

THREADS is 1 to 64 (default 4). Each thread has its own LLVM disassembler. The report
goes to stdout, and progress lines go to stderr.

The exit status is 0 when every divergence belongs to a known class, 1 when one is
unexplained (or the self-test fails), and 2 on a usage error. Without `-Dllvm_lib`, the
step fails with a message saying so.

## Reading the results

The report starts with the counts:

```
total=49152 identical=28823 both-reject=20328
(i)   Determinant accepts, LLVM rejects : 0
(ii)  Determinant rejects, LLVM accepts : 1
(iii) both accept, text differs         : 0
LLVM length != instruction length       : 0
unexplained divergences                 : 0
```

`identical` means both accept and the text is the same. LLVM's text is compared with
the decoded fields rendered in LLVM's syntax (`render.zig`). This covers the opcode
and every operand: registers, sign-extended immediates, CSR names, shift amounts and
compressed expansions. The renderer also checks each compressed expansion's implicit
registers and base opcode. A violation renders as `!BAD ...`, which never matches.
`LLVM length` counts encodings where LLVM consumed a byte count other than the
instruction's length. It must be 0.

Next comes one bucket per kind of divergence, sorted by key:

```
[i|fence|rd!=0 rs1!=0]  count=14663  known: FENCE/FENCE.I ignore their unused fields (SEMANTICS.md); ...
    0x0000808f  det: fence 0, 0                               llvm: <invalid>
```

The key is the class with both mnemonics. Class (i) keys also list the fields that a
stricter decoder would require to be zero. Each bucket shows up to three samples: the
first two encodings and the last one seen. A bucket that is not a known class has
`UNEXPLAINED` at the end of its key and no reason. Treat it as a decoder bug until shown
otherwise. Check the samples with `probe` and against the ISA manual.

Last come the identical-decode counts for each opcode (and, for `c16`, for each
compressed opcode). They show that every instruction was exercised. For example, in a
full `c32` run, each R-type instruction has 2^15 identical encodings.

The validation run with LLVM 23 on all 16-bit encodings gave the counts above: 28,823
identical, 20,328 rejected by both, and one class (ii), `c.unimp`.

## Known divergences

These are the accepted differences. The oracle checks each one against the encoding
itself (fixed field values, the exact word, or the exact LLVM text rebuilt from the
decode). A decoder bug that lands in the same bucket is still reported as unexplained.

| Class | Buckets | Reason |
|---|---|---|
| (i) | `fence\|...` (fm ≠ 0 except FENCE.TSO, pred/succ combinations, rd/rs1 ≠ 0), `fence.i\|...` (imm/rd/rs1 ≠ 0) | FENCE and FENCE.I ignore their unused fields, as the spec requires of base implementations (SEMANTICS.md, "Decoding"). LLVM disassembles only the canonical encodings. Checked: opcode MISC-MEM with funct3 0 (FENCE) or 1 (FENCE.I). |
| (ii) | `mret`, `sret`, `dret`, `wfi`, `sfence.vma` (more with other `--features`) | Privileged instructions. Determinant has no privilege modes, so they raise IllegalInstruction (SEMANTICS.md). Checked: SYSTEM with funct3 0, and a privileged mnemonic. |
| (ii) | `c.unimp` (`0x0000`) | The all-zero halfword is defined to be illegal. LLVM names it `c.unimp`. |
| (iii) | `ori ~ prefetch.i`, `ori ~ prefetch.r`, `ori ~ prefetch.w` (LLVM 23 only) | ORI with rd = x0 and imm[4:0] = 0, 1 or 3 is the encoding of the Zicbop prefetch hints. LLVM 23 prints the hint even without `+zicbop`. Determinant executes it as ORI, a HINT with no effect. Checked: the exact `prefetch` text rebuilt from the decoded rs1 and imm. |
| (iii) | `fence ~ fence.tso` (`0x8330000F`) | A naming difference. FENCE.TSO executes as FENCE, and the renderer prints its pred/succ sets. |
| (iii) | `csrrw ~ unimp` (`0xC0001073`) | A naming difference. `unimp` is LLVM's name for CSRRW x0, cycle, x0. Determinant decodes it as CSRRW, which traps at execution because `cycle` is read-only. |

LLVM 22 does not print the prefetch hints, so those buckets do not appear with it.
Other LLVM versions or `--features` may name more encodings differently, for example
Zicbop or Zihintntl hints. Add such a class to `explainText()` only after checking that
Determinant executes the encoding as the base instruction the hint is defined on.

What the oracle does not compare: execution. It also leaves out the fields Determinant
does not decode, FENCE pred/succ and the AMO aq/rl bits. The renderer prints those from
the raw bits.

## Self-test

`self-test` plants five decoder bugs after decoding:

- branch and jump offsets +2 (BEQ, BNE, JAL, C.BEQZ, C.BNEZ, C.J, C.JAL);
- SUB operands swapped (with C.SUB);
- the LW destination register off by one (with C.LW and C.LWSP);
- the CSR number off by one;
- bit 4 of the RORI shift amount flipped.

It compares all 16-bit encodings and two blocks of 2^20 32-bit encodings chosen to
contain all of these instructions. Each block fixes funct7 at `0b0100000` (SUB) or
`0b0110000` (RORI). Every decode that a planted bug changed must be reported as an
unexplained divergence, and nothing else may be. The self-test passes when all five
bugs change at least one decode, none of the changed decodes is missed, and there is
no other unexplained divergence. Run it after any change to the oracle or the
renderer. The validation run reported every changed decode, 90,112 (offsets), 4,024
(SUB), 12,224 (LW), 49,152 (CSR) and 4,096 (RORI), and nothing else.

## Runtime

Measured on an Apple M2 with 4 threads under load: about 14 million encodings per
second for 32-bit blocks. `c16` and `self-test` take about a second, and a full `c32`
run takes about 1.5 to 3 minutes.
