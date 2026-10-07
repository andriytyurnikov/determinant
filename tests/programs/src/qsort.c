#include "common.h"
#define N 4096
static uint32_t a[N];
typedef struct { uint32_t key; uint16_t tag; uint8_t pad; int8_t sval; } rec_t;
static rec_t recs[1024];

static void isort(uint32_t *v, int lo, int hi) {
    for (int i = lo + 1; i <= hi; i++) { uint32_t x = v[i]; int j = i - 1; while (j >= lo && v[j] > x) { v[j+1] = v[j]; j--; } v[j+1] = x; }
}
static void quick(uint32_t *v, int lo, int hi) {
    while (hi - lo > 16) {
        uint32_t p = v[lo + (hi - lo) / 2];
        int i = lo, j = hi;
        while (i <= j) {
            while (v[i] < p) i++;
            while (v[j] > p) j--;
            if (i <= j) { uint32_t t = v[i]; v[i] = v[j]; v[j] = t; i++; j--; }
        }
        if (j - lo < hi - i) { quick(v, lo, j); lo = i; } else { quick(v, i, hi); hi = j; }
    }
    isort(v, lo, hi);
}
/* generic qsort with byte-wise swap and comparator function pointer */
typedef int (*cmp_fn)(const void *, const void *);
static void bswap_bytes(uint8_t *x, uint8_t *y, size_t n) { while (n--) { uint8_t t = *x; *x++ = *y; *y++ = t; } }
static void gsort(void *base, size_t n, size_t sz, cmp_fn cmp) {
    uint8_t *b = base;
    if (n < 2) return;
    /* shell sort */
    for (size_t gap = n / 2; gap > 0; gap /= 2)
        for (size_t i = gap; i < n; i++)
            for (size_t j = i; j >= gap && cmp(b + (j - gap) * sz, b + j * sz) > 0; j -= gap)
                bswap_bytes(b + (j - gap) * sz, b + j * sz, sz);
}
static int cmp_rec(const void *x, const void *y) {
    const rec_t *p = x, *q = y;
    if (p->sval != q->sval) return p->sval < q->sval ? -1 : 1;
    if (p->key != q->key) return p->key < q->key ? -1 : 1;
    return (int)p->tag - (int)q->tag;
}
uint32_t prog_main(void) {
    uint32_t s = 2463534242u, acc = 0, sorted = 1;
    for (int r = 0; r < SCALE; r++) {
        for (int i = 0; i < N; i++) a[i] = xorshift32(&s) % 100000u;
        quick(a, 0, N - 1);
        for (int i = 1; i < N; i++) sorted &= a[i-1] <= a[i];
        for (int i = 0; i < N; i++) acc += a[i] * (uint32_t)(i + 1);
    }
    out[0] = acc; out[1] = sorted; out[2] = a[0]; out[3] = a[N-1]; out[4] = a[N/2];
    for (int i = 0; i < 1024; i++) { recs[i].key = xorshift32(&s) & 0xFF; recs[i].tag = (uint16_t)i; recs[i].pad = 0; recs[i].sval = (int8_t)(xorshift32(&s) & 0xFF); }
    gsort(recs, 1024, sizeof(rec_t), cmp_rec);
    uint32_t h = 2166136261u, ok = 1;
    for (int i = 0; i < 1024; i++) { h = fnv1a(h, recs[i].key); h = fnv1a(h, recs[i].tag); h = fnv1a(h, (uint32_t)(int32_t)recs[i].sval); if (i) ok &= cmp_rec(&recs[i-1], &recs[i]) <= 0; }
    out[5] = h; out[6] = ok;
    return acc ^ h;
}
