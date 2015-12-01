#include "ruby/missing.h"
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

/* Similar to bzero(), but have a guarantee not to be eliminated from compiler
   optimization. */

/* OS support note:
 * BSD have explicit_bzero().
 * Windows, OS-X have memset_s().
 * Linux has none. *Sigh*
 */

/*
 * Following URL explain why memset_s is added to the standard.
 * http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1381.pdf
 */

#ifndef FUNC_UNOPTIMIZED
# define FUNC_UNOPTIMIZED(x) x
#endif

#ifndef HAVE_EXPLICIT_BZERO
 #ifdef HAVE_MEMSET_S
void
explicit_bzero(void *b, size_t len)
{
    memset_s(b, len, 0, len);
}
 #elif defined SecureZeroMemory
void
explicit_bzero(void *b, size_t len)
{
    SecureZeroMemory(b, len);
}

 #elif defined HAVE_FUNC_WEAK

/* A weak function never be optimization away. Even if nobody use it. */
WEAK(void ruby_explicit_bzero_hook_unused(void *buf, size_t len));
void
ruby_explicit_bzero_hook_unused(void *buf, size_t len)
{
}

void
explicit_bzero(void *b, size_t len)
{
    memset(b, len);
    ruby_explicit_bzero_hook_unused(b, len);
}

 #else /* Your OS have no capability. Sigh. */

FUNC_UNOPTIMIZED(void explicit_bzero(void *b, size_t len));
#undef explicit_bzero

void
explicit_bzero(void *b, size_t len)
{
    /*
     * volatile is not enough if compiler have a LTO (link time
     * optimization). At least, the standard provide no guarantee.
     * However, gcc and major other compiler never optimization a volatile
     * variable away. So, using volatile is practically ok.
     */
    volatile char* p = (volatile char*)b;

    while(len) {
	*p = 0;
	p++;
	len--;
    }
}
 #endif
#endif /* HAVE_EXPLICIT_BZERO */
