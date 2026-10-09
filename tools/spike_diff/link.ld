/* Linker script of the Spike differential tests: everything at 0x10000, the bottom of
   Spike's RAM (see template.py for the layout). */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x10000;
  .text : { *(.text.init) *(.text) }
  . = ALIGN(0x40);
  .data : { *(.data) }
  . = ALIGN(0x40);
  .tohost : { *(.tohost) }
  . = ALIGN(0x40);
  _end = .;
}
