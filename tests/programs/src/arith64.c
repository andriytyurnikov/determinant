#include "common.h"
static uint64_t xs64(uint64_t *s) { uint64_t x = *s; x ^= x << 13; x ^= x >> 7; x ^= x << 17; return *s = x; }
static uint64_t mulmod(uint64_t a, uint64_t b, uint64_t m) { /* double-and-add, no 128-bit */
    uint64_t r = 0; a %= m;
    while (b) { if (b & 1) { r += a; if (r >= m) r -= m; } a <<= 1; if (a >= m) a -= m; b >>= 1; }
    return r;
}
static uint64_t powmod(uint64_t b, uint64_t e, uint64_t m) { uint64_t r = 1 % m; b %= m; while (e) { if (e & 1) r = mulmod(r, b, m); b = mulmod(b, b, m); e >>= 1; } return r; }
static uint32_t isqrt64(uint64_t n) { uint64_t x = n, y = x / 2 + (x & 1); if (n < 2) return (uint32_t)n; while (y < x) { x = y; y = (x + n / x) / 2; } return (uint32_t)x; }
static uint64_t gcd64(uint64_t a, uint64_t b) { while (b) { uint64_t t = a % b; a = b; b = t; } return a; }
uint32_t prog_main(void) {
    uint64_t s = 88172645463325252ull;
    uint32_t h = 2166136261u, bad = 0;
    for (int r = 0; r < 2000 * SCALE; r++) {
        uint64_t a = xs64(&s), b = xs64(&s) >> (r % 61);
        if (b == 0) b = 7;
        uint64_t q = a / b, m = a % b;
        if (q * b + m != a || m >= b) bad++;
        int64_t sa = (int64_t)a, sb = (int64_t)b; if (r & 1) sb = -sb; if (sb == 0) sb = 3;
        if (sa == INT64_MIN) sa++;
        int64_t sq = sa / sb, sm = sa % sb;
        if (sq * sb + sm != sa) bad++;
        uint64_t p = a * b;                     /* __muldi3 or mul/mulhu sequence */
        uint32_t a32 = (uint32_t)a, b32 = (uint32_t)(b | 1);
        uint32_t hi = (uint32_t)(((uint64_t)a32 * (uint64_t)b32) >> 32);           /* mulhu */
        int32_t shi = (int32_t)(((int64_t)(int32_t)a32 * (int64_t)(int32_t)b32) >> 32);  /* mulh */
        int32_t sxu = (int32_t)(((int64_t)(int32_t)a32 * (int64_t)(uint64_t)b32) >> 32); /* mulhsu */
        int32_t dv = (int32_t)(b32 | 0x100); if (dv == -1) dv = -3;
        int32_t d32 = (int32_t)a32 / dv, r32 = (int32_t)a32 % dv;
        h = fnv1a(h, (uint32_t)q); h = fnv1a(h, (uint32_t)(q >> 32)); h = fnv1a(h, (uint32_t)m);
        h = fnv1a(h, (uint32_t)sq); h = fnv1a(h, (uint32_t)((uint64_t)sm >> 32));
        h = fnv1a(h, (uint32_t)p); h = fnv1a(h, (uint32_t)(p >> 32));
        h = fnv1a(h, hi); h = fnv1a(h, (uint32_t)shi); h = fnv1a(h, (uint32_t)sxu);
        h = fnv1a(h, (uint32_t)d32); h = fnv1a(h, (uint32_t)r32); h = fnv1a(h, a32 / b32); h = fnv1a(h, a32 % b32);
    }
    out[0] = h; out[1] = bad;
    out[2] = (uint32_t)powmod(2, 1000000007ull - 1, 1000000007ull);           /* Fermat: 1 */
    uint64_t pm = powmod(0x123456789ull, 0xFEDCBA987ull, 0xFFFFFFFFFFFFFFC5ull); /* 2^64-59 prime */
    out[3] = (uint32_t)pm; out[4] = (uint32_t)(pm >> 32);
    out[5] = isqrt64(0xFFFFFFFFFFFFFFFFull); out[6] = isqrt64(1000000000000ull);
    out[7] = (uint32_t)gcd64(0x123456789ABCDEF0ull, 0x0FEDCBA987654321ull);
    uint64_t f = 1; for (uint32_t i = 1; i <= 20; i++) f *= i; out[8] = (uint32_t)(f % 1000000007ull); out[9] = (uint32_t)(f / 1000000007ull);
    return h ^ out[3] ^ out[5];
}
