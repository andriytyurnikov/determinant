#include "common.h"
typedef struct { uint32_t h[8]; uint8_t buf[64]; uint32_t len_lo, len_hi; uint32_t fill; } sha256_ctx;
static const uint32_t K[64] = {
 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
static inline uint32_t ror(uint32_t x, unsigned n) { return (x >> n) | (x << ((32 - n) & 31)); }
static void compress(sha256_ctx *c, const uint8_t *p) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = ((uint32_t)p[4*i] << 24) | ((uint32_t)p[4*i+1] << 16) | ((uint32_t)p[4*i+2] << 8) | p[4*i+3];
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ror(w[i-15], 7) ^ ror(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ror(w[i-2], 17) ^ ror(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    uint32_t a=c->h[0],b=c->h[1],cc=c->h[2],d=c->h[3],e=c->h[4],f=c->h[5],g=c->h[6],h=c->h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ror(e, 6) ^ ror(e, 11) ^ ror(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + K[i] + w[i];
        uint32_t S0 = ror(a, 2) ^ ror(a, 13) ^ ror(a, 22);
        uint32_t mj = (a & b) ^ (a & cc) ^ (b & cc);
        uint32_t t2 = S0 + mj;
        h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0]+=a; c->h[1]+=b; c->h[2]+=cc; c->h[3]+=d; c->h[4]+=e; c->h[5]+=f; c->h[6]+=g; c->h[7]+=h;
}
static void init(sha256_ctx *c) {
    static const uint32_t iv[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    memcpy(c->h, iv, sizeof iv); c->len_lo = c->len_hi = 0; c->fill = 0;
}
static void update(sha256_ctx *c, const uint8_t *p, size_t n) {
    while (n) {
        size_t take = 64 - c->fill; if (take > n) take = n;
        memcpy(c->buf + c->fill, p, take);
        c->fill += take; p += take; n -= take;
        uint32_t old = c->len_lo; c->len_lo += (uint32_t)take * 8; if (c->len_lo < old) c->len_hi++;
        if (c->fill == 64) { compress(c, c->buf); c->fill = 0; }
    }
}
static void final(sha256_ctx *c, uint32_t dig[8]) {
    uint32_t lo = c->len_lo, hi = c->len_hi;
    uint8_t pad = 0x80; update(c, &pad, 1);
    uint8_t z = 0; while (c->fill != 56) update(c, &z, 1);
    uint8_t L[8];
    for (int i = 0; i < 4; i++) { L[i] = (uint8_t)(hi >> (24 - 8*i)); L[4+i] = (uint8_t)(lo >> (24 - 8*i)); }
    update(c, L, 8);
    for (int i = 0; i < 8; i++) dig[i] = c->h[i];
}
static uint8_t big[16384];
uint32_t prog_main(void) {
    sha256_ctx c; uint32_t d[8];
    init(&c); update(&c, (const uint8_t *)"abc", 3); final(&c, d);
    out[0] = d[0]; out[1] = d[7];            /* KAT: ba7816bf ... f20015ad */
    const char *m2 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    init(&c); update(&c, (const uint8_t *)m2, strlen(m2)); final(&c, d);
    out[2] = d[0]; out[3] = d[7];            /* KAT: 248d6a61 ... 19db06c1 */
    uint32_t s = 0xC0FFEEu;
    for (size_t i = 0; i < sizeof big; i++) big[i] = (uint8_t)xorshift32(&s);
    uint32_t acc = 0;
    for (int r = 0; r < SCALE; r++) {
        init(&c);
        for (size_t off = 0; off < sizeof big; off += 1000) update(&c, big + off, (sizeof big - off) < 1000 ? (sizeof big - off) : 1000);
        final(&c, d);
        for (int i = 0; i < 8; i++) acc = fnv1a(acc, d[i]);
        big[r & 16383] ^= (uint8_t)d[0];
    }
    out[4] = acc;
    out[5] = (out[0] == 0xba7816bfu) && (out[1] == 0xf20015adu) && (out[2] == 0x248d6a61u) && (out[3] == 0x19db06c1u);
    return out[0] ^ out[3] ^ out[4];
}
