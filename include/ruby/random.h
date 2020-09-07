#ifndef RUBY_RANDOM_H
#define RUBY_RANDOM_H 1
/**
 * @file
 * @date       Sat May  7 11:51:14 JST 2016
 * @copyright  2007-2020 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#include "ruby/ruby.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

typedef struct {
    VALUE seed;
} rb_random_t;

typedef void rb_random_init_func(rb_random_t *, const uint32_t *, size_t);
typedef unsigned int rb_random_get_int32_func(rb_random_t *);
typedef void rb_random_get_bytes_func(rb_random_t *, void *, size_t);
typedef double rb_random_get_real_func(rb_random_t *, int);

typedef struct {
    size_t default_seed_bits;
    rb_random_init_func *init;
    rb_random_get_int32_func *get_int32;
    rb_random_get_bytes_func *get_bytes;
    rb_random_get_real_func *get_real;
} rb_random_interface_t;

#define rb_rand_if(obj) \
    ((const rb_random_interface_t *)RTYPEDDATA_TYPE(obj)->data)

#define RB_RANDOM_INTERFACE_DECLARE(prefix) \
    static void prefix##_init(rb_random_t *, const uint32_t *, size_t); \
    static unsigned int prefix##_get_int32(rb_random_t *); \
    static void prefix##_get_bytes(rb_random_t *, void *, size_t)

#define RB_RANDOM_INTERFACE_DECLARE_WITH_REAL(prefix) \
    RB_RANDOM_INTERFACE_DECLARE(prefix); \
    static double prefix##_get_real(rb_random_t *, int)

#define RB_RANDOM_INTERFACE_DEFINE(prefix) \
    prefix##_init, \
    prefix##_get_int32, \
    prefix##_get_bytes

#define RB_RANDOM_INTERFACE_DEFINE_WITH_REAL(prefix) \
    RB_RANDOM_INTERFACE_DEFINE(prefix), \
    prefix##_get_real

#if defined _WIN32 && !defined __CYGWIN__
typedef rb_data_type_t rb_random_data_type_t;
# define RB_RANDOM_PARENT 0
# define RB_RANDOM_DATA_INIT_PARENT(random_data) \
    (random_data.parent = &rb_random_data_type)
#else
typedef const rb_data_type_t rb_random_data_type_t;
# define RB_RANDOM_PARENT &rb_random_data_type
# define RB_RANDOM_DATA_INIT_PARENT(random_data) ((void)0)
#endif

void rb_random_mark(void *ptr);
void rb_random_base_init(rb_random_t *rnd);
double rb_int_pair_to_real(uint32_t a, uint32_t b, int excl);
void rb_rand_bytes_int32(rb_random_get_int32_func *, rb_random_t *, void *, size_t);
RUBY_EXTERN const rb_data_type_t rb_random_data_type;

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_RANDOM_H */
