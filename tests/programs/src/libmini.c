/* Freestanding mini libc. Compile with -fno-builtin (and -fno-tree-loop-distribute-patterns on GCC)
   so these loops are not turned back into calls to themselves. */
#include "common.h"
uint32_t out[16];

void *memcpy(void *restrict d, const void *restrict s, size_t n) {
    uint8_t *dp = d; const uint8_t *sp = s;
    if ((((uintptr_t)dp | (uintptr_t)sp) & 3) == 0) {
        while (n >= 4) { *(uint32_t *)dp = *(const uint32_t *)sp; dp += 4; sp += 4; n -= 4; }
    }
    while (n--) *dp++ = *sp++;
    return d;
}
void *memmove(void *d, const void *s, size_t n) {
    uint8_t *dp = d; const uint8_t *sp = s;
    if (dp == sp || n == 0) return d;
    if (dp < sp) { while (n--) *dp++ = *sp++; }
    else { dp += n; sp += n; while (n--) *--dp = *--sp; }
    return d;
}
void *memset(void *d, int c, size_t n) {
    uint8_t *dp = d;
    while (n && ((uintptr_t)dp & 3)) { *dp++ = (uint8_t)c; n--; }
    uint32_t w = (uint8_t)c; w |= w << 8; w |= w << 16;
    while (n >= 4) { *(uint32_t *)dp = w; dp += 4; n -= 4; }
    while (n--) *dp++ = (uint8_t)c;
    return d;
}
int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a, *y = b;
    for (size_t i = 0; i < n; i++) if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
    return 0;
}
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
