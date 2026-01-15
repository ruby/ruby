/************************************************

  digest.h - header file for ruby digest modules

  $Author$
  created at: Fri May 25 08:54:56 JST 2001


  Copyright (C) 2001-2006 Akinori MUSHA

  $RoughId: digest.h,v 1.3 2001/07/13 15:38:27 knu Exp $
  $Id$

************************************************/

#include "ruby.h"

#define RUBY_DIGEST_API_VERSION	3

typedef int (*rb_digest_hash_init_func_t)(void *);
typedef void (*rb_digest_hash_update_func_t)(void *, unsigned char *, size_t);
typedef int (*rb_digest_hash_finish_func_t)(void *, unsigned char *);

typedef struct {
    int api_version;
    size_t digest_len;
    size_t block_len;
    size_t ctx_size;
    rb_digest_hash_init_func_t init_func;
    rb_digest_hash_update_func_t update_func;
    rb_digest_hash_finish_func_t finish_func;
} rb_digest_metadata_t;

#define DEFINE_UPDATE_FUNC_FOR_UINT(name) \
void \
rb_digest_##name##_update(void *ctx, unsigned char *ptr, size_t size) \
{ \
    const unsigned int stride = 16384; \
 \
    for (; size > stride; size -= stride, ptr += stride) { \
        name##_Update(ctx, ptr, stride); \
    } \
    /* Since size <= stride, size should fit into an unsigned int */ \
    if (size > 0) name##_Update(ctx, ptr, (unsigned int)size); \
}

#define DEFINE_FINISH_FUNC_FROM_FINAL(name) \
int \
rb_digest_##name##_finish(void *ctx, unsigned char *ptr) \
{ \
    return name##_Final(ptr, ctx); \
}

static inline VALUE
rb_digest_namespace(void)
{
    rb_require("digest");
    return rb_path2class("Digest");
}

static inline ID
rb_id_metadata(void)
{
    return rb_intern_const("metadata");
}

#if !defined(HAVE_RB_EXT_RESOLVE_SYMBOL)
#elif !defined(RUBY_UNTYPED_DATA_WARNING)
# error RUBY_UNTYPED_DATA_WARNING is not defined
#elif RUBY_UNTYPED_DATA_WARNING
/* rb_ext_resolve_symbol() has been defined since Ruby 3.3, but digest
 * bundled with 3.3 didn't use it. */
# define DIGEST_USE_RB_EXT_RESOLVE_SYMBOL 1
#endif

static inline VALUE
rb_digest_make_metadata(const rb_digest_metadata_t *meta)
{
#if defined(EXTSTATIC) && EXTSTATIC
    /* The extension is built as a static library, so safe to refer to
     * rb_digest_wrap_metadata directly. */
    extern VALUE rb_digest_wrap_metadata(const rb_digest_metadata_t *meta);
    return rb_digest_wrap_metadata(meta);
#else
    /* The extension is built as a shared library, so we can't refer
     * to rb_digest_wrap_metadata directly. */
# ifdef DIGEST_USE_RB_EXT_RESOLVE_SYMBOL
    /* If rb_ext_resolve_symbol() is available, use it to get the address of
     * rb_digest_wrap_metadata. */
    typedef VALUE (*wrapper_func_type)(const rb_digest_metadata_t *meta);
    static wrapper_func_type wrapper;
    if (!wrapper) {
        wrapper = (wrapper_func_type)(uintptr_t)
            rb_ext_resolve_symbol("digest.so", "rb_digest_wrap_metadata");
        if (!wrapper) rb_raise(rb_eLoadError, "rb_digest_wrap_metadata not found");
    }
    return wrapper(meta);
# else
    /* If rb_ext_resolve_symbol() is not available, keep using untyped
     * data. */
# undef RUBY_UNTYPED_DATA_WARNING
# define RUBY_UNTYPED_DATA_WARNING 0
    return rb_obj_freeze(Data_Wrap_Struct(0, 0, 0, (void *)meta));
# endif
#endif
}
