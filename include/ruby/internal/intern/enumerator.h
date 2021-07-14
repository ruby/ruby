#ifndef RBIMPL_INTERN_ENUMERATOR_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ENUMERATOR_H
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
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_cEnumerator.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/intern/eval.h" /* rb_frame_this_func */
#include "ruby/internal/iterator.h"    /* rb_block_given_p */
#include "ruby/internal/symbol.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

typedef VALUE rb_enumerator_size_func(VALUE, VALUE, VALUE);

typedef struct {
    VALUE begin;
    VALUE end;
    VALUE step;
    int exclude_end;
} rb_arithmetic_sequence_components_t;

/* enumerator.c */
VALUE rb_enumeratorize(VALUE, VALUE, int, const VALUE *);
VALUE rb_enumeratorize_with_size(VALUE, VALUE, int, const VALUE *, rb_enumerator_size_func *);
VALUE rb_enumeratorize_with_size_kw(VALUE, VALUE, int, const VALUE *, rb_enumerator_size_func *, int);
int rb_arithmetic_sequence_extract(VALUE, rb_arithmetic_sequence_components_t *);
VALUE rb_arithmetic_sequence_beg_len_step(VALUE, long *begp, long *lenp, long *stepp, long len, int err);

RBIMPL_SYMBOL_EXPORT_END()

#ifndef RUBY_EXPORT
# define rb_enumeratorize_with_size(obj, id, argc, argv, size_fn) \
    rb_enumeratorize_with_size(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn))
# define rb_enumeratorize_with_size_kw(obj, id, argc, argv, size_fn, kw_splat) \
    rb_enumeratorize_with_size_kw(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn), kw_splat)
#endif

#define SIZED_ENUMERATOR(obj, argc, argv, size_fn)                  \
    rb_enumeratorize_with_size((obj), ID2SYM(rb_frame_this_func()), \
                               (argc), (argv), (size_fn))

#define SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat)        \
    rb_enumeratorize_with_size_kw((obj), ID2SYM(rb_frame_this_func()), \
                                  (argc), (argv), (size_fn), (kw_splat))

#define RETURN_SIZED_ENUMERATOR(obj, argc, argv, size_fn) do {          \
        if (!rb_block_given_p())                                        \
            return SIZED_ENUMERATOR(obj, argc, argv, size_fn);          \
    } while (0)

#define RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat) do { \
        if (!rb_block_given_p())                                            \
            return SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat);              \
    } while (0)

#define RETURN_ENUMERATOR(obj, argc, argv) \
    RETURN_SIZED_ENUMERATOR(obj, argc, argv, 0)

#define RETURN_ENUMERATOR_KW(obj, argc, argv, kw_splat) \
    RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, 0, kw_splat)

#endif /* RBIMPL_INTERN_ENUMERATOR_H */
