/**********************************************************************

  intern.h -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/
#ifndef INTERN_H
#define INTERN_H

#include "defines.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

/*
 * Functions and variables that are used by more than one source file of
 * the kernel.
 */

#define ID_ALLOCATOR 1

/* array.c */
void rb_mem_clear _((register VALUE*, register long));
VALUE rb_assoc_new _((VALUE, VALUE));
VALUE rb_check_array_type _((VALUE));
VALUE rb_ary_new _((void));
VALUE rb_ary_new2 _((long));
VALUE rb_ary_new3 __((long,...));
VALUE rb_ary_new4 _((long, const VALUE *));
VALUE rb_ary_freeze _((VALUE));
VALUE rb_ary_aref _((int, VALUE*, VALUE));
void rb_ary_store _((VALUE, long, VALUE));
VALUE rb_ary_dup _((VALUE));
VALUE rb_ary_to_ary _((VALUE));
VALUE rb_ary_to_s _((VALUE));
VALUE rb_ary_push _((VALUE, VALUE));
VALUE rb_ary_pop _((VALUE));
VALUE rb_ary_shift _((VALUE));
VALUE rb_ary_unshift _((VALUE, VALUE));
VALUE rb_ary_entry _((VALUE, long));
VALUE rb_ary_each _((VALUE));
VALUE rb_ary_join _((VALUE, VALUE));
VALUE rb_ary_reverse _((VALUE));
VALUE rb_ary_sort _((VALUE));
VALUE rb_ary_sort_bang _((VALUE));
VALUE rb_ary_delete _((VALUE, VALUE));
VALUE rb_ary_delete_at _((VALUE, long));
VALUE rb_ary_clear _((VALUE));
VALUE rb_ary_plus _((VALUE, VALUE));
VALUE rb_ary_concat _((VALUE, VALUE));
VALUE rb_ary_assoc _((VALUE, VALUE));
VALUE rb_ary_rassoc _((VALUE, VALUE));
VALUE rb_ary_includes _((VALUE, VALUE));
VALUE rb_ary_cmp _((VALUE, VALUE));
VALUE rb_protect_inspect _((VALUE(*)(ANYARGS),VALUE,VALUE));
VALUE rb_inspecting_p _((VALUE));
VALUE rb_check_array_value _((VALUE));
VALUE rb_values_at _((VALUE, long, int, VALUE*, VALUE(*) _((VALUE,long))));
/* bignum.c */
VALUE rb_big_clone _((VALUE));
void rb_big_2comp _((VALUE));
VALUE rb_big_norm _((VALUE));
VALUE rb_uint2big _((unsigned long));
VALUE rb_int2big _((long));
VALUE rb_uint2inum _((unsigned long));
VALUE rb_int2inum _((long));
VALUE rb_cstr_to_inum _((const char*, int, int));
VALUE rb_str_to_inum _((VALUE, int, int));
VALUE rb_cstr2inum _((const char*, int));
VALUE rb_str2inum _((VALUE, int));
VALUE rb_big2str _((VALUE, int));
VALUE rb_big2str0 _((VALUE, int, int));
long rb_big2long _((VALUE));
#define rb_big2int(x) rb_big2long(x)
unsigned long rb_big2ulong _((VALUE));
#define rb_big2uint(x) rb_big2ulong(x)
#if HAVE_LONG_LONG
VALUE rb_ll2inum _((LONG_LONG));
VALUE rb_ull2inum _((unsigned LONG_LONG));
LONG_LONG rb_big2ll _((VALUE));
unsigned LONG_LONG rb_big2ull _((VALUE));
#endif  /* HAVE_LONG_LONG */
void rb_quad_pack _((char*,VALUE));
VALUE rb_quad_unpack _((const char*,int));
void rb_big_pack(VALUE val, unsigned long *buf, long num_longs);
VALUE rb_big_unpack(unsigned long *buf, long num_longs);
VALUE rb_dbl2big _((double));
double rb_big2dbl _((VALUE));
VALUE rb_big_plus _((VALUE, VALUE));
VALUE rb_big_minus _((VALUE, VALUE));
VALUE rb_big_mul _((VALUE, VALUE));
VALUE rb_big_divmod _((VALUE, VALUE));
VALUE rb_big_pow _((VALUE, VALUE));
VALUE rb_big_and _((VALUE, VALUE));
VALUE rb_big_or _((VALUE, VALUE));
VALUE rb_big_xor _((VALUE, VALUE));
VALUE rb_big_lshift _((VALUE, VALUE));
VALUE rb_big_rand _((VALUE, double*));
/* class.c */
VALUE rb_class_boot _((VALUE));
VALUE rb_class_new _((VALUE));
VALUE rb_mod_init_copy _((VALUE, VALUE));
VALUE rb_class_init_copy _((VALUE, VALUE));
VALUE rb_singleton_class_clone _((VALUE));
void rb_singleton_class_attached _((VALUE,VALUE));
VALUE rb_make_metaclass _((VALUE, VALUE));
void rb_check_inheritable _((VALUE));
VALUE rb_class_inherited _((VALUE, VALUE));
VALUE rb_define_class_id _((ID, VALUE));
VALUE rb_module_new _((void));
VALUE rb_define_module_id _((ID));
VALUE rb_mod_included_modules _((VALUE));
VALUE rb_mod_include_p _((VALUE, VALUE));
VALUE rb_mod_ancestors _((VALUE));
VALUE rb_class_instance_methods _((int, VALUE*, VALUE));
VALUE rb_class_public_instance_methods _((int, VALUE*, VALUE));
VALUE rb_class_protected_instance_methods _((int, VALUE*, VALUE));
VALUE rb_big_rshift(VALUE, VALUE);
VALUE rb_class_private_instance_methods _((int, VALUE*, VALUE));
VALUE rb_obj_singleton_methods _((int, VALUE*, VALUE));
void rb_define_method_id _((VALUE, ID, VALUE (*)(ANYARGS), int));
void rb_frozen_class_p _((VALUE));
void rb_undef _((VALUE, ID));
void rb_define_protected_method _((VALUE, const char*, VALUE (*)(ANYARGS), int));
void rb_define_private_method _((VALUE, const char*, VALUE (*)(ANYARGS), int));
void rb_define_singleton_method _((VALUE, const char*, VALUE(*)(ANYARGS), int));
VALUE rb_singleton_class _((VALUE));
/* compar.c */
int rb_cmpint _((VALUE, VALUE, VALUE));
NORETURN(void rb_cmperr _((VALUE, VALUE)));
/* enum.c */
VALUE rb_block_call _((VALUE, ID, int, VALUE*, VALUE (*)(ANYARGS), VALUE));
/* enumerator.c */
VALUE rb_enumeratorize _((VALUE, VALUE, int, VALUE *));
#define RETURN_ENUMERATOR(obj, argc, argv) do {				\
	if (!rb_block_given_p())					\
	    return rb_enumeratorize(obj, ID2SYM(rb_frame_this_func()),	\
				    argc, argv);			\
    } while (0)
/* error.c */
RUBY_EXTERN int ruby_nerrs;
VALUE rb_exc_new _((VALUE, const char*, long));
VALUE rb_exc_new2 _((VALUE, const char*));
VALUE rb_exc_new3 _((VALUE, VALUE));
NORETURN(void rb_loaderror __((const char*, ...)));
NORETURN(void rb_name_error __((ID, const char*, ...)));
NORETURN(void rb_invalid_str _((const char*, const char*)));
void rb_compile_error __((const char*, ...));
void rb_compile_error_append __((const char*, ...));
NORETURN(void rb_load_fail _((const char*)));
NORETURN(void rb_error_frozen _((const char*)));
void rb_check_frozen _((VALUE));
/* eval.c */
RUBY_EXTERN struct RNode *ruby_current_node;
void ruby_set_current_source _((void));
NORETURN(void rb_exc_raise _((VALUE)));
NORETURN(void rb_exc_fatal _((VALUE)));
VALUE rb_f_exit _((int,VALUE*));
VALUE rb_f_abort _((int,VALUE*));
void rb_remove_method _((VALUE, const char*));
#define rb_disable_super(klass, name) ((void)0)
#define rb_enable_super(klass, name) ((void)0)
#define HAVE_RB_DEFINE_ALLOC_FUNC 1
void rb_define_alloc_func _((VALUE, VALUE (*)(VALUE)));
void rb_undef_alloc_func _((VALUE));
void rb_clear_cache _((void));
void rb_clear_cache_by_class _((VALUE));
void rb_alias _((VALUE, ID, ID));
void rb_attr _((VALUE,ID,int,int,int));
int rb_method_boundp _((VALUE, ID, int));
VALUE rb_dvar_defined _((ID));
VALUE rb_dvar_curr _((ID));
VALUE rb_dvar_ref _((ID));
void rb_dvar_asgn _((ID, VALUE));
void rb_dvar_push _((ID, VALUE));
VALUE *rb_svar _((int));
VALUE rb_eval_cmd _((VALUE, VALUE, int));
VALUE rb_obj_is_proc _((VALUE));
int rb_obj_respond_to _((VALUE, ID, int));
int rb_respond_to _((VALUE, ID));
void rb_interrupt _((void));
VALUE rb_apply _((VALUE, ID, VALUE));
void rb_backtrace _((void));
ID rb_frame_last_func _((void));
ID rb_frame_this_func _((void));
VALUE rb_obj_instance_eval _((int, VALUE*, VALUE));
VALUE rb_mod_module_eval _((int, VALUE*, VALUE));
void rb_load _((VALUE, int));
void rb_load_protect _((VALUE, int, int*));
NORETURN(void rb_jump_tag _((int)));
int rb_provided _((const char*));
void rb_provide _((const char*));
VALUE rb_f_require _((VALUE, VALUE));
VALUE rb_require_safe _((VALUE, int));
void rb_obj_call_init _((VALUE, int, VALUE*));
VALUE rb_class_new_instance _((int, VALUE*, VALUE));
VALUE rb_block_proc _((void));
VALUE rb_block_dup _((VALUE, VALUE, VALUE));
VALUE rb_method_dup _((VALUE, VALUE, VALUE));
VALUE rb_f_lambda _((void));
VALUE rb_proc_call _((VALUE, VALUE));
VALUE rb_obj_method _((VALUE, VALUE));
VALUE rb_protect _((VALUE (*)(VALUE), VALUE, int*));
void rb_set_end_proc _((void (*)(VALUE), VALUE));
void rb_mark_end_proc _((void));
void rb_exec_end_proc _((void));
void ruby_finalize _((void));
NORETURN(void ruby_stop _((int)));
int ruby_cleanup _((int));
int ruby_exec _((void));
void rb_gc_mark_threads _((void));
void rb_thread_start_timer _((void));
void rb_thread_stop_timer _((void));
void rb_thread_schedule _((void));
void rb_thread_wait_fd _((int));
int rb_thread_fd_writable _((int));
void rb_thread_fd_close _((int));
int rb_thread_alone _((void));
void rb_thread_polling _((void));
void rb_thread_sleep _((int));
void rb_thread_sleep_forever _((void));
VALUE rb_thread_stop _((void));
VALUE rb_thread_wakeup _((VALUE));
VALUE rb_thread_wakeup_alive _((VALUE));
VALUE rb_thread_run _((VALUE));
VALUE rb_thread_kill _((VALUE));
VALUE rb_thread_alive_p _((VALUE));
VALUE rb_thread_create _((VALUE (*)(ANYARGS), void*));
void rb_thread_interrupt _((void));
int rb_thread_join _((VALUE thread, double limit));
void rb_thread_trap_eval _((VALUE, int, int));
void rb_thread_signal_raise _((int));
void rb_thread_signal_exit _((void));
int rb_thread_select _((int, fd_set *, fd_set *, fd_set *, struct timeval *));
void rb_thread_wait_for _((struct timeval));
VALUE rb_thread_current _((void));
VALUE rb_thread_main _((void));
VALUE rb_thread_local_aref _((VALUE, ID));
VALUE rb_thread_local_aset _((VALUE, ID, VALUE));
void rb_thread_atfork _((void));
VALUE rb_exec_recursive _((VALUE(*)(VALUE, VALUE, int),VALUE,VALUE));
VALUE rb_funcall_rescue __((VALUE, ID, int, ...));
/* file.c */
VALUE rb_file_s_expand_path _((int, VALUE *));
VALUE rb_file_expand_path _((VALUE, VALUE));
void rb_file_const _((const char*, VALUE));
int rb_find_file_ext _((VALUE*, const char* const*));
VALUE rb_find_file _((VALUE));
char *rb_path_next _((const char *));
char *rb_path_skip_prefix _((const char *));
char *rb_path_last_separator _((const char *));
char *rb_path_end _((const char *));
VALUE rb_file_directory_p _((VALUE,VALUE));
/* gc.c */
NORETURN(void rb_memerror __((void)));
int ruby_stack_check _((void));
size_t ruby_stack_length _((VALUE**));
int rb_during_gc _((void));
char *rb_source_filename _((const char*));
void rb_gc_mark_locations _((VALUE*, VALUE*));
void rb_mark_tbl _((struct st_table*));
void rb_mark_set _((struct st_table*));
void rb_mark_hash _((struct st_table*));
void rb_gc_mark_maybe _((VALUE));
void rb_gc_mark _((VALUE));
void rb_gc_force_recycle _((VALUE));
void rb_gc _((void));
void rb_gc_copy_finalizer _((VALUE,VALUE));
void rb_gc_finalize_deferred _((void));
void rb_gc_call_finalizer_at_exit _((void));
VALUE rb_gc_enable _((void));
VALUE rb_gc_disable _((void));
VALUE rb_gc_start _((void));
#define Init_stack(addr) ruby_init_stack(addr)
/* hash.c */
void st_foreach_safe _((struct st_table *, int (*)(ANYARGS), unsigned long));
void rb_hash_foreach _((VALUE, int (*)(ANYARGS), VALUE));
VALUE rb_hash _((VALUE));
VALUE rb_hash_new _((void));
VALUE rb_hash_freeze _((VALUE));
VALUE rb_hash_aref _((VALUE, VALUE));
VALUE rb_hash_lookup _((VALUE, VALUE));
VALUE rb_hash_aset _((VALUE, VALUE, VALUE));
VALUE rb_hash_delete_if _((VALUE));
VALUE rb_hash_delete _((VALUE,VALUE));
int rb_path_check _((const char*));
int rb_env_path_tainted _((void));
/* io.c */
#define rb_defout rb_stdout
RUBY_EXTERN VALUE rb_fs;
RUBY_EXTERN VALUE rb_output_fs;
RUBY_EXTERN VALUE rb_rs;
RUBY_EXTERN VALUE rb_default_rs;
RUBY_EXTERN VALUE rb_output_rs;
VALUE rb_io_write _((VALUE, VALUE));
VALUE rb_io_gets _((VALUE));
VALUE rb_io_getc _((VALUE));
VALUE rb_io_ungetc _((VALUE, VALUE));
VALUE rb_io_close _((VALUE));
VALUE rb_io_eof _((VALUE));
VALUE rb_io_binmode _((VALUE));
VALUE rb_io_addstr _((VALUE, VALUE));
VALUE rb_io_printf _((int, VALUE*, VALUE));
VALUE rb_io_print _((int, VALUE*, VALUE));
VALUE rb_io_puts _((int, VALUE*, VALUE));
VALUE rb_file_open _((const char*, const char*));
VALUE rb_gets _((void));
void rb_write_error _((const char*));
void rb_write_error2 _((const char*, long));
/* marshal.c */
VALUE rb_marshal_dump _((VALUE, VALUE));
VALUE rb_marshal_load _((VALUE));
/* numeric.c */
void rb_num_zerodiv _((void));
VALUE rb_num_coerce_bin _((VALUE, VALUE));
VALUE rb_num_coerce_cmp _((VALUE, VALUE));
VALUE rb_num_coerce_relop _((VALUE, VALUE));
VALUE rb_float_new _((double));
VALUE rb_num2fix _((VALUE));
VALUE rb_fix2str _((VALUE, int));
VALUE rb_dbl_cmp _((double, double));
/* object.c */
int rb_eql _((VALUE, VALUE));
VALUE rb_any_to_s _((VALUE));
VALUE rb_inspect _((VALUE));
VALUE rb_obj_is_instance_of _((VALUE, VALUE));
VALUE rb_obj_is_kind_of _((VALUE, VALUE));
VALUE rb_obj_alloc _((VALUE));
VALUE rb_obj_clone _((VALUE));
VALUE rb_obj_dup _((VALUE));
VALUE rb_obj_init_copy _((VALUE,VALUE));
VALUE rb_obj_taint _((VALUE));
VALUE rb_obj_tainted _((VALUE));
VALUE rb_obj_untaint _((VALUE));
VALUE rb_obj_freeze _((VALUE));
VALUE rb_obj_id _((VALUE));
VALUE rb_obj_class _((VALUE));
VALUE rb_sym_to_s _((VALUE));
VALUE rb_class_real _((VALUE));
VALUE rb_class_inherited_p _((VALUE, VALUE));
VALUE rb_convert_type _((VALUE,int,const char*,const char*));
VALUE rb_check_convert_type _((VALUE,int,const char*,const char*));
VALUE rb_check_to_integer _((VALUE, const char *));
VALUE rb_to_int _((VALUE));
VALUE rb_Integer _((VALUE));
VALUE rb_Float _((VALUE));
VALUE rb_String _((VALUE));
VALUE rb_Array _((VALUE));
double rb_cstr_to_dbl _((const char*, int));
double rb_str_to_dbl _((VALUE, int));
/* pack.c */
unsigned long rb_utf8_to_uv _((char *, long *));
/* parse.y */
RUBY_EXTERN int   ruby_sourceline;
RUBY_EXTERN char *ruby_sourcefile;
int ruby_yyparse _((void));
ID rb_id_attrset _((ID));
void rb_parser_append_print _((void));
void rb_parser_while_loop _((int, int));
int ruby_parser_stack_on_heap _((void));
void rb_gc_mark_parser _((void));
int rb_is_const_id _((ID));
int rb_is_instance_id _((ID));
int rb_is_class_id _((ID));
int rb_is_local_id _((ID));
int rb_is_junk_id _((ID));
int rb_symname_p _((const char*));
int rb_sym_interned_p _((VALUE));
VALUE rb_backref_get _((void));
void rb_backref_set _((VALUE));
VALUE rb_lastline_get _((void));
void rb_lastline_set _((VALUE));
VALUE rb_sym_all_symbols _((void));
/* process.c */
int rb_proc_exec _((const char*));
VALUE rb_f_exec _((int,VALUE*));
int rb_waitpid _((int,int*,int));
void rb_syswait _((int));
VALUE rb_proc_times _((VALUE));
VALUE rb_detach_process _((int));
/* range.c */
VALUE rb_range_new _((VALUE, VALUE, int));
VALUE rb_range_beg_len _((VALUE, long*, long*, long, int));
VALUE rb_length_by_each _((VALUE));
/* random.c */
unsigned long rb_genrand_int32(void);
double rb_genrand_real(void);
void rb_reset_random_seed(void);
/* re.c */
int rb_memcmp _((const void*,const void*,long));
int rb_memcicmp _((const void*,const void*,long));
long rb_memsearch _((const void*,long,const void*,long));
VALUE rb_reg_nth_defined _((int, VALUE));
VALUE rb_reg_nth_match _((int, VALUE));
VALUE rb_reg_last_match _((VALUE));
VALUE rb_reg_match_pre _((VALUE));
VALUE rb_reg_match_post _((VALUE));
VALUE rb_reg_match_last _((VALUE));
VALUE rb_reg_new _((const char*, long, int));
VALUE rb_reg_match _((VALUE, VALUE));
VALUE rb_reg_match2 _((VALUE));
int rb_reg_options _((VALUE));
void rb_set_kcode _((const char*));
const char* rb_get_kcode _((void));
void rb_kcode_set_option _((VALUE));
void rb_kcode_reset_option _((void));
/* ruby.c */
RUBY_EXTERN VALUE rb_argv;
RUBY_EXTERN VALUE rb_argv0;
void rb_load_file _((const char*));
void ruby_script _((const char*));
void ruby_prog_init _((void));
void ruby_set_argv _((int, char**));
void ruby_process_options _((int, char**));
void ruby_load_script _((void));
void ruby_init_loadpath _((void));
void ruby_incpush _((const char*));
/* signal.c */
VALUE rb_f_kill _((int, VALUE*));
void rb_gc_mark_trap_list _((void));
#ifdef POSIX_SIGNAL
#define posix_signal ruby_posix_signal
void posix_signal _((int, RETSIGTYPE (*)(int)));
#endif
void rb_trap_exit _((void));
void rb_trap_exec _((void));
const char *ruby_signal_name _((int));
void ruby_default_signal _((int));
/* sprintf.c */
VALUE rb_f_sprintf _((int, VALUE*));
VALUE rb_str_format _((int, VALUE*, VALUE));
/* string.c */
VALUE rb_str_new _((const char*, long));
VALUE rb_str_new2 _((const char*));
VALUE rb_str_new3 _((VALUE));
VALUE rb_str_new4 _((VALUE));
VALUE rb_str_new5 _((VALUE, const char*, long));
VALUE rb_tainted_str_new _((const char*, long));
VALUE rb_tainted_str_new2 _((const char*));
VALUE rb_str_buf_new _((long));
VALUE rb_str_buf_new2 _((const char*));
VALUE rb_str_tmp_new _((long));
VALUE rb_str_buf_append _((VALUE, VALUE));
VALUE rb_str_buf_cat _((VALUE, const char*, long));
VALUE rb_str_buf_cat2 _((VALUE, const char*));
#define rb_usascii_str_new rb_str_new
#define rb_usascii_str_new_cstr rb_str_new_cstr
#define rb_usascii_str_new2 rb_str_new2
VALUE rb_obj_as_string _((VALUE));
VALUE rb_check_string_type _((VALUE));
VALUE rb_str_dup _((VALUE));
VALUE rb_str_locktmp _((VALUE));
VALUE rb_str_unlocktmp _((VALUE));
VALUE rb_str_dup_frozen _((VALUE));
VALUE rb_str_plus _((VALUE, VALUE));
VALUE rb_str_times _((VALUE, VALUE));
VALUE rb_str_substr _((VALUE, long, long));
void rb_str_modify _((VALUE));
VALUE rb_str_freeze _((VALUE));
void rb_str_set_len _((VALUE, long));
VALUE rb_str_resize _((VALUE, long));
VALUE rb_str_cat _((VALUE, const char*, long));
VALUE rb_str_cat2 _((VALUE, const char*));
VALUE rb_str_append _((VALUE, VALUE));
VALUE rb_str_concat _((VALUE, VALUE));
int rb_str_hash _((VALUE));
int rb_str_cmp _((VALUE, VALUE));
VALUE rb_str_upto _((VALUE, VALUE, int));
void rb_str_update _((VALUE, long, long, VALUE));
VALUE rb_str_inspect _((VALUE));
VALUE rb_str_dump _((VALUE));
VALUE rb_str_split _((VALUE, const char*));
void rb_str_associate _((VALUE, VALUE));
VALUE rb_str_associated _((VALUE));
void rb_str_setter _((VALUE, ID, VALUE*));
VALUE rb_str_intern _((VALUE));
/* struct.c */
VALUE rb_struct_new __((VALUE, ...));
VALUE rb_struct_define __((const char*, ...));
VALUE rb_struct_alloc _((VALUE, VALUE));
VALUE rb_struct_aref _((VALUE, VALUE));
VALUE rb_struct_aset _((VALUE, VALUE, VALUE));
VALUE rb_struct_getmember _((VALUE, ID));
VALUE rb_struct_iv_get _((VALUE, const char*));
VALUE rb_struct_s_members _((VALUE));
VALUE rb_struct_members _((VALUE));
/* time.c */
VALUE rb_time_new _((time_t, time_t));
/* variable.c */
VALUE rb_mod_name _((VALUE));
VALUE rb_class_path _((VALUE));
void rb_set_class_path _((VALUE, VALUE, const char*));
VALUE rb_path2class _((const char*));
void rb_name_class _((VALUE, ID));
VALUE rb_class_name _((VALUE));
void rb_autoload _((VALUE, ID, const char*));
VALUE rb_autoload_load _((VALUE, ID));
VALUE rb_autoload_p _((VALUE, ID));
void rb_gc_mark_global_tbl _((void));
VALUE rb_f_trace_var _((int, VALUE*));
VALUE rb_f_untrace_var _((int, VALUE*));
VALUE rb_f_global_variables _((void));
void rb_alias_variable _((ID, ID));
struct st_table* rb_generic_ivar_table _((VALUE));
void rb_copy_generic_ivar _((VALUE,VALUE));
void rb_mark_generic_ivar _((VALUE));
void rb_mark_generic_ivar_tbl _((void));
void rb_free_generic_ivar _((VALUE));
VALUE rb_ivar_get _((VALUE, ID));
VALUE rb_ivar_set _((VALUE, ID, VALUE));
VALUE rb_ivar_defined _((VALUE, ID));
VALUE rb_iv_set _((VALUE, const char*, VALUE));
VALUE rb_iv_get _((VALUE, const char*));
VALUE rb_attr_get _((VALUE, ID));
VALUE rb_obj_instance_variables _((VALUE));
VALUE rb_obj_remove_instance_variable _((VALUE, VALUE));
void *rb_mod_const_at _((VALUE, void*));
void *rb_mod_const_of _((VALUE, void*));
VALUE rb_const_list _((void*));
VALUE rb_mod_constants _((VALUE));
VALUE rb_mod_remove_const _((VALUE, VALUE));
int rb_const_defined _((VALUE, ID));
int rb_const_defined_at _((VALUE, ID));
int rb_const_defined_from _((VALUE, ID));
VALUE rb_const_get _((VALUE, ID));
VALUE rb_const_get_at _((VALUE, ID));
VALUE rb_const_get_from _((VALUE, ID));
void rb_const_set _((VALUE, ID, VALUE));
VALUE rb_const_remove _((VALUE, ID));
VALUE rb_mod_constants _((VALUE));
VALUE rb_mod_const_missing _((VALUE,VALUE));
VALUE rb_cvar_defined _((VALUE, ID));
#define RB_CVAR_SET_4ARGS 1
void rb_cvar_set _((VALUE, ID, VALUE, int));
VALUE rb_cvar_get _((VALUE, ID));
void rb_cv_set _((VALUE, const char*, VALUE));
VALUE rb_cv_get _((VALUE, const char*));
void rb_define_class_variable _((VALUE, const char*, VALUE));
VALUE rb_mod_class_variables _((VALUE));
VALUE rb_mod_remove_cvar _((VALUE, VALUE));
/* version.c */
void ruby_show_version _((void));
void ruby_show_copyright _((void));

#endif
