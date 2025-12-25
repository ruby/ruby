#ifndef _JSON_H_
#define _JSON_H_

#include "ruby.h"
#include "ruby/encoding.h"
#include <stdint.h>

#if defined(RUBY_DEBUG) && RUBY_DEBUG
# define JSON_ASSERT RUBY_ASSERT
#else
# ifdef JSON_DEBUG
#  include <assert.h>
#  define JSON_ASSERT(x) assert(x)
# else
#  define JSON_ASSERT(x)
# endif
#endif

/* shims */

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

#ifndef HAVE_RB_EXT_RACTOR_SAFE
#   undef RUBY_TYPED_FROZEN_SHAREABLE
#   define RUBY_TYPED_FROZEN_SHAREABLE 0
#endif

#ifndef NORETURN
#define NORETURN(x) x
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

#endif // _JSON_H_
