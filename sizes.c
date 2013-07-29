#include "ruby/ruby.h"

void
Init_sizes(void)
{
    VALUE s = rb_hash_new();
    rb_define_const(rb_define_module("RbConfig"), "SIZEOF", s);

#define DEFINE(type, size) rb_hash_aset(s, rb_str_new_cstr(#type), INT2FIX(SIZEOF_##size));

#ifdef SIZEOF_INT
    DEFINE(int, INT);
#endif
#ifdef SIZEOF_SHORT
    DEFINE(short, SHORT);
#endif
#ifdef SIZEOF_LONG
    DEFINE(long, LONG);
#endif
#ifdef SIZEOF_LONG_LONG
    DEFINE(long long, LONG_LONG);
#endif
#ifdef SIZEOF___INT64
    DEFINE(__int64, __INT64);
#endif
#ifdef SIZEOF___INT128
    DEFINE(__int128, __INT128);
#endif
#ifdef SIZEOF_OFF_T
    DEFINE(off_t, OFF_T);
#endif
#ifdef SIZEOF_VOIDP
    DEFINE(void*, VOIDP);
#endif
#ifdef SIZEOF_FLOAT
    DEFINE(float, FLOAT);
#endif
#ifdef SIZEOF_DOUBLE
    DEFINE(double, DOUBLE);
#endif
#ifdef SIZEOF_TIME_T
    DEFINE(time_t, TIME_T);
#endif
#ifdef SIZEOF_SIZE_T
    DEFINE(size_t, SIZE_T);
#endif
#ifdef SIZEOF_PTRDIFF_T
    DEFINE(ptrdiff_t, PTRDIFF_T);
#endif

#undef DEFINE
}
