#ifndef RUBY_ATOMIC_H
#define RUBY_ATOMIC_H

#ifdef _WIN32
#pragma intrinsic(_InterlockedOr)
typedef LONG rb_atomic_t;

# define ATOMIC_SET(var, val) InterlockedExchange(&(var), (val))
# define ATOMIC_INC(var) InterlockedIncrement(&(var))
# define ATOMIC_DEC(var) InterlockedDecrement(&(var))
# define ATOMIC_OR(var, val) _InterlockedOr(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) InterlockedExchange(&(var), (val))

#elif defined HAVE_GCC_ATOMIC_BUILTINS
/* @shyouhei hack to support atomic operations in case of gcc. Gcc
 * has its own pseudo-insns to support them.  See info, or
 * http://gcc.gnu.org/onlinedocs/gcc/Atomic-Builtins.html */

typedef unsigned int rb_atomic_t; /* Anything OK */
# define ATOMIC_SET(var, val)  __sync_lock_test_and_set(&(var), (val))
# define ATOMIC_INC(var) __sync_fetch_and_add(&(var), 1)
# define ATOMIC_DEC(var) __sync_fetch_and_sub(&(var), 1)
# define ATOMIC_OR(var, val) __sync_or_and_fetch(&(var), (val))
# define ATOMIC_EXCHANGE(var, val) __sync_lock_test_and_set(&(var), (val))

#else
typedef int rb_atomic_t;
extern rb_atomic_t ruby_atomic_exchange(rb_atomic_t *ptr, rb_atomic_t val);

# define ATOMIC_SET(var, val) ((var) = (val))
# define ATOMIC_INC(var) (++(var))
# define ATOMIC_DEC(var) (--(var))
# define ATOMIC_OR(var, val) ((var) |= (val))
# define ATOMIC_EXCHANGE(var, val) ruby_atomic_exchange(&(var), (val))
#endif

#endif /* RUBY_ATOMIC_H */
