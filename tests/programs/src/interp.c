#include "common.h"
/* Tiny stack bytecode interpreter: dense switch (jump table) + function-pointer table. */
enum { OP_PUSH, OP_LOAD, OP_STORE, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_LT, OP_JZ, OP_JMP, OP_DUP, OP_POP, OP_XOR, OP_SHL, OP_SHR, OP_CALLF, OP_HALT };
typedef uint32_t (*fn_t)(uint32_t, uint32_t);
static uint32_t f_add(uint32_t a, uint32_t b) { return a + b; }
static uint32_t f_rot(uint32_t a, uint32_t b) { return (a << (b & 31)) | (a >> ((32 - b) & 31)); }
static uint32_t f_mix(uint32_t a, uint32_t b) { return (a ^ b) * 0x9E3779B1u; }
static uint32_t f_min(uint32_t a, uint32_t b) { return a < b ? a : b; }
static const fn_t ftab[4] = { f_add, f_rot, f_mix, f_min };
static uint32_t run(const int32_t *code, uint32_t *vars) {
    uint32_t st[64]; int sp = 0, pc = 0; uint32_t steps = 0;
    for (;;) {
        steps++;
        int32_t op = code[pc++];
        switch (op) {
        case OP_PUSH: st[sp++] = (uint32_t)code[pc++]; break;
        case OP_LOAD: st[sp++] = vars[code[pc++]]; break;
        case OP_STORE: vars[code[pc++]] = st[--sp]; break;
        case OP_ADD: sp--; st[sp-1] += st[sp]; break;
        case OP_SUB: sp--; st[sp-1] -= st[sp]; break;
        case OP_MUL: sp--; st[sp-1] *= st[sp]; break;
        case OP_DIV: sp--; st[sp-1] = st[sp] ? st[sp-1] / st[sp] : 0; break;
        case OP_MOD: sp--; st[sp-1] = st[sp] ? st[sp-1] % st[sp] : 0; break;
        case OP_LT: sp--; st[sp-1] = st[sp-1] < st[sp]; break;
        case OP_JZ: { int32_t t = code[pc++]; if (!st[--sp]) pc = t; break; }
        case OP_JMP: pc = code[pc]; break;
        case OP_DUP: st[sp] = st[sp-1]; sp++; break;
        case OP_POP: sp--; break;
        case OP_XOR: sp--; st[sp-1] ^= st[sp]; break;
        case OP_SHL: sp--; st[sp-1] <<= (st[sp] & 31); break;
        case OP_SHR: sp--; st[sp-1] >>= (st[sp] & 31); break;
        case OP_CALLF: { int32_t f = code[pc++]; sp--; st[sp-1] = ftab[f & 3](st[sp-1], st[sp]); break; }
        case OP_HALT: return steps;
        default: return 0xFFFFFFFFu;
        }
    }
}
/* vars: 0=i 1=acc 2=n 3=collatz x 4=collatz steps */
static const int32_t prog[] = {
    /* 0 */ OP_PUSH, 0, OP_STORE, 0,
    /* 4 loop: if !(i < n) goto end */ OP_LOAD, 0, OP_LOAD, 2, OP_LT, OP_JZ, 60,
    /* 11 acc = f[i&3](acc ^ i*i, i) */ OP_LOAD, 1, OP_LOAD, 0, OP_LOAD, 0, OP_MUL, OP_XOR, OP_LOAD, 0, OP_CALLF, 2, OP_STORE, 1,
    /* 25 acc += (acc >> 7) % 1000 / 3 */ OP_LOAD, 1, OP_DUP, OP_PUSH, 7, OP_SHR, OP_PUSH, 1000, OP_MOD, OP_PUSH, 3, OP_DIV, OP_ADD, OP_STORE, 1,
    /* 40 acc = rot(acc, i) min-ish */ OP_LOAD, 1, OP_LOAD, 0, OP_CALLF, 1, OP_PUSH, 0, OP_ADD, OP_STORE, 1,
    /* 51 i++ */ OP_LOAD, 0, OP_PUSH, 1, OP_ADD, OP_STORE, 0, OP_JMP, 4,
    /* 60 end */ OP_HALT };
uint32_t prog_main(void) {
    uint32_t vars[8] = {0, 12345, 3000u * SCALE, 0, 0, 0, 0, 0};
    uint32_t steps = run(prog, vars);
    out[0] = vars[1]; out[1] = steps; out[2] = vars[0];
    /* direct function-pointer dispatch loop */
    uint32_t a = 1, s = 7;
    for (uint32_t i = 0; i < 5000; i++) a = ftab[xorshift32(&s) & 3](a, i);
    out[3] = a;
    return vars[1] ^ steps ^ a;
}
