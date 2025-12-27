/* Linker script for Determinant RISC-V VM compliance tests.
 *
 * Origin at 0x0 (not 0x80000000 as in standard riscv-tests).
 * Simple flat memory layout — no virtual memory, no tohost section.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x0;

    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
    }

    . = ALIGN(4);

    .data : {
        *(.data)
        *(.data.*)
        *(.rodata)
        *(.rodata.*)
    }

    . = ALIGN(4);

    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    }

    /* Signature sections used by some tests */
    . = ALIGN(4);
    .signature : {
        *(.signature)
    }

    /* Discard tohost/fromhost — we use EBREAK, not HTIF */
    /DISCARD/ : {
        *(.tohost)
    }
}
