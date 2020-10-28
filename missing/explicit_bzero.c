#ifndef __STDC_WANT_LIB_EXT1__
#define __STDC_WANT_LIB_EXT1__ 1
#endif

#include "ruby/missing.h"
#include <string.h>
#ifdef HAVE_MEMSET_S
# include <string.h>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

/* Similar to bzero(), but has a guarantee not to be eliminated from compiler
   optimization. */

/* OS support note:
 * BSDs have explicit_bzero().
 * macOS has memset_s().
 * Windows has SecureZeroMemory() since XP.
 * Linux has explicit_bzero() since glibc 2.25, musl libc 1.1.20.
 */

/*
 * Following URL explains why memset_s is added to the standard.
 * http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1381.pdf
 */

#ifndef FUNC_UNOPTIMIZED
# define FUNC_UNOPTIMIZED(x) x
#endif

#undef explicit_bzero
#ifndef HAVE_EXPLICIT_BZERO
 #ifdef HAVE_EXPLICIT_MEMSET
void
explicit_bzero(void *b, size_t len)
{
    (void)explicit_memset(b, 0, len);
}
 #elif defined HAVE_MEMSET_S
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

/* A weak function never be optimized away. Even if nobody uses it. */
WEAK(void ruby_explicit_bzero_hook_unused(void *buf, size_t len));
void
ruby_explicit_bzero_hook_unused(void *buf, size_t len)
{
}

void
explicit_bzero(void *b, size_t len)
{
    memset(b, 0, len);
    ruby_explicit_bzero_hook_unused(b, len);
}

 #else /* Your OS have no capability. Sigh. */

FUNC_UNOPTIMIZED(void explicit_bzero(void *b, size_t len));
#undef explicit_bzero

void
explicit_bzero(void *b, size_t len)
{
    /*
     * volatile is not enough if the compiler has an LTO (link time
     * optimization). At least, the standard provides no guarantee.
     * However, gcc and major other compilers never optimize a volatile
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
