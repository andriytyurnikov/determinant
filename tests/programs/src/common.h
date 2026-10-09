#ifndef COMMON_H
#define COMMON_H
#include <stdint.h>
#include <stddef.h>

/* 16 result words; crt0 hands their address to the host in a1. */
extern uint32_t out[16];
uint32_t prog_main(void);

void *memcpy(void *restrict d, const void *restrict s, size_t n);
void *memmove(void *d, const void *s, size_t n);
void *memset(void *d, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);

#ifndef SCALE
#define SCALE 1
#endif

static inline uint32_t xorshift32(uint32_t *s) {
    uint32_t x = *s;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return *s = x;
}
static inline uint32_t fnv1a(uint32_t h, uint32_t v) {
    for (int i = 0; i < 4; i++) { h ^= (v >> (8 * i)) & 0xFF; h *= 16777619u; }
    return h;
}
#endif
