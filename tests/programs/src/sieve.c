#include "common.h"
#define LIMIT 200000u
static uint8_t comp[LIMIT + 1];
static uint32_t bits[(LIMIT >> 5) + 1];
uint32_t prog_main(void) {
    uint32_t count = 0, sum = 0, last = 0, h = 0;
    for (int r = 0; r < SCALE; r++) {
        memset(comp, 0, sizeof comp);
        count = 0; sum = 0; last = 0;
        for (uint32_t i = 2; i * i <= LIMIT; i++)
            if (!comp[i]) for (uint32_t j = i * i; j <= LIMIT; j += i) comp[j] = 1;
        for (uint32_t i = 2; i <= LIMIT; i++) if (!comp[i]) { count++; sum += i; last = i; }
    }
    out[0] = count; out[1] = sum; out[2] = last;  /* pi(200000) = 17984 */
    /* bit-array sieve: exercises single-bit set/test (Zbs bset/bext patterns) */
    memset(bits, 0, sizeof bits);
    for (uint32_t i = 2; i * i <= LIMIT; i++)
        if (!((bits[i >> 5] >> (i & 31)) & 1u))
            for (uint32_t j = i * i; j <= LIMIT; j += i) bits[j >> 5] |= 1u << (j & 31);
    uint32_t c2 = 0;
    for (uint32_t i = 2; i <= LIMIT; i++) if (!((bits[i >> 5] >> (i & 31)) & 1u)) { c2++; h = h * 33u + i; }
    /* clear some bits again (bclr / binv patterns) */
    for (uint32_t i = 0; i < 1000; i++) { bits[i >> 5] &= ~(1u << (i & 31)); bits[(i * 7) >> 5] ^= 1u << ((i * 7) & 31); }
    uint32_t h2 = 0; for (uint32_t i = 0; i < 64; i++) h2 = fnv1a(h2, bits[i]);
    out[3] = c2; out[4] = h; out[5] = h2;
    return count ^ sum ^ h ^ h2;
}
