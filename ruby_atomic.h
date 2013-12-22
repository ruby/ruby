#ifndef RUBY_ATOMIC_H
#define RUBY_ATOMIC_H

#if 0
#elif defined HAVE_GCC_ATOMIC_BUILTINS
typedef unsigned int rb_atomic_t;
# define ATOMIC_SET(var, val)  (void)__atomic_exchange_n(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_INC(var) __atomic_fetch_add(&(var), 1, __ATOMIC_SEQ_CST)
# define ATOMIC_DEC(var) __atomic_fetch_sub(&(var), 1, __ATOMIC_SEQ_CST)
# define ATOMIC_OR(var, val) __atomic_or_fetch(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_EXCHANGE(var, val) __atomic_exchange_n(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_CAS(var, oldval, newval) \
({ __typeof__(oldval) oldvaldup = (oldval); /* oldval should not be modified */ \
   __atomic_compare_exchange_n(&(var), &oldvaldup, (newval), 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); \
   oldvaldup; })

# define ATOMIC_SIZE_ADD(var, val) __atomic_fetch_add(&(var), (val), __ATOMIC_SEQ_CST)
# define ATOMIC_SIZE_SUB(var, val) __atomic_fetch_sub(&(var), (val), __ATOMIC_SEQ_CST)

# define ATOMIC_PTR_EXCHANGE(var, val) __atomic_exchange_n(&(var), (val), __ATOMIC_SEQ_CST)

#elif defined HAVE_GCC_SYNC_BUILTINS
/* @shyouhei hack to support atomic operations in case of gcc. Gcc
 * has its own pseudo-insns to support them.  See info, or
 * http://gcc.gnu.org/onlinedocs/gcc/Atomic-Builtins.html */

typedef unsigned int rb_atomic_t; /* Anything OK */
# define ATOMIC_SET(var, val)  (void)__sync_lock_test_and_set(&(var), (val))
# define ATOMIC_INC(var) __sync_fetch_and_add(&(var), 1)
# define ATOMIC_DEC(var) __sync_fetch_and_sub(&(var), 1)
# define ATOMIC_OR(var, val) __sync_or_and_fetch(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) __sync_val_compare_and_swap(&(var), (oldval), (newval))

# define ATOMIC_SIZE_ADD(var, val) __sync_fetch_and_add(&(var), (val))
# define ATOMIC_SIZE_SUB(var, val) __sync_fetch_and_sub(&(var), (val))

# define ATOMIC_PTR_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))

#elif defined _WIN32
#if defined _MSC_VER && _MSC_VER > 1200
#pragma intrinsic(_InterlockedOr)
#endif
typedef LONG rb_atomic_t;

# define ATOMIC_SET(var, val) InterlockedExchange(&(var), (val))
# define ATOMIC_INC(var) InterlockedIncrement(&(var))
# define ATOMIC_DEC(var) InterlockedDecrement(&(var))
#if defined __GNUC__
# define ATOMIC_OR(var, val) __asm__("lock\n\t" "orl\t%1, %0" : "=m"(var) : "Ir"(val))
#elif defined _MSC_VER && _MSC_VER <= 1200
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
# if defined _MSC_VER && _MSC_VER <= 1200
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
#  define ATOMIC_SIZE_CAS(var, oldval, val) InterlockedCompareExchange64(&(var), (oldval), (val))
# else
#  define ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd((LONG *)&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd((LONG *)&(var), -(LONG)(val))
#  define ATOMIC_SIZE_INC(var) InterlockedIncrement((LONG *)&(var))
#  define ATOMIC_SIZE_DEC(var) InterlockedDecrement((LONG *)&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange((LONG *)&(var), (val))
# endif

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
#include <atomic.h>
typedef unsigned int rb_atomic_t;

# define ATOMIC_SET(var, val) (void)atomic_swap_uint(&(var), (val))
# define ATOMIC_INC(var) atomic_inc_uint(&(var))
# define ATOMIC_DEC(var) atomic_dec_uint(&(var))
# define ATOMIC_OR(var, val) atomic_or_uint(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) atomic_cas_uint(&(var), (oldval), (newval))

# if SIZEOF_SIZE_T == SIZEOF_LONG
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
typedef int rb_atomic_t;
#define NEED_RUBY_ATOMIC_OPS
extern rb_atomic_t ruby_atomic_exchange(rb_atomic_t *ptr, rb_atomic_t val);
extern rb_atomic_t ruby_atomic_compare_and_swap(rb_atomic_t *ptr,
						rb_atomic_t cmp,
						rb_atomic_t newval);

# define ATOMIC_SET(var, val) (void)((var) = (val))
# define ATOMIC_INC(var) ((var)++)
# define ATOMIC_DEC(var) ((var)--)
# define ATOMIC_OR(var, val) ((var) |= (val))
# define ATOMIC_EXCHANGE(var, val) ruby_atomic_exchange(&(var), (val))
# define ATOMIC_CAS(var, oldval, newval) ruby_atomic_compare_and_swap(&(var), (oldval), (newval))

# define ATOMIC_SIZE_ADD(var, val) (void)((var) += (val))
# define ATOMIC_SIZE_SUB(var, val) (void)((var) -= (val))
# define ATOMIC_SIZE_EXCHANGE(var, val) atomic_size_exchange(&(var), (val))
static inline size_t
atomic_size_exchange(size_t *ptr, size_t val)
{
    size_t old = *ptr;
    *ptr = val;
    return old;
}
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

#ifndef ATOMIC_PTR_EXCHANGE
# if SIZEOF_VOIDP == SIZEOF_SIZE_T
#   define ATOMIC_PTR_EXCHANGE(var, val) (void *)ATOMIC_SIZE_EXCHANGE(*(size_t *)&(var), (size_t)(val))
# endif
#endif

#endif /* RUBY_ATOMIC_H */
