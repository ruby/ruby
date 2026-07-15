#include "ruby/missing.h"

void *
memrchr(const void *ptr, int ch, size_t len)
{
    const unsigned char *p = (const unsigned char *)ptr + len;

    while (p > (const unsigned char *)ptr) {
        if (*--p == (unsigned char)ch) return (void *)p;
    }
    return NULL;
}
