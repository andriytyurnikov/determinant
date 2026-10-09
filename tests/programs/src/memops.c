#include "common.h"
typedef struct { uint8_t tag; uint16_t id; uint32_t val; uint64_t big; int8_t s8; int16_t s16; uint8_t name[13]; uint32_t arr[7]; } item_t;
static item_t items[256], copy[256];
static uint8_t arena[16384], arena2[16384];
static uint32_t ring[37];
static item_t make(uint32_t *s, uint32_t i) {
    item_t it; memset(&it, 0, sizeof it);
    it.tag = (uint8_t)i; it.id = (uint16_t)(i * 7); it.val = xorshift32(s);
    it.big = ((uint64_t)xorshift32(s) << 32) | xorshift32(s);
    it.s8 = (int8_t)xorshift32(s); it.s16 = (int16_t)xorshift32(s);
    for (int k = 0; k < 13; k++) it.name[k] = (uint8_t)('a' + (i + k) % 26);
    for (int k = 0; k < 7; k++) it.arr[k] = it.val ^ (uint32_t)k;
    return it;                                 /* returned by value: hidden sret + memcpy */
}
static uint32_t hash_item(uint32_t h, const item_t *it) {
    h = fnv1a(h, it->tag); h = fnv1a(h, it->id); h = fnv1a(h, it->val); h = fnv1a(h, (uint32_t)it->big); h = fnv1a(h, (uint32_t)(it->big >> 32));
    h = fnv1a(h, (uint32_t)(int32_t)it->s8); h = fnv1a(h, (uint32_t)(int32_t)it->s16);
    for (int k = 0; k < 13; k++) h = fnv1a(h, it->name[k]);
    for (int k = 0; k < 7; k++) h = fnv1a(h, it->arr[k]);
    return h;
}
static void put_le32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static uint32_t get_le32(const uint8_t *p) { return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint32_t utoa10(uint32_t v, uint8_t *buf) { uint8_t t[10]; uint32_t n = 0; do { t[n++] = (uint8_t)('0' + v % 10); v /= 10; } while (v); for (uint32_t i = 0; i < n; i++) buf[i] = t[n - 1 - i]; return n; }
uint32_t prog_main(void) {
    uint32_t s = 0x9E3779B9u, h = 2166136261u;
    for (int r = 0; r < SCALE; r++) {
        for (uint32_t i = 0; i < 256; i++) items[i] = make(&s, i);
        for (uint32_t i = 0; i < 256; i++) copy[255 - i] = items[i];          /* struct assignment */
        for (uint32_t i = 1; i < 256; i++) {                                   /* insertion sort by val (struct swaps) */
            item_t x = copy[i]; int j = (int)i - 1;
            while (j >= 0 && copy[j].val > x.val) { copy[j + 1] = copy[j]; j--; }
            copy[j + 1] = x;
        }
        for (uint32_t i = 0; i < 256; i += 5) h = hash_item(h, &copy[i]);
        /* memset / memcpy / memmove at odd offsets and sizes */
        for (uint32_t i = 0; i < sizeof arena; i++) arena[i] = (uint8_t)(i * 31 + (i >> 7));
        for (uint32_t k = 0; k < 200; k++) {
            uint32_t off = xorshift32(&s) % 8000, len = xorshift32(&s) % 4000, off2 = xorshift32(&s) % 8000;
            switch (k % 4) {
            case 0: memset(arena + off, (int)(k & 0xFF), len); break;
            case 1: memcpy(arena2 + off2, arena + off, len); break;
            case 2: memmove(arena + off + (k % 7), arena + off, len); break;   /* overlapping forward */
            case 3: memmove(arena + off, arena + off + (k % 9) + 1, len); break; /* overlapping backward */
            }
        }
        for (uint32_t i = 0; i < sizeof arena; i += 4) h = fnv1a(h, get_le32(arena + i) ^ get_le32(arena2 + i));
        { int c1 = memcmp(arena, arena2, 4096), c2 = memcmp(arena + 1, arena + 1, 1000); h = fnv1a(h, (uint32_t)((c1 > 0) - (c1 < 0) + 2)); h = fnv1a(h, (uint32_t)((c2 > 0) - (c2 < 0) + 2)); }
        /* serialization round trip */
        uint8_t ser[64]; for (int k = 0; k < 16; k++) put_le32(ser + 4 * k, xorshift32(&s));
        for (int k = 0; k < 16; k++) h = fnv1a(h, get_le32(ser + 4 * k));
        /* ring buffer with modulo indexing */
        for (uint32_t k = 0; k < 1000; k++) ring[(k * 5) % 37] += k ^ ring[(k + 3) % 37];
        for (int k = 0; k < 37; k++) h = fnv1a(h, ring[k]);
        /* decimal formatting (div/rem by 10) */
        uint8_t num[16]; uint32_t tot = 0;
        for (uint32_t k = 0; k < 500; k++) { uint32_t n = utoa10(xorshift32(&s), num); for (uint32_t q = 0; q < n; q++) tot = tot * 131u + num[q]; }
        h = fnv1a(h, tot);
        /* large stack object, compound literal */
        item_t local[8]; for (int k = 0; k < 8; k++) local[k] = (item_t){ .tag = (uint8_t)k, .id = (uint16_t)(k * 3), .val = (uint32_t)k * 1000u, .s8 = (int8_t)(-k) };
        for (int k = 0; k < 8; k++) h = hash_item(h, &local[k]);
    }
    out[0] = h; out[1] = copy[0].val; out[2] = copy[255].val; out[3] = (uint32_t)sizeof(item_t);
    return h;
}
