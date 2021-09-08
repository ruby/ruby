#ifndef RUBY_TOPLEVEL_VARIABLE_H                         /*-*-C-*-vi:se ft=c:*/
#define RUBY_TOPLEVEL_VARIABLE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* per-object */

struct gen_ivtbl {
    uint32_t numiv;
    VALUE ivptr[FLEX_ARY_LEN];
};

int rb_ivar_generic_ivtbl_lookup(VALUE obj, struct gen_ivtbl **);
VALUE rb_ivar_generic_lookup_with_index(VALUE obj, ID id, uint32_t index);

#endif /* RUBY_TOPLEVEL_VARIABLE_H */
