#include "common.h"
static inline uint32_t rotl(uint32_t x, uint32_t r) { return (x << (r & 31)) | (x >> ((32 - r) & 31)); }
static inline uint32_t rotr(uint32_t x, uint32_t r) { return (x >> (r & 31)) | (x << ((32 - r) & 31)); }
static uint32_t tbl[64];
__attribute__((noinline)) static uint32_t idx3(const uint32_t *t, uint32_t i, uint32_t j) { return t[i & 63] + t[(i + j) & 63] * 3u + t[(2 * i + 1) & 63]; }
__attribute__((noinline)) static uint32_t ld64(const uint64_t *t, uint32_t i) { return (uint32_t)t[i & 7] ^ (uint32_t)(t[(i + 3) & 7] >> 32); }
uint32_t prog_main(void) {
    uint32_t s = 0xDEADBEEFu, h = 2166136261u;
    uint64_t t64[8];
    for (int i = 0; i < 64; i++) tbl[i] = xorshift32(&s);
    for (int i = 0; i < 8; i++) t64[i] = ((uint64_t)xorshift32(&s) << 32) | xorshift32(&s);
    for (uint32_t r = 0; r < 4000u * SCALE; r++) {
        uint32_t x = xorshift32(&s), y = xorshift32(&s), n = y & 31;
        uint32_t nz = x | 1u, nzh = x | 0x80000000u;
        h = fnv1a(h, (uint32_t)__builtin_clz(nz));
        h = fnv1a(h, (uint32_t)__builtin_ctz(nzh));
        h = fnv1a(h, (uint32_t)__builtin_popcount(x));
        h = fnv1a(h, __builtin_bswap32(x));
        uint64_t b64 = __builtin_bswap64(((uint64_t)x << 32) | y);
        h = fnv1a(h, (uint32_t)b64); h = fnv1a(h, (uint32_t)(b64 >> 32));
        h = fnv1a(h, rotl(x, n)); h = fnv1a(h, rotr(x, n)); h = fnv1a(h, rotr(y, 13));
        h = fnv1a(h, x & ~y); h = fnv1a(h, x | ~y); h = fnv1a(h, ~(x ^ y));
        int32_t sx = (int32_t)x, sy = (int32_t)y;
        h = fnv1a(h, (uint32_t)(sx < sy ? sx : sy)); h = fnv1a(h, (uint32_t)(sx > sy ? sx : sy));
        h = fnv1a(h, x < y ? x : y); h = fnv1a(h, x > y ? x : y);
        h = fnv1a(h, (uint32_t)(int32_t)(int8_t)x); h = fnv1a(h, (uint32_t)(int32_t)(int16_t)y); h = fnv1a(h, (uint16_t)x);
        h = fnv1a(h, x | (1u << n)); h = fnv1a(h, x & ~(1u << n)); h = fnv1a(h, x ^ (1u << n)); h = fnv1a(h, (x >> n) & 1u);
        h = fnv1a(h, x | (1u << 17)); h = fnv1a(h, x & ~(1u << 30)); h = fnv1a(h, x ^ (1u << 3)); h = fnv1a(h, (x >> 21) & 1u);
        h = fnv1a(h, idx3(tbl, x, y)); h = fnv1a(h, ld64(t64, y));
        h = fnv1a(h, (uint32_t)__builtin_parity(x) + (uint32_t)__builtin_clz(y | 1u) * 7u);
        /* orc.b-like zero-byte detection */
        uint32_t zb = (x - 0x01010101u) & ~x & 0x80808080u; h = fnv1a(h, zb);
        h = fnv1a(h, (uint32_t)__builtin_ffs((int)x));
    }
    out[0] = h;
    out[1] = (uint32_t)__builtin_clz(1u) | ((uint32_t)__builtin_ctz(0x80000000u) << 8) | ((uint32_t)__builtin_popcount(0xFFFFFFFFu) << 16);
    out[2] = __builtin_bswap32(0x11223344u);
    out[3] = rotl(0x80000001u, 1) ^ rotr(0x80000001u, 1);
    return h ^ out[1] ^ out[2];
}
