/* Flat image at address 0 for the Determinant corpus VM (256 KiB of memory).
   The stack starts at the top of that memory and grows down. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
PROVIDE(__stack_top = 0x40000);
SECTIONS
{
  . = 0;
  .text : { KEEP(*(.text.init)) *(.text .text.*) }
  .rodata : ALIGN(8) { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : ALIGN(8) { *(.data .data.*) }
  .sdata : ALIGN(8) {
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.* .sdata2 .sdata2.*)
  }
  . = ALIGN(8);
  __bss_start = .;
  .sbss (NOLOAD) : { *(.sbss .sbss.* .scommon) }
  .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) }
  . = ALIGN(8);
  __bss_end = .;
  /DISCARD/ : { *(.comment) *(.note .note.*) *(.eh_frame) *(.eh_frame_hdr) *(.riscv.attributes) }
}
