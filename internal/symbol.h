#ifndef INTERNAL_SYMBOL_H /* -*- C -*- */
#define INTERNAL_SYMBOL_H
/**
 * @file
 * @brief      Internal header for Symbol.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* symbol.c */
#ifdef RUBY_ENCODING_H
VALUE rb_sym_intern(const char *ptr, long len, rb_encoding *enc);
#endif
VALUE rb_sym_intern_ascii(const char *ptr, long len);
VALUE rb_sym_intern_ascii_cstr(const char *ptr);
#ifdef __GNUC__
#define rb_sym_intern_ascii_cstr(ptr) __extension__ ( \
{                                               \
    (__builtin_constant_p(ptr)) ?               \
        rb_sym_intern_ascii((ptr), (long)strlen(ptr)) : \
        rb_sym_intern_ascii_cstr(ptr); \
})
#endif
VALUE rb_to_symbol_type(VALUE obj);

#endif /* INTERNAL_SYMBOL_H */
