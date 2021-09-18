#ifndef RUBY_ATOMIC_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ATOMIC_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Atomic operations
 *
 * Basically, if  we could assume  either C11 or  C++11, these macros  are just
 * redundant.  Sadly we cannot.  We have to do them ourselves.
 */

/*
 * - RUBY_ATOMIC_CAS, RUBY_ATOMIC_EXCHANGE, RUBY_ATOMIC_FETCH_*:
 *   return the old value.
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

#elif defined(__DOXYGEN__)
/**
 * Asserts that  your environment supports  more than one atomic  types.  These
 * days systems tend to have such property  (C11 was a standard of decades ago,
 * right?) but we still support older ones.
 */
# define RUBY_ATOMIC_GENERIC_MACRO 1

/**
 * Type  that  is eligible  for  atomic  operations.   Depending on  your  host
 * platform you might have  more than one such type, but we  choose one of them
 * anyways.
 */
using rb_atomic_t = std::atomic<std::uintptr_t>;

/**
 * Atomically replaces the  value pointed by `var` with the  result of addition
 * of `val` to  the old value of `var`.  In  case #RUBY_ATOMIC_GENERIC_MACRO is
 * set, this  operation could  be applied  to a  signed integer  type.  However
 * there is  no portabe way  to know what happens  on integer overflow  on such
 * situations.  You might better stick to unsigned types.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to add.
 * @return  What was stored in `var` before the addition.
 * @post    `var` holds `var + val`.
 */
# define RUBY_ATOMIC_FETCH_ADD(var, val) std::atomic_fetch_add(&(var), val)

/**
 * Atomically replaces the  value pointed by `var` with the  result of addition
 * of `val` to  the old value of `var`.  In  case #RUBY_ATOMIC_GENERIC_MACRO is
 * set, this  operation could  be applied  to a  signed integer  type.  However
 * there is  no portabe way  to know what happens  on integer overflow  on such
 * situations.  You might better stick to unsigned types.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to subtract.
 * @return  What was stored in `var` before the suntraction.
 * @post    `var` holds `var - val`.
 */
# define RUBY_ATOMIC_FETCH_SUB(var, val) std::atomic_fetch_sub(&(var),  val)

/**
 * Atomically  replaces  the  value  pointed   by  `var`  with  the  result  of
 * bitwise OR between `val` and the old value of `var`.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to mix.
 * @return  void
 * @post    `var` holds `var | val`.
 * @note    For portability, this macro can return void.
 */
# define RUBY_ATOMIC_OR(var, val) (void)std::atomic_fetch_or(&(var),  val)

/**
 * Atomically replaces the value pointed by  `var` with `val`.  This is just an
 * assignment, but you can additionally know the previous value.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
# define RUBY_ATOMIC_EXCHANGE(var, val) std::atomic_exchange(&(var), (val))

/**
 * Atomic compare-and-swap.   This stores  `val` to  `var` if  and only  if the
 * assignment changes  the value of `var`  from `oldval` to `newval`.   You can
 * detect whether the assignment happened or not using the return value.
 *
 * @param   var     A variable of ::rb_atomic_t.
 * @param   oldval  Expected value of `var` before the assignment.
 * @param   newval  What you want to store at `var`.
 * @retval  1       Successful assignment.
 * @retval  0       Something different from `oldval` resides at `var`.
 */
# define RUBY_ATOMIC_CAS(var, oldval, newval) \
    std::atomic_compare_exchange_strong(&(var), (newval), (oldval))

#else
# error No atomic operation found
#endif

/**
 * Identical to #RUBY_ATOMIC_EXCHANGE, except for the return type.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to set.
 * @return  void
 * @post    `var` holds `val`.
 */
#ifndef RUBY_ATOMIC_SET
# define RUBY_ATOMIC_SET(var, val) (void)RUBY_ATOMIC_EXCHANGE(var, val)
#endif

/**
 * Identical to #RUBY_ATOMIC_FETCH_ADD, except for the return type.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to add.
 * @return  void
 * @post    `var` holds `var + val`.
 */
#ifndef RUBY_ATOMIC_ADD
# define RUBY_ATOMIC_ADD(var, val) (void)RUBY_ATOMIC_FETCH_ADD(var, val)
#endif

/**
 * Identical to #RUBY_ATOMIC_FETCH_ADD, except for the return type.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to subtract.
 * @return  void
 * @post    `var` holds `var - val`.
 */
#ifndef RUBY_ATOMIC_SUB
# define RUBY_ATOMIC_SUB(var, val) (void)RUBY_ATOMIC_FETCH_SUB(var, val)
#endif

/**
 * Atomically increments the value pointed by `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @return  void
 * @post    `var` holds `var + 1`.
 */
#ifndef RUBY_ATOMIC_INC
# define RUBY_ATOMIC_INC(var) RUBY_ATOMIC_ADD(var, 1)
#endif

/**
 * Atomically decrements the value pointed by `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @return  void
 * @post    `var` holds `var - 1`.
 */
#ifndef RUBY_ATOMIC_DEC
# define RUBY_ATOMIC_DEC(var) RUBY_ATOMIC_SUB(var, 1)
#endif

/**
 * Identical  to  #RUBY_ATOMIC_INC,  except  it  expects  its  argument  is  an
 * (possibly  `_Atomic`  qualified)  unsigned  integer of  the  same  width  of
 * `size_t`.  There  are cases where  ::rb_atomic_t is 32bit while  `size_t` is
 * 64bit.  This  should be  used for  size related  operations to  support such
 * platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `size_t`.
 * @return  void
 * @post    `var` holds `var + 1`.
 */
#ifndef RUBY_ATOMIC_SIZE_INC
# define RUBY_ATOMIC_SIZE_INC(var) RUBY_ATOMIC_INC(var)
#endif

/**
 * Identical  to  #RUBY_ATOMIC_DEC,  except  it  expects  its  argument  is  an
 * (possibly  `_Atomic`  qualified)  unsigned  integer of  the  same  width  of
 * `size_t`.  There  are cases where  ::rb_atomic_t is 32bit while  `size_t` is
 * 64bit.  This  should be  used for  size related  operations to  support such
 * platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `size_t`.
 * @return  void
 * @post    `var` holds `var - 1`.
 */
#ifndef RUBY_ATOMIC_SIZE_DEC
# define RUBY_ATOMIC_SIZE_DEC(var) RUBY_ATOMIC_DEC(var)
#endif

/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * (possibly  `_Atomic`  qualified) unsigned  integers  of  the same  width  of
 * `size_t`.  There  are cases where  ::rb_atomic_t is 32bit while  `size_t` is
 * 64bit.  This  should be  used for  size related  operations to  support such
 * platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `size_t`.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
#ifndef RUBY_ATOMIC_SIZE_EXCHANGE
# define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
#endif

/**
 * Identical to #RUBY_ATOMIC_CAS, except it expects its arguments are (possibly
 * `_Atomic` qualified) unsigned integers of the same width of `size_t`.  There
 * are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This should
 * be used for size related operations to support such platforms.
 *
 * @param   var     A variable of (possibly _Atomic qualified) `size_t`.
 * @param   oldval  Expected value of `var` before the assignment.
 * @param   val     What you want to store at `var`.
 * @retval  1       Successful assignment.
 * @retval  0       Something different from `oldval` resides at `var`.
 */
#ifndef RUBY_ATOMIC_SIZE_CAS
# define RUBY_ATOMIC_SIZE_CAS(var, oldval, val) RUBY_ATOMIC_CAS(var, oldval, val)
#endif

/**
 * Identical to #RUBY_ATOMIC_ADD, except it expects its arguments are (possibly
 * `_Atomic` qualified) unsigned integers of the same width of `size_t`.  There
 * are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This should
 * be used for size related operations to support such platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `size_t`.
 * @param   val  Value to add.
 * @return  void
 * @post    `var` holds `var + val`.
 */
#ifndef RUBY_ATOMIC_SIZE_ADD
# define RUBY_ATOMIC_SIZE_ADD(var, val) RUBY_ATOMIC_ADD(var, val)
#endif

/**
 * Identical to #RUBY_ATOMIC_SUB, except it expects its arguments are (possibly
 * `_Atomic` qualified) unsigned integers of the same width of `size_t`.  There
 * are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This should
 * be used for size related operations to support such platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `size_t`.
 * @param   val  Value to subtract.
 * @return  void
 * @post    `var` holds `var - val`.
 */
#ifndef RUBY_ATOMIC_SIZE_SUB
# define RUBY_ATOMIC_SIZE_SUB(var, val) RUBY_ATOMIC_SUB(var, val)
#endif

#if RUBY_ATOMIC_GENERIC_MACRO
/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * (possibly  `_Atomic`  qualified) unsigned  integers  of  the same  width  of
 * `void*`.   There are  cases where  ::rb_atomic_t is  32bit while  `void*` is
 * 64bit.  This should  be used for pointer related operations  to support such
 * platforms.
 *
 * @param   var  A variable of (possibly _Atomic qualified) `void *`.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
# ifndef RUBY_ATOMIC_PTR_EXCHANGE
#   define RUBY_ATOMIC_PTR_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
# endif

/**
 * Identical to #RUBY_ATOMIC_CAS, except it expects its arguments are (possibly
 * `_Atomic` qualified) unsigned integers of  the same width of `void*`.  There
 * are cases where ::rb_atomic_t is 32bit  while `void*` is 64bit.  This should
 * be used for size related operations to support such platforms.
 *
 * @param   var     A variable of (possibly _Atomic qualified) `void*`.
 * @param   oldval  Expected value of `var` before the assignment.
 * @param   newval  What you want to store at `var`.
 * @retval  1       Successful assignment.
 * @retval  0       Something different from `oldval` resides at `var`.
 */
# ifndef RUBY_ATOMIC_PTR_CAS
#   define RUBY_ATOMIC_PTR_CAS(var, oldval, newval) RUBY_ATOMIC_CAS(var, oldval, newval)
# endif

/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * ::VALUE.   There are  cases where  ::rb_atomic_t is  32bit while  ::VALUE is
 * 64bit.  This should  be used for pointer related operations  to support such
 * platforms.
 *
 * @param   var  A variable of ::VALUE.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
# ifndef RUBY_ATOMIC_VALUE_EXCHANGE
#   define RUBY_ATOMIC_VALUE_EXCHANGE(var, val) RUBY_ATOMIC_EXCHANGE(var, val)
# endif

/**
 * Identical to #RUBY_ATOMIC_CAS, except it expects its arguments are (possibly
 * `_Atomic` qualified) unsigned integers of  the same width of `void*`.  There
 * are cases where ::rb_atomic_t is 32bit  while `void*` is 64bit.  This should
 * be used for size related operations to support such platforms.
 *
 * @param   var     A variable of (possibly _Atomic qualified) `void*`.
 * @param   oldval  Expected value of `var` before the assignment.
 * @param   val     What you want to store at `var`.
 * @retval  1       Successful assignment.
 * @retval  0       Something different from `oldval` resides at `var`.
 */
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
