#include "ruby/assert.h"

#if !defined(__STDC_VERSION__) || (__STDC_VERSION__ < 199901L)
/* C89 compilers are required to support strings of only 509 chars. */
/* can't use RUBY_ASSERT for such compilers. */
#include <assert.h>
#else
#undef assert
#define assert RUBY_ASSERT
#endif

#ifdef NDEBUG
  #undef  RUBY_NDEBUG
  #define RUBY_NDEBUG 1
#endif
