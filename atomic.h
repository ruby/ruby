#ifndef RUBY_ATOMIC_H
#define RUBY_ATOMIC_H

#if 0
#elif defined HAVE_GCC_ATOMIC_BUILTINS
/* @shyouhei hack to support atomic operations in case of gcc. Gcc
 * has its own pseudo-insns to support them.  See info, or
 * http://gcc.gnu.org/onlinedocs/gcc/Atomic-Builtins.html */

typedef unsigned int rb_atomic_t; /* Anything OK */
# define ATOMIC_SET(var, val)  (void)__sync_lock_test_and_set(&(var), (val))
# define ATOMIC_INC(var) __sync_fetch_and_add(&(var), 1)
# define ATOMIC_DEC(var) __sync_fetch_and_sub(&(var), 1)
# define ATOMIC_OR(var, val) __sync_or_and_fetch(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))

# define ATOMIC_SIZE_ADD(var, val) __sync_fetch_and_add(&(var), (val))
# define ATOMIC_SIZE_SUB(var, val) __sync_fetch_and_sub(&(var), (val))
# define ATOMIC_SIZE_INC(var) __sync_fetch_and_add(&(var), 1)
# define ATOMIC_SIZE_DEC(var) __sync_fetch_and_sub(&(var), 1)
# define ATOMIC_SIZE_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))

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

# ifdef _M_AMD64
#  define ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd64(&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd64(&(var), -(val))
#  define ATOMIC_SIZE_INC(var) InterlockedIncrement64(&(var))
#  define ATOMIC_SIZE_DEC(var) InterlockedDecrement64(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange64(&(var), (val))
# else
#  define ATOMIC_SIZE_ADD(var, val) InterlockedExchangeAdd((LONG *)&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) InterlockedExchangeAdd((LONG *)&(var), -(val))
#  define ATOMIC_SIZE_INC(var) InterlockedIncrement((LONG *)&(var))
#  define ATOMIC_SIZE_DEC(var) InterlockedDecrement((LONG *)&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) InterlockedExchange((LONG *)&(var), (val))
# endif

#elif defined(__sun)
#include <atomic.h>
typedef unsigned int rb_atomic_t;

# define ATOMIC_SET(var, val) (void)atomic_swap_uint(&(var), (val))
# define ATOMIC_INC(var) atomic_inc_uint(&(var))
# define ATOMIC_DEC(var) atomic_dec_uint(&(var))
# define ATOMIC_OR(var, val) atomic_or_uint(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))

# if SIZEOF_SIZE_T == SIZEOF_LONG
#  define ATOMIC_SIZE_ADD(var, val) atomic_add_long(&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) atomic_add_long(&(var), -(val))
#  define ATOMIC_SIZE_INC(var) atomic_inc_ulong(&(var))
#  define ATOMIC_SIZE_DEC(var) atomic_dec_ulong(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_ulong(&(var), (val))
# else
#  define ATOMIC_SIZE_ADD(var, val) atomic_add_int(&(var), (val))
#  define ATOMIC_SIZE_SUB(var, val) atomic_add_int(&(var), -(val))
#  define ATOMIC_SIZE_INC(var) atomic_inc_uint(&(var))
#  define ATOMIC_SIZE_DEC(var) atomic_dec_uint(&(var))
#  define ATOMIC_SIZE_EXCHANGE(var, val) atomic_swap_uint(&(var), (val))
# endif

#else
typedef int rb_atomic_t;
#define NEED_RUBY_ATOMIC_EXCHANGE
extern rb_atomic_t ruby_atomic_exchange(rb_atomic_t *ptr, rb_atomic_t val);

# define ATOMIC_SET(var, val) (void)((var) = (val))
# define ATOMIC_INC(var) ((var)++)
# define ATOMIC_DEC(var) ((var)--)
# define ATOMIC_OR(var, val) ((var) |= (val))
# define ATOMIC_EXCHANGE(var, val) ruby_atomic_exchange(&(var), (val))

# define ATOMIC_SIZE_ADD(var, val) (void)((var) += (val))
# define ATOMIC_SIZE_SUB(var, val) (void)((var) -= (val))
# define ATOMIC_SIZE_INC(var) ((var)++)
# define ATOMIC_SIZE_DEC(var) ((var)--)
# define ATOMIC_SIZE_EXCHANGE(var, val) atomic_size_exchange(&(var), (val))
static inline size_t
atomic_size_exchange(size_t *ptr, size_t val)
{
    size_t old = *ptr;
    *ptr = val;
    return old;
}
#endif

#endif /* RUBY_ATOMIC_H */
