#include "ruby/missing.h"
#include <string.h>

/*
 *BSD have explicit_bzero().
 Windows, OS-X have memset_s().
 Linux has none. *Sigh*
*/

#ifndef HAVE_EXPLICIT_BZERO
/* Similar to bzero(), but have a guarantee not to be eliminated from compiler
   optimization. */
void
explicit_bzero(void *b, size_t len)
{
#ifdef HAVE_MEMSET_S
    memset_s(b, len, 0, len);
#else
    {
	/*
	 * TODO: volatile is not enough if compiler have a LTO (link time
	 * optimization)
	 */
	volatile char* p = (volatile char*)b;

	while(len) {
	    *p = 0;
	    p++;
	    len--;
	}
    }
#endif
}
#endif
