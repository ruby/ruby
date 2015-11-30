#include <string.h>

/* prevent the compiler from optimizing away memset or bzero */
void
explicit_bzero(void *p, size_t n)
{
    memset(p, 0, n);
}
