#ifndef _JSON_H_
#define _JSON_H_

#include "ruby.h"
#include "ruby/encoding.h"
#include <stdint.h>

#ifndef RBIMPL_ASSERT_OR_ASSUME
# define RBIMPL_ASSERT_OR_ASSUME(x)
#endif

#if defined(RUBY_DEBUG) && RUBY_DEBUG
# define JSON_ASSERT RUBY_ASSERT
# ifndef JSON_DEBUG
#  define JSON_DEBUG 1
# endif
#else
# ifdef JSON_DEBUG
#  include <assert.h>
#  define JSON_ASSERT(x) assert(x)
# else
#  define JSON_ASSERT(x)
# endif
#endif

#ifdef JSON_DEBUG
# define JSON_UNREACHABLE_RETURN(val) rb_bug("Unreachable")
#else
# define JSON_UNREACHABLE_RETURN UNREACHABLE_RETURN
#endif

/* shims */

#ifndef UNDEF_P
#define UNDEF_P(val) (val == Qundef)
#endif

#if SIZEOF_UINT64_T == SIZEOF_LONG_LONG
# define INT64T2NUM(x) LL2NUM(x)
# define UINT64T2NUM(x) ULL2NUM(x)
#elif SIZEOF_UINT64_T == SIZEOF_LONG
# define INT64T2NUM(x) LONG2NUM(x)
# define UINT64T2NUM(x) ULONG2NUM(x)
#else
# error No uint64_t conversion
#endif

/* This is the fallback definition from Ruby 3.4 */
#ifndef RBIMPL_STDBOOL_H
#if defined(__cplusplus)
# if defined(HAVE_STDBOOL_H) && (__cplusplus >= 201103L)
#  include <cstdbool>
# endif
#elif defined(HAVE_STDBOOL_H)
# include <stdbool.h>
#elif !defined(HAVE__BOOL)
typedef unsigned char _Bool;
# define bool  _Bool
# define true  ((_Bool)+1)
# define false ((_Bool)+0)
# define __bool_true_false_are_defined
#endif
#endif

#ifndef HAVE_RUBY_XFREE_SIZED
static inline void ruby_xfree_sized(void *ptr, size_t oldsize)
{
    ruby_xfree(ptr);
}

static inline void *ruby_xrealloc2_sized(void *ptr, size_t new_elems, size_t elem_size, size_t old_elems)
{
    return ruby_xrealloc2(ptr, new_elems, elem_size);
}
#endif

# define JSON_SIZED_REALLOC_N(v, T, m, n) \
    ((v) = (T *)ruby_xrealloc2_sized((void *)(v), (m), sizeof(T), (n)))

# define JSON_SIZED_FREE(v) ruby_xfree_sized((void *)(v), sizeof(*(v)))
# define JSON_SIZED_FREE_N(v, n) ruby_xfree_sized((void *)(v), sizeof(*(v)) * (n))

#ifndef HAVE_RB_EXT_RACTOR_SAFE
#   undef RUBY_TYPED_FROZEN_SHAREABLE
#   define RUBY_TYPED_FROZEN_SHAREABLE 0
#endif

#ifdef RUBY_TYPED_EMBEDDABLE
#  define HAVE_RUBY_TYPED_EMBEDDABLE 1
#else
# ifdef HAVE_CONST_RUBY_TYPED_EMBEDDABLE
#  define RUBY_TYPED_EMBEDDABLE RUBY_TYPED_EMBEDDABLE
#  define HAVE_RUBY_TYPED_EMBEDDABLE 1
# else
#  define RUBY_TYPED_EMBEDDABLE 0
# endif
#endif

#ifndef NORETURN
#if defined(__has_attribute) && __has_attribute(noreturn)
#define NORETURN(x) __attribute__((noreturn)) x
#else
#define NORETURN(x) x
#endif
#endif

#ifndef NOINLINE
#if defined(__has_attribute) && __has_attribute(noinline)
#define NOINLINE(x) __attribute__((noinline)) x
#else
#define NOINLINE(x) x
#endif
#endif

#ifndef ALWAYS_INLINE
#if defined(__has_attribute) && __has_attribute(always_inline)
#define ALWAYS_INLINE(x) inline __attribute__((always_inline)) x
#else
#define ALWAYS_INLINE(x) inline x
#endif
#endif

#ifndef RB_UNLIKELY
#define RB_UNLIKELY(expr) expr
#endif

#ifndef RB_LIKELY
#define RB_LIKELY(expr) expr
#endif

#ifndef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x
#endif

#ifdef RUBY_DEBUG
#ifndef JSON_DEBUG
#define JSON_DEBUG RUBY_DEBUG
#endif
#endif

#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ && INTPTR_MAX == INT64_MAX
#define JSON_CPU_LITTLE_ENDIAN_64BITS 1
#else
#define JSON_CPU_LITTLE_ENDIAN_64BITS 0
#endif

#ifdef JSON_TRUFFLERUBY_RB_CATCH_BUG

#undef RB_BLOCK_CALL_FUNC_ARGLIST
#define RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, func_args) VALUE func_args

NORETURN(static inline) void json_rb_throw_obj(VALUE tag, VALUE obj)
{
    VALUE exc = rb_exc_new_str(rb_eException, rb_utf8_str_new_cstr("throw_workaround"));
    rb_ivar_set(exc, rb_intern("@throw_tag"), tag);
    rb_ivar_set(exc, rb_intern("@throw_obj"), obj);
    rb_exc_raise(exc);
}
#define rb_throw_obj json_rb_throw_obj

static inline VALUE json_rb_catch_obj(VALUE tag, VALUE (*func)(VALUE args), VALUE func_args)
{
    int status;
    VALUE result = rb_protect(func, func_args, &status);
    if (status) {
        VALUE exc = rb_errinfo();
        if (tag == rb_ivar_get(exc, rb_intern("@throw_tag"))) {
            rb_set_errinfo(Qnil);
            return rb_ivar_get(exc, rb_intern("@throw_obj"));
        }
        rb_jump_tag(status);
    }
    return result;
}
#define rb_catch_obj json_rb_catch_obj

#endif // JSON_TRUFFLERUBY_RB_CATCH_BUG

#endif // _JSON_H_
