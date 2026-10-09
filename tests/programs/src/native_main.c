/* Host wrapper: compiled together with one program source (which includes common.h). */
#include <stdio.h>

#include "common.h"
uint32_t out[16];
int main(void) {
    uint32_t r = prog_main();
    printf("a0=%08x out=", r);
    for (int i = 0; i < 16; i++) printf("%08x%s", out[i], i < 15 ? "," : "\n");
    return 0;
}
