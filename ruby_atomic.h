#ifndef INTERNAL_ATOMIC_H
#define INTERNAL_ATOMIC_H

#include "ruby/atomic.h"

#if defined(HAVE_GCC_ATOMIC_BUILTINS)
    #define RUBY_ATOMIC_RELAXED __ATOMIC_RELAXED
    #define RUBY_ATOMIC_ACQUIRE __ATOMIC_ACQUIRE
    #define RUBY_ATOMIC_RELEASE __ATOMIC_RELEASE
    #define RUBY_ATOMIC_ACQ_REL __ATOMIC_ACQ_REL
    #define RUBY_ATOMIC_SEQ_CST __ATOMIC_SEQ_CST
#elif defined(HAVE_STDATOMIC_H)
    #include <stdatomic.h>
    #define RUBY_ATOMIC_RELAXED memory_order_relaxed
    #define RUBY_ATOMIC_ACQUIRE memory_order_acquire
    #define RUBY_ATOMIC_RELEASE memory_order_release
    #define RUBY_ATOMIC_ACQ_REL memory_order_acq_rel
    #define RUBY_ATOMIC_SEQ_CST memory_order_seq_cst
#else
    /* Dummy values for unsupported platforms */
    #define RUBY_ATOMIC_RELAXED 0
    #define RUBY_ATOMIC_ACQUIRE 1
    #define RUBY_ATOMIC_RELEASE 2
    #define RUBY_ATOMIC_ACQ_REL 3
    #define RUBY_ATOMIC_SEQ_CST 4
#endif

#define RUBY_ATOMIC_VALUE_LOAD(x) (VALUE)(RUBY_ATOMIC_PTR_LOAD(x))

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

/**********************************/

/* Platform-specific implementation (or fallback) */
#if defined(HAVE_GCC_ATOMIC_BUILTINS)
#define DEFINE_ATOMIC_LOAD_EXPLICIT_BODY(ptr, memory_order, type, name) \
    __atomic_load_n(ptr, memory_order)
#elif defined(HAVE_STDATOMIC_H)
#define DEFINE_ATOMIC_LOAD_EXPLICIT_BODY(ptr, memory_order, type, name) \
    atomic_load_explicit((_Atomic volatile type *)ptr, memory_order)
#else
#define DEFINE_ATOMIC_LOAD_EXPLICIT_BODY(ptr, memory_order, type, name) \
    ((void)memory_order, rbimpl_atomic_##name##load(ptr))
#endif

/* Single macro definition for load operations with explicit memory ordering */
#define DEFINE_ATOMIC_LOAD_EXPLICIT(name, type) \
static inline type \
rbimpl_atomic_##name##load_explicit(type *ptr, int memory_order) \
{ \
    return DEFINE_ATOMIC_LOAD_EXPLICIT_BODY(ptr, memory_order, type, name); \
}

/* Generate atomic load function with explicit memory ordering */
DEFINE_ATOMIC_LOAD_EXPLICIT(, rb_atomic_t)
DEFINE_ATOMIC_LOAD_EXPLICIT(value_, VALUE)
DEFINE_ATOMIC_LOAD_EXPLICIT(ptr_, void *)

#undef DEFINE_ATOMIC_LOAD_EXPLICIT
#undef DEFINE_ATOMIC_LOAD_EXPLICIT_BODY

/**********************************/

#define ATOMIC_LOAD_RELAXED(var) rbimpl_atomic_load_explicit(&(var), RUBY_ATOMIC_RELAXED)

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
    *address = value;
#endif
}
#define ATOMIC_U64_SET_RELAXED(var, val) rbimpl_atomic_u64_set_relaxed(&(var), val)

#endif
