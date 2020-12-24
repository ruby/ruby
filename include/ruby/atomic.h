#ifndef RUBY_ATOMIC_H
#define RUBY_ATOMIC_H

/*
 * - RUBY_ATOMIC_CAS, RUBY_ATOMIC_EXCHANGE, RUBY_ATOMIC_FETCH_*:
 *   return the old * value.
 * - RUBY_ATOMIC_ADD, RUBY_ATOMIC_SUB, RUBY_ATOMIC_INC, RUBY_ATOMIC_DEC, RUBY_ATOMIC_OR, RUBY_ATOMIC_SET:
 *   may be void.
 */
#if 0
#elif defined HAVE_GCC_ATOMIC_BUILTINS
typedef unsigned int rb_atomic_t;
# define RUBY_ATOMIC_FETCH_ADD(var, val) __atomic_fetch_add(&(var), (val), __ATOMIC_SEQ_CST)
# define RUBY_ATOMIC_FETCH_SUB(var, val) __atomic_fetch_sub(&(var), (val), __ATOMIC_SEQ_CST)
# define RUBY_ATOMIC_OR(var, val) __atomic_fetch_or(&(var), (val), __ATOMIC_SEQ_CST)
# define RUBY_ATOMIC_EXCHANGE(var, val) __atomic_exchange_n(&(var), (val), __ATOMIC_SEQ_CST)
# define RUBY_ATOMIC_CAS(var, oldval, newval) RB_GNUC_EXTENSION_BLOCK( \
   __typeof__(var) oldvaldup = (oldval); /* oldval should not be modified */ \
   __atomic_compare_exchange_n(&(var), &oldvaldup, (newval), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); \
   oldvaldup )

# define RUBY_ATOMIC_GENERIC_MACRO 1

#elif defined HAVE_GCC_SYNC_BUILTINS
/* @shyouhei hack to support atomic operations in case of gcc. Gcc
 * has its own pseudo-insns to support them.  See info, or
 * http://gcc.gnu.org/onlinedocs/gcc/Atomic-Builtins.html */

typedef unsigned int rb_atomic_t; /* Anything OK */
# define RUBY_ATOMIC_FETCH_ADD(var, val) __sync_fetch_and_add(&(var), (val))
# define RUBY_ATOMIC_FETCH_SUB(var, val) __sync_fetch_and_sub(&(var), (val))
# define RUBY_ATOMIC_OR(var, val) __sync_fetch_and_or(&(var), (val))
# define RUBY_ATOMIC_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))
# define RUBY_ATOMIC_CAS(var, oldval, newval) __sync_val_compare_and_swap(&(var), (oldval), (newval))

# define RUBY_ATOMIC_GENERIC_MACRO 1

#elif defined _WIN32
#if RBIMPL_COMPILER_SINCE(MSVC, 13, 0, 0)
#pragma intrinsic(_InterlockedOr)
#endif
typedef LONG rb_atomic_t;

# define RUBY_ATOMIC_SET(var, val) InterlockedExchange(&(var), (val))
# define RUBY_ATOMIC_INC(var) InterlockedIncrement(&(var))
# define RUBY_ATOMIC_DEC(var) InterlockedDecrement(&(var))
# define RUBY_ATOMIC_FETCH_ADD(var, val) InterlockedExchangeAdd(&(var), (val))
# define RUBY_ATOMIC_FETCH_SUB(var, val) InterlockedExchangeAdd(&(var), -(LONG)(val))
#if defined __GNUC__
# define RUBY_ATOMIC_OR(var, val) __asm__("lock\n\t" "orl\t%1, %0" : "=m"(var) : "Ir"(val))
#elif RBIMPL_COMPILER_BEFORE(MSVC, 13, 0, 0)
# define RUBY_ATOMIC_OR(var, val) rb_w32_atomic_or(&(var), (val))
static inline void
rb_w32_atomic_or(volatile rb_atomic_t *var, rb_atomic_t val)
{
#ifdef _M_IX86
    __asm mov eax, var;
    __asm mov ecx, val;
    __asm lock or [eax], ecx;
#else
#error unsupported architecture
#endif
}
#else
# define RUBY_ATOMIC_OR(var, val) _InterlockedOr(&(var), (val))
#endif
# define RUBY_ATOMIC_EXCHANGE(var, val) InterlockedExchange(&(var), (val))
# define RUBY_ATOMIC_CAS(var, oldval, newval) InterlockedCompareExchange(&(var), (newval), (oldval))
# if RBIMPL_COMPILER_BEFORE(MSVC, 13, 0, 0)
static inline rb_atomic_t
rb_w32_atomic_cas(volatile rb_atomic_t *var, rb_atomic_t oldval, rb_atomic_t newval)
{
    return (rb_atomic_t)InterlockedCompareExchange((PVOID *)var, (PVOID)newval, (PVOID)oldval);
}
#   undef RUBY_ATOMIC_CAS
#   define RUBY_ATOMIC_CAS(var, oldval, newval) rb_w32_atomic_cas(&(var), (oldval), (newval))
# endif
# ifdef _M_AMD64
#  define RUBY_ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd64((LONG_LONG *)&(var), (val))
#  define RUBY_ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd64((LONG_LONG *)&(var), -(LONG)(val))
#  define RUBY_ATOMIC_SIZE_INC(var) InterlockedIncrement64(&(var))
#  define RUBY_ATOMIC_SIZE_DEC(var) InterlockedDecrement64(&(var))
#  define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange64(&(var), (val))
#  define RUBY_ATOMIC_SIZE_CAS(var, oldval, newval) InterlockedCompareExchange64(&(var), (newval), (oldval))
# else
#  define RUBY_ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd((LONG *)&(var), (val))
#  define RUBY_ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd((LONG *)&(var), -(LONG)(val))
#  define RUBY_ATOMIC_SIZE_INC(var) InterlockedIncrement((LONG *)&(var))
#  define RUBY_ATOMIC_SIZE_DEC(var) InterlockedDecrement((LONG *)&(var))
#  define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange((LONG *)&(var), (val))
# endif

# ifdef InterlockedExchangePointer
#   define RUBY_ATOMIC_PTR_EXCHANGE(var, val) InterlockedExchangePointer((PVOID volatile *)&(var), (PVOID)(val))
# endif /* See below for definitions of other situations */

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
#include <atomic.h>
typedef unsigned int rb_atomic_t;

# define RUBY_ATOMIC_INC(var) atomic_inc_uint(&(var))
# define RUBY_ATOMIC_DEC(var) atomic_dec_uint(&(var))
# define RUBY_ATOMIC_FETCH_ADD(var, val) rb_atomic_fetch_add(&(var), (val))
# define RUBY_ATOMIC_FETCH_SUB(var, val) rb_atomic_fetch_sub(&(var), (val))
# define RUBY_ATOMIC_ADD(var, val) atomic_add_uint(&(var), (val))
# define RUBY_ATOMIC_SUB(var, val) atomic_sub_uint(&(var), (val))
# define RUBY_ATOMIC_OR(var, val) atomic_or_uint(&(var), (val))
# define RUBY_ATOMIC_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# define RUBY_ATOMIC_CAS(var, oldval, newval) atomic_cas_uint(&(var), (oldval), (newval))

static inline rb_atomic_t
rb_atomic_fetch_add(volatile rb_atomic_t *var, rb_atomic_t val)
{
    return atomic_add_int_nv(var, val) - val;
}

static inline rb_atomic_t
rb_atomic_fetch_sub(volatile rb_atomic_t *var, rb_atomic_t val)
{
    return atomic_add_int_nv(var, (rb_atomic_t)(-(int)val)) + val;
}

# if defined(_LP64) || defined(_I32LPx)
#  define RUBY_ATOMIC_SIZE_ADD(var, val) atomic_add_long(&(var), (val))
#  define RUBY_ATOMIC_SIZE_SUB(var, val) atomic_add_long(&(var), -(val))
#  define RUBY_ATOMIC_SIZE_INC(var) atomic_inc_ulong(&(var))
#  define RUBY_ATOMIC_SIZE_DEC(var) atomic_dec_ulong(&(var))
#  define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_ulong(&(var), (val))
#  define RUBY_ATOMIC_SIZE_CAS(var, oldval, val) atomic_cas_ulong(&(var), (oldval), (val))
# else
#  define RUBY_ATOMIC_SIZE_ADD(var, val) atomic_add_int(&(var), (val))
#  define RUBY_ATOMIC_SIZE_SUB(var, val) atomic_add_int(&(var), -(val))
#  define RUBY_ATOMIC_SIZE_INC(var) atomic_inc_uint(&(var))
#  define RUBY_ATOMIC_SIZE_DEC(var) atomic_dec_uint(&(var))
#  define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# endif

#else
# error No atomic operation found
#endif

#ifndef RUBY_ATOMIC_SET
# define RUBY_ATOMIC_SET(var, val) (void)RUBY_ATOMIC_EXCHANGE(var, val)
#endif

#ifndef RUBY_ATOMIC_ADD
# define RUBY_ATOMIC_ADD(var, val) (void)RUBY_ATOMIC_FETCH_ADD(var, val)
#endif

#ifndef RUBY_ATOMIC_SUB
# define RUBY_ATOMIC_SUB(var, val) (void)RUBY_ATOMIC_FETCH_SUB(var, val)
#endif

#ifndef RUBY_ATOMIC_INC
# define RUBY_ATOMIC_INC(var) RUBY_ATOMIC_ADD(var, 1)
#endif

#ifndef RUBY_ATOMIC_DEC
# define RUBY_ATOMIC_DEC(var) RUBY_ATOMIC_SUB(var, 1)
#endif

#ifndef RUBY_ATOMIC_SIZE_INC
# define RUBY_ATOMIC_SIZE_INC(var) RUBY_ATOMIC_INC(var)
#endif

#ifndef RUBY_ATOMIC_SIZE_DEC
# define RUBY_ATOMIC_SIZE_DEC(var) RUBY_ATOMIC_DEC(var)
#endif

#ifndef RUBY_ATOMIC_SIZE_EXCHANGE
# define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
#endif

#ifndef RUBY_ATOMIC_SIZE_CAS
# define RUBY_ATOMIC_SIZE_CAS(var, oldval, val) RUBY_ATOMIC_CAS(var, oldval, val)
#endif

#ifndef RUBY_ATOMIC_SIZE_ADD
# define RUBY_ATOMIC_SIZE_ADD(var, val) RUBY_ATOMIC_ADD(var, val)
#endif

#ifndef RUBY_ATOMIC_SIZE_SUB
# define RUBY_ATOMIC_SIZE_SUB(var, val) RUBY_ATOMIC_SUB(var, val)
#endif

#if RUBY_ATOMIC_GENERIC_MACRO
# ifndef RUBY_ATOMIC_PTR_EXCHANGE
#   define RUBY_ATOMIC_PTR_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
# endif

# ifndef RUBY_ATOMIC_PTR_CAS
#   define RUBY_ATOMIC_PTR_CAS(var, oldval, newval) RUBY_ATOMIC_CAS(var, oldval, newval)
# endif

# ifndef RUBY_ATOMIC_VALUE_EXCHANGE
#   define RUBY_ATOMIC_VALUE_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
# endif

# ifndef RUBY_ATOMIC_VALUE_CAS
#   define RUBY_ATOMIC_VALUE_CAS(var, oldval, val) RUBY_ATOMIC_CAS(var, oldval, val)
# endif
#endif

#ifndef RUBY_ATOMIC_PTR_EXCHANGE
# if SIZEOF_VOIDP == SIZEOF_SIZE_T
#   define RUBY_ATOMIC_PTR_EXCHANGE(var, val) (void *)RUBY_ATOMIC_SIZE_EXCHANGE(*(size_t *)&(var), (size_t)(val))
# else
#   error No atomic exchange for void*
# endif
#endif

#ifndef RUBY_ATOMIC_PTR_CAS
# if SIZEOF_VOIDP == SIZEOF_SIZE_T
#   define RUBY_ATOMIC_PTR_CAS(var, oldval, val) (void *)RUBY_ATOMIC_SIZE_CAS(*(size_t *)&(var), (size_t)(oldval), (size_t)(val))
# else
#   error No atomic compare-and-set for void*
# endif
#endif

#ifndef RUBY_ATOMIC_VALUE_EXCHANGE
# if SIZEOF_VALUE == SIZEOF_SIZE_T
#   define RUBY_ATOMIC_VALUE_EXCHANGE(var, val) RUBY_ATOMIC_SIZE_EXCHANGE(*(size_t *)&(var), (size_t)(val))
# else
#   error No atomic exchange for VALUE
# endif
#endif

#ifndef RUBY_ATOMIC_VALUE_CAS
# if SIZEOF_VALUE == SIZEOF_SIZE_T
#   define RUBY_ATOMIC_VALUE_CAS(var, oldval, val) RUBY_ATOMIC_SIZE_CAS(*(size_t *)&(var), (size_t)(oldval), (size_t)(val))
# else
#   error No atomic compare-and-set for VALUE
# endif
#endif

#endif /* RUBY_ATOMIC_H */
