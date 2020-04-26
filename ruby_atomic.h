#ifndef RUBY_ATOMIC_H
#define RUBY_ATOMIC_H

/*
 * - ATOMIC_CAS, ATOMIC_EXCHANGE, ATOMIC_FETCH_*:
 *   return the old * value.
 * - ATOMIC_ADD, ATOMIC_SUB, ATOMIC_INC, ATOMIC_DEC, ATOMIC_OR, ATOMIC_SET:
 *   may be void.
 */
#if 0
#elif defined HAVE_GCC_ATOMIC_BUILTINS
typedef unsigned int rb_atomic_t;
# define ATOMIC_FETCH_ADD(var, val) __atomic_fetch_add(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_FETCH_SUB(var, val) __atomic_fetch_sub(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_OR(var, val) __atomic_fetch_or(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_EXCHANGE(var, val) __atomic_exchange_n(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_CAS(var, oldval, newval) RB_GNUC_EXTENSION_BLOCK( \
   __typeof__(var) oldvaldup = (oldval); /* oldval should not be modified */ \
   __atomic_compare_exchange_n(&(var), &oldvaldup, (newval), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); \
   oldvaldup )

# define RUBY_ATOMIC_GENERIC_MACRO 1

#elif defined HAVE_GCC_SYNC_BUILTINS
/* @shyouhei hack to support atomic operations in case of gcc. Gcc
 * has its own pseudo-insns to support them.  See info, or
 * http://gcc.gnu.org/onlinedocs/gcc/Atomic-Builtins.html */

typedef unsigned int rb_atomic_t; /* Anything OK */
# define ATOMIC_FETCH_ADD(var, val) __sync_fetch_and_add(&(var), (val))
# define ATOMIC_FETCH_SUB(var, var) __sync_fetch_and_sub(&(var), (val))
# define ATOMIC_OR(var, val) __sync_fetch_and_or(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) __sync_val_compare_and_swap(&(var), (oldval), (newval))

# define RUBY_ATOMIC_GENERIC_MACRO 1

#elif defined _WIN32
#if MSC_VERSION_SINCE(1300)
#pragma intrinsic(_InterlockedOr)
#endif
typedef LONG rb_atomic_t;

# define ATOMIC_SET(var, val) InterlockedExchange(&(var), (val))
# define ATOMIC_INC(var) InterlockedIncrement(&(var))
# define ATOMIC_DEC(var) InterlockedDecrement(&(var))
# define ATOMIC_FETCH_ADD(var, val) InterlockedExchangeAdd(&(var), (val))
# define ATOMIC_FETCH_SUB(var, val) InterlockedExchangeAdd(&(var), -(LONG)(val))
#if defined __GNUC__
# define ATOMIC_OR(var, val) __asm__("lock\n\t" "orl\t%1, %0" : "=m"(var) : "Ir"(val))
#elif MSC_VERSION_BEFORE(1300)
# define ATOMIC_OR(var, val) rb_w32_atomic_or(&(var), (val))
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
# define ATOMIC_OR(var, val) _InterlockedOr(&(var), (val))
#endif
# define ATOMIC_EXCHANGE(var, val) InterlockedExchange(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) InterlockedCompareExchange(&(var), (newval), (oldval))
# if MSC_VERSION_BEFORE(1300)
static inline rb_atomic_t
rb_w32_atomic_cas(volatile rb_atomic_t *var, rb_atomic_t oldval, rb_atomic_t newval)
{
    return (rb_atomic_t)InterlockedCompareExchange((PVOID *)var, (PVOID)newval, (PVOID)oldval);
}
#   undef ATOMIC_CAS
#   define ATOMIC_CAS(var, oldval, newval) rb_w32_atomic_cas(&(var), (oldval), (newval))
# endif
# ifdef _M_AMD64
#  define ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd64((LONG_LONG *)&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd64((LONG_LONG *)&(var), -(LONG)(val))
#  define ATOMIC_SIZE_INC(var) InterlockedIncrement64(&(var))
#  define ATOMIC_SIZE_DEC(var) InterlockedDecrement64(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange64(&(var), (val))
#  define ATOMIC_SIZE_CAS(var, oldval, newval) InterlockedCompareExchange64(&(var), (newval), (oldval))
# else
#  define ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd((LONG *)&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd((LONG *)&(var), -(LONG)(val))
#  define ATOMIC_SIZE_INC(var) InterlockedIncrement((LONG *)&(var))
#  define ATOMIC_SIZE_DEC(var) InterlockedDecrement((LONG *)&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange((LONG *)&(var), (val))
# endif

# ifdef InterlockedExchangePointer
#   define ATOMIC_PTR_EXCHANGE(var, val) InterlockedExchangePointer((PVOID volatile *)&(var), (PVOID)(val))
# endif /* See below for definitions of other situations */

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
#include <atomic.h>
typedef unsigned int rb_atomic_t;

# define ATOMIC_INC(var) atomic_inc_uint(&(var))
# define ATOMIC_DEC(var) atomic_dec_uint(&(var))
# define ATOMIC_FETCH_ADD(var, val) rb_atomic_fetch_add(&(var), (val))
# define ATOMIC_FETCH_SUB(var, val) rb_atomic_fetch_sub(&(var), (val))
# define ATOMIC_ADD(var, val) atomic_add_uint(&(var), (val))
# define ATOMIC_SUB(var, val) atomic_sub_uint(&(var), (val))
# define ATOMIC_OR(var, val) atomic_or_uint(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) atomic_cas_uint(&(var), (oldval), (newval))

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
#  define ATOMIC_SIZE_ADD(var, val) atomic_add_long(&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) atomic_add_long(&(var), -(val))
#  define ATOMIC_SIZE_INC(var) atomic_inc_ulong(&(var))
#  define ATOMIC_SIZE_DEC(var) atomic_dec_ulong(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_ulong(&(var), (val))
#  define ATOMIC_SIZE_CAS(var, oldval, val) atomic_cas_ulong(&(var), (oldval), (val))
# else
#  define ATOMIC_SIZE_ADD(var, val) atomic_add_int(&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) atomic_add_int(&(var), -(val))
#  define ATOMIC_SIZE_INC(var) atomic_inc_uint(&(var))
#  define ATOMIC_SIZE_DEC(var) atomic_dec_uint(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# endif

#else
# error No atomic operation found
#endif

#ifndef ATOMIC_SET
# define ATOMIC_SET(var, val) (void)ATOMIC_EXCHANGE(var, val)
#endif

#ifndef ATOMIC_ADD
# define ATOMIC_ADD(var, val) (void)ATOMIC_FETCH_ADD(var, val)
#endif

#ifndef ATOMIC_SUB
# define ATOMIC_SUB(var, val) (void)ATOMIC_FETCH_SUB(var, val)
#endif

#ifndef ATOMIC_INC
# define ATOMIC_INC(var) ATOMIC_ADD(var, 1)
#endif

#ifndef ATOMIC_DEC
# define ATOMIC_DEC(var) ATOMIC_SUB(var, 1)
#endif

#ifndef ATOMIC_SIZE_INC
# define ATOMIC_SIZE_INC(var) ATOMIC_INC(var)
#endif

#ifndef ATOMIC_SIZE_DEC
# define ATOMIC_SIZE_DEC(var) ATOMIC_DEC(var)
#endif

#ifndef ATOMIC_SIZE_EXCHANGE
# define ATOMIC_SIZE_EXCHANGE(var, val) ATOMIC_EXCHANGE(var, val)
#endif

#ifndef ATOMIC_SIZE_CAS
# define ATOMIC_SIZE_CAS(var, oldval, val) ATOMIC_CAS(var, oldval, val)
#endif

#ifndef ATOMIC_SIZE_ADD
# define ATOMIC_SIZE_ADD(var, val) ATOMIC_ADD(var, val)
#endif

#ifndef ATOMIC_SIZE_SUB
# define ATOMIC_SIZE_SUB(var, val) ATOMIC_SUB(var, val)
#endif

#if RUBY_ATOMIC_GENERIC_MACRO
# ifndef ATOMIC_PTR_EXCHANGE
#   define ATOMIC_PTR_EXCHANGE(var, val) ATOMIC_EXCHANGE(var, val)
# endif

# ifndef ATOMIC_PTR_CAS
#   define ATOMIC_PTR_CAS(var, oldval, newval) ATOMIC_CAS(var, oldval, newval)
# endif

# ifndef ATOMIC_VALUE_EXCHANGE
#   define ATOMIC_VALUE_EXCHANGE(var, val) ATOMIC_EXCHANGE(var, val)
# endif

# ifndef ATOMIC_VALUE_CAS
#   define ATOMIC_VALUE_CAS(var, oldval, val) ATOMIC_CAS(var, oldval, val)
# endif
#endif

#ifndef ATOMIC_PTR_EXCHANGE
# if SIZEOF_VOIDP == SIZEOF_SIZE_T
#   define ATOMIC_PTR_EXCHANGE(var, val) (void *)ATOMIC_SIZE_EXCHANGE(*(size_t *)&(var), (size_t)(val))
# else
#   error No atomic exchange for void*
# endif
#endif

#ifndef ATOMIC_PTR_CAS
# if SIZEOF_VOIDP == SIZEOF_SIZE_T
#   define ATOMIC_PTR_CAS(var, oldval, val) (void *)ATOMIC_SIZE_CAS(*(size_t *)&(var), (size_t)(oldval), (size_t)(val))
# else
#   error No atomic compare-and-set for void*
# endif
#endif

#ifndef ATOMIC_VALUE_EXCHANGE
# if SIZEOF_VALUE == SIZEOF_SIZE_T
#   define ATOMIC_VALUE_EXCHANGE(var, val) ATOMIC_SIZE_EXCHANGE(*(size_t *)&(var), (size_t)(val))
# else
#   error No atomic exchange for VALUE
# endif
#endif

#ifndef ATOMIC_VALUE_CAS
# if SIZEOF_VALUE == SIZEOF_SIZE_T
#   define ATOMIC_VALUE_CAS(var, oldval, val) ATOMIC_SIZE_CAS(*(size_t *)&(var), (size_t)(oldval), (size_t)(val))
# else
#   error No atomic compare-and-set for VALUE
# endif
#endif

#endif /* RUBY_ATOMIC_H */
