#include "ruby/ruby.h"

void
Init_sizes(void)
{
    VALUE s = rb_hash_new();
    rb_define_const(rb_define_module("RbConfig"), "SIZEOF", s);

#define DEFINE(type, size) rb_hash_aset(s, rb_str_new_cstr(#type), INT2FIX(SIZEOF_##size));

#if SIZEOF_INT != 0
    DEFINE(int, INT);
#endif
#if SIZEOF_SHORT != 0
    DEFINE(short, SHORT);
#endif
#if SIZEOF_LONG != 0
    DEFINE(long, LONG);
#endif
#if SIZEOF_LONG_LONG != 0 && defined(HAVE_TRUE_LONG_LONG)
    DEFINE(long long, LONG_LONG);
#endif
#if SIZEOF___INT64 != 0
    DEFINE(__int64, __INT64);
#endif
#if SIZEOF___INT128 != 0
    DEFINE(__int128, __INT128);
#endif
#if SIZEOF_OFF_T != 0
    DEFINE(off_t, OFF_T);
#endif
#if SIZEOF_VOIDP != 0
    DEFINE(void*, VOIDP);
#endif
#if SIZEOF_FLOAT != 0
    DEFINE(float, FLOAT);
#endif
#if SIZEOF_DOUBLE != 0
    DEFINE(double, DOUBLE);
#endif
#if SIZEOF_TIME_T != 0
    DEFINE(time_t, TIME_T);
#endif
#if SIZEOF_SIZE_T != 0
    DEFINE(size_t, SIZE_T);
#endif
#if SIZEOF_PTRDIFF_T != 0
    DEFINE(ptrdiff_t, PTRDIFF_T);
#endif

#undef DEFINE
}
