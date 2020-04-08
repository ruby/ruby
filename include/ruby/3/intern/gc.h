/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
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
 * @brief      Public APIs related to ::rb_mGC.
 */
#ifndef  RUBY3_INTERN_GC_H
#define  RUBY3_INTERN_GC_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/attributes.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

/* gc.c */
COLDFUNC NORETURN(void rb_memerror(void));
PUREFUNC(int rb_during_gc(void));
void rb_gc_mark_locations(const VALUE*, const VALUE*);
void rb_mark_tbl(struct st_table*);
void rb_mark_tbl_no_pin(struct st_table*);
void rb_mark_set(struct st_table*);
void rb_mark_hash(struct st_table*);
void rb_gc_update_tbl_refs(st_table *ptr);
void rb_gc_mark_maybe(VALUE);
void rb_gc_mark(VALUE);
void rb_gc_mark_movable(VALUE);
VALUE rb_gc_location(VALUE);
void rb_gc_force_recycle(VALUE);
void rb_gc(void);
void rb_gc_copy_finalizer(VALUE,VALUE);
VALUE rb_gc_enable(void);
VALUE rb_gc_disable(void);
VALUE rb_gc_start(void);
VALUE rb_define_finalizer(VALUE, VALUE);
VALUE rb_undefine_finalizer(VALUE);
size_t rb_gc_count(void);
size_t rb_gc_stat(VALUE);
VALUE rb_gc_latest_gc_info(VALUE);
void rb_gc_adjust_memory_usage(ssize_t);

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_GC_H */
