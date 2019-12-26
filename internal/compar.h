#ifndef INTERNAL_COMPAR_H /* -*- C -*- */
#define INTERNAL_COMPAR_H
/**
 * @file
 * @brief      Internal header for Comparable.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/ruby.h"          /* for RUBY_INTEGER_UNIFICATION */
#include "internal/vm.h"        /* for rb_method_basic_definition_p */

#define STRING_P(s) (RB_TYPE_P((s), T_STRING) && CLASS_OF(s) == rb_cString)

#ifdef RUBY_INTEGER_UNIFICATION
# define rb_cFixnum rb_cInteger
# define rb_cBignum rb_cInteger
#endif

enum {
    cmp_opt_Fixnum,
    cmp_opt_String,
    cmp_opt_Float,
    cmp_optimizable_count
};

struct cmp_opt_data {
    unsigned int opt_methods;
    unsigned int opt_inited;
};

#define NEW_CMP_OPT_MEMO(type, value) \
    NEW_PARTIAL_MEMO_FOR(type, value, cmp_opt)
#define CMP_OPTIMIZABLE_BIT(type) (1U << TOKEN_PASTE(cmp_opt_,type))
#define CMP_OPTIMIZABLE(data, type) \
    (((data).opt_inited & CMP_OPTIMIZABLE_BIT(type)) ? \
     ((data).opt_methods & CMP_OPTIMIZABLE_BIT(type)) : \
     (((data).opt_inited |= CMP_OPTIMIZABLE_BIT(type)), \
      rb_method_basic_definition_p(TOKEN_PASTE(rb_c,type), id_cmp) && \
      ((data).opt_methods |= CMP_OPTIMIZABLE_BIT(type))))

#define OPTIMIZED_CMP(a, b, data) \
    ((FIXNUM_P(a) && FIXNUM_P(b) && CMP_OPTIMIZABLE(data, Fixnum)) ? \
     (((long)a > (long)b) ? 1 : ((long)a < (long)b) ? -1 : 0) : \
     (STRING_P(a) && STRING_P(b) && CMP_OPTIMIZABLE(data, String)) ? \
     rb_str_cmp(a, b) : \
     (RB_FLOAT_TYPE_P(a) && RB_FLOAT_TYPE_P(b) && CMP_OPTIMIZABLE(data, Float)) ? \
     rb_float_cmp(a, b) : \
     rb_cmpint(rb_funcallv(a, id_cmp, 1, &b), a, b))

/* compar.c */
VALUE rb_invcmp(VALUE, VALUE);

#endif /* INTERNAL_COMPAR_H */
