"""Program skeleton shared by the Spike differential tests.

Memory layout (linked at 0x10000, see link.ld):
  _start / begin_signature  Spike-only preamble: install the trap handler (mtvec)
  test_start                Determinant starts here (it has no mtvec)
  ... test body ...         ends in ebreak / c.ebreak / ecall, or faults
  trap_handler              Spike-only: dumps x1..x31, mscratch, mcause, mepc, mtval
  data_region (2 KiB)       scratch memory for loads, stores and AMOs
  trap_dump                 Spike's register dump, compared with Determinant's registers
  end_signature
  tohost / fromhost         HTIF exit mailbox (outside the signature)

Spike dumps [begin_signature, end_signature); the runner dumps the same memory range
plus its register file. Everything before trap_dump (code and data) is compared byte
for byte, so a stray store anywhere in the image is caught.
"""

ISA_AS = "rv32imac_zicsr_zifencei_zba_zbb_zbs"
ISA_SPIKE = "rv32imac_zicsr_zifencei_zicntr_zba_zbb_zbs"
LOAD_ADDR = 0x10000
SPIKE_MEM_BASE = 0x10000
SPIKE_MEM_SIZE = 0x40000  # Spike RAM [0x10000, 0x50000); the runner's VM has [0, 0x50000)
SPIKE_MEM = f"0x{SPIKE_MEM_BASE:x}:0x{SPIKE_MEM_SIZE:x}"
DUMP_MARKER = 0x600DC0DE
# minstret as read by the handler's second instruction = boot ROM (5) + preamble
# (la + csrw = 3) + the handler's first instruction (1) + the instructions the test
# retired (a trapping instruction does not retire).
SPIKE_INSTRET_OFFSET = 9
DATA_SIZE = 2048

HEADER = """\
  .option norelax
  .option norvc
  .section .text.init, "ax"
  .globl _start
  .globl begin_signature
_start:
begin_signature:
  la t0, trap_handler
  csrw mtvec, t0
  .globl test_start
test_start:
"""


def trap_handler():
    lines = [
        "  .option norvc",
        "  .align 2",
        "trap_handler:",
        "  csrw sscratch, t6",
        "  csrr t6, minstret",  # = SPIKE_INSTRET_OFFSET + instructions the test retired
        "  csrw stval, t6",
        "  la t6, trap_dump",
    ]
    for i in range(1, 31):
        lines.append(f"  sw x{i}, {4 * i}(t6)")
    lines += [
        "  csrr x1, sscratch",
        "  sw x1, 124(t6)",
        "  csrr x1, mscratch",
        "  sw x1, 128(t6)",
        "  csrr x1, mcause",
        "  sw x1, 132(t6)",
        "  csrr x1, mepc",
        "  sw x1, 136(t6)",
        "  csrr x1, mtval",
        "  sw x1, 140(t6)",
        "  csrr x1, stval",
        "  sw x1, 144(t6)",
        f"  li x1, 0x{DUMP_MARKER:x}",
        "  sw x1, 0(t6)",
        "  li x1, 1",
        "  la t6, tohost",
        "  sw x1, 0(t6)",
        "  sw x0, 4(t6)",
        "1: j 1b",
    ]
    return "\n".join(lines) + "\n"


def signature_tail():
    """trap_dump, end_signature and the HTIF mailbox, after the data."""
    return "\n".join([
        "  .align 6",
        "  .globl trap_dump",
        "trap_dump:",
        "  .space 192",
        "  .align 6",
        "  .globl end_signature",
        "end_signature:",
        '  .section .tohost, "aw", @progbits',
        "  .align 6",
        "  .globl tohost",
        "tohost: .dword 0",
        "  .align 6",
        "  .globl fromhost",
        "fromhost: .dword 0",
    ]) + "\n"


def data_section(data_words):
    """data_words: DATA_SIZE/4 u32 values for the scratch region."""
    assert len(data_words) == DATA_SIZE // 4
    out = ["  .data", "  .align 6", "  .globl data_region", "data_region:"]
    for i in range(0, len(data_words), 8):
        out.append("  .word " + ", ".join(f"0x{w:08x}" for w in data_words[i:i + 8]))
    return "\n".join(out) + "\n" + signature_tail()


def indent(lines):
    """Indent instruction lines; labels ("name:") stay in column 0."""
    return ["  " + line if not line.endswith(":") else line for line in lines]


def assemble_program(body_lines, data_words):
    """Full assembly source: header + body + trap handler + data."""
    return HEADER + "\n".join(indent(body_lines)) + "\n" + trap_handler() + data_section(data_words)
