#ifndef INTERNAL_VARIABLE_H                              /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_VARIABLE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for variables.
 */
#include "ruby/internal/config.h"
#include <stddef.h>             /* for size_t */
#include "constant.h"           /* for rb_const_entry_t */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/ruby.h"          /* for VALUE */
#include "shape.h"              /* for shape_id_t */

/* variable.c */
void rb_gc_mark_global_tbl(void);
void rb_gc_update_global_tbl(void);
VALUE rb_search_class_path(VALUE);
VALUE rb_attr_delete(VALUE, ID);
void rb_autoload_str(VALUE mod, ID id, VALUE file);
VALUE rb_autoload_at_p(VALUE, ID, int);
void rb_autoload_copy_table_for_box(st_table *, const rb_box_t *);
NORETURN(VALUE rb_mod_const_missing(VALUE,VALUE));
rb_gvar_getter_t *rb_gvar_getter_function_of(ID);
rb_gvar_setter_t *rb_gvar_setter_function_of(ID);
void rb_gvar_readonly_setter(VALUE v, ID id, VALUE *_);
void rb_gvar_ractor_local(const char *name);
void rb_gvar_box_ready(const char *name);
void rb_gvar_box_dynamic(const char *name);

/**
 * Sets the name of a module.
 *
 * Non-permanently named classes can have a temporary name assigned (or
 * cleared). In that case the name will be used for `#inspect` and `#to_s`, and
 * nested classes/modules will be named with the temporary name as a prefix.
 *
 * After the module is assigned to a constant, the temporary name will be
 * discarded, and the name will be computed based on the nesting.
 *
 * @param[in]  mod        An instance of ::rb_cModule.
 * @param[in]  name       An instance of ::rb_cString.
 * @retval     mod
 */
VALUE rb_mod_set_temporary_name(VALUE, VALUE);

void rb_obj_replace_fields(VALUE obj, VALUE fields_obj);
VALUE rb_obj_complex_fields_build(VALUE obj);
VALUE rb_obj_field_get(VALUE obj, shape_id_t target_shape_id);
void rb_ivar_set_internal(VALUE obj, ID id, VALUE val);
void rb_ivar_foreach_buffered(VALUE obj, int (*func)(ID name, VALUE val, st_data_t arg), st_data_t arg);
attr_index_t rb_ivar_set_index(VALUE obj, ID id, VALUE val);
attr_index_t rb_obj_field_set(VALUE obj, shape_id_t target_shape_id, ID field_name, VALUE val);
VALUE rb_ivar_get_at(VALUE obj, attr_index_t index, ID id);
VALUE rb_ivar_get_at_no_ractor_check(VALUE obj, attr_index_t index);
void rb_generic_fields_lock_atfork(void);
void rb_imemo_fields_record_shrefs(VALUE fields_obj);

/* global GC 用の generic_fields weak pass。mark_foreach は全表（shareable 用 global と
 * 全 Ractor の per-Ractor）の各 (key,val) で cb を呼び live key の val を mark する。
 * drain_dead は is_dead(key) が真の entry を削除する。key は既に free/poison 済みかも
 * しれないので key 本体や shape には触らない。 */
void rb_gc_vm_generic_fields_mark_foreach(int (*cb)(VALUE key, VALUE val, void *arg), void *arg);
void rb_gc_vm_generic_fields_drain_dead(bool (*is_dead)(VALUE key));
/* 全 generic_fields 表（global + 全 Ractor per-Ractor）について cb(tbl,arg) を呼ぶ。
 * compaction の参照更新（gc.c）から使う。 */
void rb_generic_fields_tables_foreach(void (*cb)(struct st_table *tbl, void *arg), void *arg);
/* obj の generic_fields entry を owner の per-Ractor 表から shared global 表へ移送。 */
void rb_mv_generic_ivar_to_shared(VALUE obj);

RUBY_SYMBOL_EXPORT_BEGIN
/* variable.c (export) */
void rb_mark_generic_ivar(VALUE obj);
VALUE rb_const_missing(VALUE klass, VALUE name);
bool rb_class_ivar_set(VALUE klass, ID vid, VALUE value);
void rb_fields_tbl_copy(VALUE dst, VALUE src);
RUBY_SYMBOL_EXPORT_END

VALUE rb_ivar_lookup(VALUE obj, ID id, VALUE undef);
VALUE rb_gvar_get(ID);
VALUE rb_gvar_set(ID, VALUE);
VALUE rb_gvar_defined(ID);
void rb_const_warn_if_deprecated(const rb_const_entry_t *, VALUE, ID);

#endif /* INTERNAL_VARIABLE_H */
