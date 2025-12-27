// Custom test environment for Determinant RISC-V VM.
//
// Replaces the standard p/riscv_test.h which assumes M-mode privilege
// (mtvec, mstatus, medeleg, PMP, mret). Our VM runs user-level code only,
// starting at address 0x0 with flat physical memory and no privilege modes.
//
// Convention: gp (x3) = 1 means PASS, gp = (N<<1|1) means test case N failed.
// Termination via EBREAK (not ECALL, since some tests exercise ECALL).

#ifndef _ENV_DETERMINANT_H
#define _ENV_DETERMINANT_H

// encoding.h provides CAUSE_*, CSR addresses, etc. — needed by test_macros.h
// Located in riscv-tests-src/env/, added to include path via -I in Makefile
#include "encoding.h"

//-----------------------------------------------------------------------
// Privilege mode macros — all no-ops for user-level VM
//-----------------------------------------------------------------------

#define RVTEST_RV32U   .macro init; .endm
#define RVTEST_RV64U   .macro init; .endm
#define RVTEST_RV32UF  .macro init; .endm
#define RVTEST_RV64UF  .macro init; .endm

// Machine/supervisor mode — should not appear in rv32u* tests, but
// define as empty to avoid preprocessor errors if referenced.
#define RVTEST_RV32M   .macro init; .endm
#define RVTEST_RV64M   .macro init; .endm
#define RVTEST_RV32S   .macro init; .endm
#define RVTEST_RV64S   .macro init; .endm

//-----------------------------------------------------------------------
// Code section macros
//-----------------------------------------------------------------------

#define RVTEST_CODE_BEGIN                                                \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        /* Zero all registers */                                        \
        li x1, 0;                                                       \
        li x2, 0;                                                       \
        li x3, 0;                                                       \
        li x4, 0;                                                       \
        li x5, 0;                                                       \
        li x6, 0;                                                       \
        li x7, 0;                                                       \
        li x8, 0;                                                       \
        li x9, 0;                                                       \
        li x10, 0;                                                      \
        li x11, 0;                                                      \
        li x12, 0;                                                      \
        li x13, 0;                                                      \
        li x14, 0;                                                      \
        li x15, 0;                                                      \
        li x16, 0;                                                      \
        li x17, 0;                                                      \
        li x18, 0;                                                      \
        li x19, 0;                                                      \
        li x20, 0;                                                      \
        li x21, 0;                                                      \
        li x22, 0;                                                      \
        li x23, 0;                                                      \
        li x24, 0;                                                      \
        li x25, 0;                                                      \
        li x26, 0;                                                      \
        li x27, 0;                                                      \
        li x28, 0;                                                      \
        li x29, 0;                                                      \
        li x30, 0;                                                      \
        li x31, 0;                                                      \
        init;

#define RVTEST_CODE_END                                                 \
        unimp

//-----------------------------------------------------------------------
// Pass/Fail macros
//-----------------------------------------------------------------------

#define TESTNUM gp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        ebreak

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        ebreak

//-----------------------------------------------------------------------
// Data section macros
//-----------------------------------------------------------------------

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

//-----------------------------------------------------------------------
// Helpers used by test_macros.h
//-----------------------------------------------------------------------

// CHECK_XLEN: verify we're running on RV32 (sign bit set after slli by 31)
#if __riscv_xlen == 64
# define CHECK_XLEN li a0, 1; slli a0, a0, 31; bgez a0, 1f; RVTEST_PASS; 1:
#else
# define CHECK_XLEN li a0, 1; slli a0, a0, 31; bltz a0, 1f; RVTEST_PASS; 1:
#endif

// Extras — not needed but must be defined to avoid preprocessor errors
#define EXTRA_TVEC_USER
#define EXTRA_TVEC_MACHINE
#define EXTRA_INIT
#define EXTRA_INIT_TIMER
#define FILTER_TRAP
#define FILTER_PAGE_FAULT

#endif
