#ifndef INTERNAL_ATOMIC_H
#define INTERNAL_ATOMIC_H

#include "ruby/atomic.h"
#ifdef HAVE_STDATOMIC_H
# include <stdatomic.h>
#endif

#define RUBY_ATOMIC_VALUE_LOAD(x) rbimpl_atomic_value_load(&(x), RBIMPL_ATOMIC_SEQ_CST)

/* shim macros only */
#define ATOMIC_ADD(var, val) RUBY_ATOMIC_ADD(var, val)
#define ATOMIC_CAS(var, oldval, newval) RUBY_ATOMIC_CAS(var, oldval, newval)
#define ATOMIC_DEC(var) RUBY_ATOMIC_DEC(var)
#define ATOMIC_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
#define ATOMIC_FETCH_ADD(var, val) RUBY_ATOMIC_FETCH_ADD(var, val)
#define ATOMIC_FETCH_SUB(var, val) RUBY_ATOMIC_FETCH_SUB(var, val)
#define ATOMIC_INC(var) RUBY_ATOMIC_INC(var)
#define ATOMIC_OR(var, val) RUBY_ATOMIC_OR(var, val)
#define ATOMIC_PTR_CAS(var, oldval, newval) RUBY_ATOMIC_PTR_CAS(var, oldval, newval)
#define ATOMIC_PTR_EXCHANGE(var, val) RUBY_ATOMIC_PTR_EXCHANGE(var, val)
#define ATOMIC_SET(var, val) RUBY_ATOMIC_SET(var, val)
#define ATOMIC_SIZE_ADD(var, val) RUBY_ATOMIC_SIZE_ADD(var, val)
#define ATOMIC_SIZE_CAS(var, oldval, newval) RUBY_ATOMIC_SIZE_CAS(var, oldval, newval)
#define ATOMIC_SIZE_DEC(var) RUBY_ATOMIC_SIZE_DEC(var)
#define ATOMIC_SIZE_EXCHANGE(var, val) RUBY_ATOMIC_SIZE_EXCHANGE(var, val)
#define ATOMIC_SIZE_INC(var) RUBY_ATOMIC_SIZE_INC(var)
#define ATOMIC_SIZE_SUB(var, val) RUBY_ATOMIC_SIZE_SUB(var, val)
#define ATOMIC_SUB(var, val) RUBY_ATOMIC_SUB(var, val)
#define ATOMIC_VALUE_CAS(var, oldval, val) RUBY_ATOMIC_VALUE_CAS(var, oldval, val)
#define ATOMIC_VALUE_EXCHANGE(var, val) RUBY_ATOMIC_VALUE_EXCHANGE(var, val)

#define ATOMIC_LOAD_RELAXED(var) rbimpl_atomic_load(&(var), RBIMPL_ATOMIC_RELAXED)

typedef RBIMPL_ALIGNAS(8) uint64_t rbimpl_atomic_uint64_t;

static inline uint64_t
rbimpl_atomic_u64_load_relaxed(const volatile rbimpl_atomic_uint64_t *value)
{
#if defined(HAVE_GCC_ATOMIC_BUILTINS_64)
    return __atomic_load_n(value, __ATOMIC_RELAXED);
#elif defined(_WIN32)
    uint64_t val = *value;
    return InterlockedCompareExchange64(RBIMPL_CAST((uint64_t *)value), val, val);
#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    uint64_t val = *value;
    return atomic_cas_64(value, val, val);
#else
    // TODO: stdatomic

    return *value;
#endif
}
#define ATOMIC_U64_LOAD_RELAXED(var) rbimpl_atomic_u64_load_relaxed(&(var))

static inline void
rbimpl_atomic_u64_set_relaxed(volatile rbimpl_atomic_uint64_t *address, uint64_t value)
{
#if defined(HAVE_GCC_ATOMIC_BUILTINS_64)
    __atomic_store_n(address, value, __ATOMIC_RELAXED);
#elif defined(_WIN32)
    InterlockedExchange64(address, value);
#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    atomic_swap_64(address, value);
#else
    // TODO: stdatomic

    *address = value;
#endif
}
#define ATOMIC_U64_SET_RELAXED(var, val) rbimpl_atomic_u64_set_relaxed(&(var), val)

static inline uint64_t
rbimpl_atomic_u64_fetch_add_relaxed(volatile rbimpl_atomic_uint64_t *value, uint64_t addend)
{
#if defined(HAVE_GCC_ATOMIC_BUILTINS_64)
    return __atomic_fetch_add(value, addend, __ATOMIC_RELAXED);
#elif defined(_WIN32)
    return (uint64_t)InterlockedExchangeAdd64((LONG64 *)value, (LONG64)addend);
#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    return atomic_add_64_nv(value, addend) - addend;
#else
    // TODO: stdatomic
    uint64_t prev = *value;
    *value = prev + addend;
    return prev;
#endif
}
#define ATOMIC_U64_FETCH_ADD_RELAXED(var, val) rbimpl_atomic_u64_fetch_add_relaxed(&(var), val)

static inline uint64_t
rbimpl_atomic_u64_load_acquire(const volatile rbimpl_atomic_uint64_t *value)
{
#if defined(HAVE_GCC_ATOMIC_BUILTINS_64)
    return __atomic_load_n(value, __ATOMIC_ACQUIRE);
#else
    return rbimpl_atomic_u64_load_relaxed(value);
#endif
}
#define ATOMIC_U64_LOAD_ACQUIRE(var) rbimpl_atomic_u64_load_acquire(&(var))

static inline void
rbimpl_atomic_u64_set_release(volatile rbimpl_atomic_uint64_t *address, uint64_t value)
{
#if defined(HAVE_GCC_ATOMIC_BUILTINS_64)
    __atomic_store_n(address, value, __ATOMIC_RELEASE);
#else
    rbimpl_atomic_u64_set_relaxed(address, value);
#endif
}
#define ATOMIC_U64_SET_RELEASE(var, val) rbimpl_atomic_u64_set_release(&(var), val)

#endif
