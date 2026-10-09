#include "common.h"
static uint32_t table[256];
static uint8_t buf[8192];

static void make_table(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        table[i] = c;
    }
}
static uint32_t crc32_tab(const uint8_t *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    while (n--) c = table[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}
static uint32_t crc32_bit(const uint8_t *p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) { uint32_t mask = -(c & 1); c = (c >> 1) ^ (0xEDB88320u & mask); }
    }
    return ~c;
}
uint32_t prog_main(void) {
    make_table();
    out[0] = crc32_tab((const uint8_t *)"123456789", 9); /* KAT: 0xCBF43926 */
    out[1] = crc32_bit((const uint8_t *)"123456789", 9);
    uint32_t s = 0x12345678u;
    for (size_t i = 0; i < sizeof buf; i++) buf[i] = (uint8_t)xorshift32(&s);
    uint32_t a = 0, b = 0;
    for (int r = 0; r < SCALE; r++) { a ^= crc32_tab(buf, sizeof buf); b ^= crc32_bit(buf, sizeof buf); buf[r & 8191]++; }
    out[2] = a; out[3] = b;
    uint32_t acc = 0;
    for (size_t off = 0; off < 64; off++) acc = acc * 31u + crc32_tab(buf + off, 1000 + off);
    out[4] = acc;
    out[5] = (out[0] == 0xCBF43926u) && (out[1] == 0xCBF43926u);
    return out[0] ^ out[2] ^ out[3] ^ out[4];
}
