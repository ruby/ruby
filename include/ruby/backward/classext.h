#ifndef RUBY_BACKWARD_CLASSEXT_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD_CLASSEXT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#if   defined __GNUC__
#warning use of RClass internals is deprecated
#elif defined _MSC_VER
#pragma message("warning: use of RClass internals is deprecated")
#endif

typedef struct rb_deprecated_classext_struct {
    VALUE super;
} rb_deprecated_classext_t;

#undef RCLASS_SUPER(c)
#define RCLASS_EXT(c) ((rb_deprecated_classext_t *)RCLASS(c)->ptr)
#define RCLASS_SUPER(c) (RCLASS(c)->super)

#endif /* RUBY_BACKWARD_CLASSEXT_H */
