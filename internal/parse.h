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

/* parse.y */
#ifndef USE_SYMBOL_GC
#define USE_SYMBOL_GC 1
#endif
VALUE rb_parser_set_yydebug(VALUE, VALUE);
RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_parser_set_context(VALUE, const struct rb_iseq_struct *, int);
RUBY_SYMBOL_EXPORT_END
void *rb_parser_load_file(VALUE parser, VALUE name);
int rb_is_const_name(VALUE name);
int rb_is_class_name(VALUE name);
int rb_is_instance_name(VALUE name);
int rb_is_local_name(VALUE name);
PUREFUNC(int rb_is_const_sym(VALUE sym));
PUREFUNC(int rb_is_attrset_sym(VALUE sym));
ID rb_make_internal_id(void);
void rb_gc_free_dsymbol(VALUE);

#endif /* INTERNAL_PARSE_H */
