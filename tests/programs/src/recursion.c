#include "common.h"
static uint32_t fib(uint32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static uint32_t calls;
static uint32_t ack(uint32_t m, uint32_t n) { calls++; if (m == 0) return n + 1; if (n == 0) return ack(m - 1, 1); return ack(m - 1, ack(m, n - 1)); }
static uint32_t moves;
static void hanoi(int n, int a, int b, int c) { if (n == 0) return; hanoi(n - 1, a, c, b); moves = moves * 3u + (uint32_t)(a * 7 + c); hanoi(n - 1, b, a, c); }
static int is_odd(uint32_t n);
static int is_even(uint32_t n) { return n == 0 ? 1 : is_odd(n - 1); }
static int is_odd(uint32_t n) { return n == 0 ? 0 : is_even(n - 1); }
/* recursive-descent expression evaluator */
static const char *P;
static int32_t expr(void);
static int32_t atom(void) {
    if (*P == '(') { P++; int32_t v = expr(); P++; return v; }
    if (*P == '-') { P++; return -atom(); }
    int32_t v = 0; while (*P >= '0' && *P <= '9') v = v * 10 + (*P++ - '0'); return v;
}
static int32_t term(void) {
    int32_t v = atom();
    for (;;) {
        if (*P == '*') { P++; v *= atom(); }
        else if (*P == '/') { P++; int32_t d = atom(); v = d ? v / d : 0; }
        else if (*P == '%') { P++; int32_t d = atom(); v = d ? v % d : 0; }
        else return v;
    }
}
static int32_t expr(void) {
    int32_t v = term();
    for (;;) { if (*P == '+') { P++; v += term(); } else if (*P == '-') { P++; v -= term(); } else return v; }
}
static uint32_t depth_sum(uint32_t n, volatile uint32_t *sink) { uint32_t local[4] = {n, n * 2, n * 3, n ^ 0x55}; *sink += local[n & 3]; return n ? local[(n + 1) & 3] + depth_sum(n - 1, sink) : 0; }
uint32_t prog_main(void) {
    out[0] = fib(24 + (SCALE > 1 ? 4 : 0));     /* 46368 */
    out[1] = ack(2, 200); out[2] = ack(3, 6); out[3] = calls;  /* 403, 509 */
    hanoi(16, 1, 2, 3); out[4] = moves;
    out[5] = (uint32_t)is_even(3001) | ((uint32_t)is_odd(2999) << 1);
    P = "((12+34)*5-(-7)/2+100%7)*(3-(4-(5*(6+7))))-123456/(1+2*(3+4))"; out[6] = (uint32_t)expr();
    P = "2*3*4*5*6*7*8*9*10-1-2-3-4-5-6-7-8-9-(10*(11+(12*(13+(14*(15+16))))))"; out[7] = (uint32_t)expr();
    volatile uint32_t sink = 0; out[8] = depth_sum(2000, &sink); out[9] = sink;
    return out[0] ^ out[2] ^ out[3] ^ out[4] ^ out[6] ^ out[8];
}
