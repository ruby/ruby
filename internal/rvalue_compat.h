#ifndef INTERNAL_RVALUE_COMPAT_H
#define INTERNAL_RVALUE_COMPAT_H

#include "ruby/config.h"

#define RBIMPL_DO_PRAGMA(x) _Pragma(#x)

#define RBIMPL_PRAGMA_PACK_PUSH(n) RB_IMPL_DO_PRAGMA(pack(push, n))
#define RBIMPL_PRAGMA_PACK_POP() RB_IMPL_DO_PRAGMA(pack(pop))

#if (SIZEOF_DOUBLE > SIZEOF_VALUE || SIZEOF_LONG_LONG > SIZEOF_VALUE) && \
    defined(_WIN32)
# define RVALUE_COMPATIBLE_TYPE(struct_or_union, name, decl) \
    RBIMPL_PRAGMA_PACK_PUSH(SIZEOF_VALUE); \
    struct_or_union name decl; \
    RBIMPL_PRAGMA_PACK_POP(); \
    RBIMPL_STATIC_ASSERT(sizeof_##name, sizeof(struct name) <= 5*SIZEOF_VALUE)
# define RVALUE_COMPATIBLE_STRUCT(name, decl) \
    RVALUE_COMPATIBLE_TYPE(struct, name, decl)
# define RVALUE_COMPATIBLE_UNION(name, decl) \
    RVALUE_COMPATIBLE_TYPE(union, name, decl)
#else
# define RVALUE_COMPATIBLE_STRUCT(name, decl) struct name decl
# define RVALUE_COMPATIBLE_UNION(name, decl) union name decl
#endif

#endif /* INTERNAL_RVALUE_COMPAT_H */
