#include <ruby/ruby.h>

#ifdef HAVE_RUBY_ATOMIC_H
# include <ruby/atomic.h>
#endif

#ifdef RUBY_ATOMIC_PTR_CAS
# define ATOMIC_PTR_CAS(var, old, new) RUBY_ATOMIC_PTR_CAS(var, old, new)
#endif

#undef strtod
#define strtod BigDecimal_strtod
#undef dtoa
#define dtoa BigDecimal_dtoa
#undef hdtoa
#define hdtoa BigDecimal_hdtoa
#include "missing/dtoa.c"
