#ifndef INTERNAL_PARSE_H /* -*- C -*- */
#define INTERNAL_PARSE_H
/**
 * @file
 * @brief      Internal header for the parser.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/ruby.h"          /* for VALUE */

#ifndef USE_SYMBOL_GC
# define USE_SYMBOL_GC 1
#endif

struct rb_iseq_struct;          /* in vm_core.h */

/* parse.y */
VALUE rb_parser_set_yydebug(VALUE, VALUE);
void *rb_parser_load_file(VALUE parser, VALUE name);

RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_parser_set_context(VALUE, const struct rb_iseq_struct *, int);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_PARSE_H */
