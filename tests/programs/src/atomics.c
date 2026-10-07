#include "common.h"
static uint32_t counter, flags, mx, mn = 0xFFFFFFFFu;
static int32_t smax = -2147483647 - 1, smin = 2147483647;
static uint32_t lock;
static uint8_t b8[4];
static uint16_t h16[2];
static uint32_t stack_top, nodes[64];   /* index-based Treiber stack, 0 = empty */
static void push(uint32_t idx) { uint32_t old = __atomic_load_n(&stack_top, __ATOMIC_ACQUIRE);
    do { nodes[idx] = old; } while (!__atomic_compare_exchange_n(&stack_top, &old, idx, 1, __ATOMIC_RELEASE, __ATOMIC_RELAXED)); }
static uint32_t pop(void) { uint32_t old = __atomic_load_n(&stack_top, __ATOMIC_ACQUIRE);
    while (old && !__atomic_compare_exchange_n(&stack_top, &old, nodes[old], 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {}
    return old; }
static void spin_lock(uint32_t *l) { while (__atomic_exchange_n(l, 1u, __ATOMIC_ACQUIRE)) {} }
static void spin_unlock(uint32_t *l) { __atomic_store_n(l, 0u, __ATOMIC_RELEASE); }
uint32_t prog_main(void) {
    uint32_t s = 0xA5A5A5A5u, h = 2166136261u;
    for (uint32_t i = 1; i <= 2000u * SCALE; i++) {
        uint32_t v = xorshift32(&s);
        h = fnv1a(h, __atomic_fetch_add(&counter, v & 0xFFFF, __ATOMIC_SEQ_CST));
        h = fnv1a(h, __atomic_fetch_sub(&counter, i, __ATOMIC_RELAXED));
        h = fnv1a(h, __atomic_fetch_xor(&flags, v, __ATOMIC_ACQ_REL));
        h = fnv1a(h, __atomic_fetch_or(&flags, 1u << (i & 31), __ATOMIC_SEQ_CST));
        h = fnv1a(h, __atomic_fetch_and(&flags, ~(1u << (v & 31)), __ATOMIC_SEQ_CST));
        h = fnv1a(h, __atomic_exchange_n(&mx, v, __ATOMIC_SEQ_CST));
        uint32_t exp = v ^ 1; h = fnv1a(h, (uint32_t)__atomic_compare_exchange_n(&mx, &exp, i, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)); h = fnv1a(h, exp);
        exp = v; h = fnv1a(h, (uint32_t)__atomic_compare_exchange_n(&mx, &exp, i, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)); h = fnv1a(h, exp);
#ifdef __clang__
        h = fnv1a(h, __atomic_fetch_max(&mx, v >> 3, __ATOMIC_SEQ_CST));
        h = fnv1a(h, __atomic_fetch_min(&mn, v, __ATOMIC_SEQ_CST));
        h = fnv1a(h, (uint32_t)__atomic_fetch_max(&smax, (int32_t)v, __ATOMIC_SEQ_CST));
        h = fnv1a(h, (uint32_t)__atomic_fetch_min(&smin, (int32_t)v, __ATOMIC_SEQ_CST));
#else
        { uint32_t o = __atomic_load_n(&mx, __ATOMIC_RELAXED); while (o < (v >> 3) && !__atomic_compare_exchange_n(&mx, &o, v >> 3, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED)) {} h = fnv1a(h, o); }
        { uint32_t o = __atomic_load_n(&mn, __ATOMIC_RELAXED); while (o > v && !__atomic_compare_exchange_n(&mn, &o, v, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED)) {} h = fnv1a(h, o); }
        { int32_t o = __atomic_load_n(&smax, __ATOMIC_RELAXED); while (o < (int32_t)v && !__atomic_compare_exchange_n(&smax, &o, (int32_t)v, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED)) {} h = fnv1a(h, (uint32_t)o); }
        { int32_t o = __atomic_load_n(&smin, __ATOMIC_RELAXED); while (o > (int32_t)v && !__atomic_compare_exchange_n(&smin, &o, (int32_t)v, 1, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED)) {} h = fnv1a(h, (uint32_t)o); }
#endif
        /* sub-word atomics: masked LR/SC sequences */
        h = fnv1a(h, __atomic_fetch_add(&b8[i & 3], (uint8_t)v, __ATOMIC_SEQ_CST));
        h = fnv1a(h, __atomic_fetch_add(&h16[i & 1], (uint16_t)(v >> 7), __ATOMIC_SEQ_CST));
        uint8_t e8 = b8[(i + 1) & 3]; h = fnv1a(h, (uint32_t)__atomic_compare_exchange_n(&b8[(i + 1) & 3], &e8, (uint8_t)(e8 + 3), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST));
        h = fnv1a(h, __sync_fetch_and_add(&counter, 3u));
        h = fnv1a(h, __sync_val_compare_and_swap(&counter, counter, counter + 5u));
        spin_lock(&lock); counter += 1; spin_unlock(&lock);
        __sync_synchronize();
        if (i % 3 == 0) { uint32_t p = pop(); if (p) push(p); }
        push((i % 63) + 1);
        if (i % 2 == 0) h = fnv1a(h, pop());
    }
    uint32_t chain = 0; for (uint32_t p = stack_top, k = 0; p && k < 10000; p = nodes[p], k++) chain = chain * 31u + p;
    out[0] = h; out[1] = counter; out[2] = flags; out[3] = mx; out[4] = mn;
    out[5] = (uint32_t)smax; out[6] = (uint32_t)smin; out[7] = b8[0] | (b8[1] << 8) | (b8[2] << 16) | ((uint32_t)b8[3] << 24);
    out[8] = h16[0] | ((uint32_t)h16[1] << 16); out[9] = chain; out[10] = lock;
    return h ^ counter ^ chain;
}
