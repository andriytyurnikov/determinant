/* Minimal crt0 for Determinant: the VM starts at pc = 0 with every register zero, so set gp and sp here. */
    .section .text.init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la    gp, __global_pointer$
    .option pop
    la    sp, __stack_top
    /* zero .sbss/.bss (VM memory starts zeroed, but do it anyway) */
    la    t0, __bss_start
    la    t1, __bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:
    call  prog_main
    /* a0 = checksum returned by prog_main, a1 = &out[0] (16 result words) */
    la    a1, out
    ebreak
3:  j     3b
