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

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct rb_random_struct {
    VALUE seed;
};
typedef struct rb_random_struct rb_random_t;

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
#else
typedef const rb_data_type_t rb_random_data_type_t;
# define RB_RANDOM_PARENT &rb_random_data_type
#endif

#define RB_RANDOM_DATA_INIT_PARENT(random_data) \
    rbimpl_random_data_init_parent(&random_data)

void rb_random_mark(void *ptr);
void rb_random_base_init(rb_random_t *rnd);
double rb_int_pair_to_real(uint32_t a, uint32_t b, int excl);
void rb_rand_bytes_int32(rb_random_get_int32_func *, rb_random_t *, void *, size_t);
RUBY_EXTERN const rb_data_type_t rb_random_data_type;

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
static inline const rb_random_interface_t *
rb_rand_if(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(RTYPEDDATA_P(obj));
    const struct rb_data_type_struct *t = RTYPEDDATA_TYPE(obj);
    const void *ret = t->data;
    return RBIMPL_CAST((const rb_random_interface_t *)ret);
}

RBIMPL_ATTR_NOALIAS()
static inline void
rbimpl_random_data_init_parent(rb_random_data_type_t *random_data)
{
#if defined _WIN32 && !defined __CYGWIN__
    random_data->parent = &rb_random_data_type;
#endif
}

#endif /* RUBY_RANDOM_H */
