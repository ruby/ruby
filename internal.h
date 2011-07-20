/**********************************************************************

  internal.h -

  $Author$
  created at: Tue May 17 11:42:20 JST 2011

  Copyright (C) 2011 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_INTERNAL_H
#define RUBY_INTERNAL_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

struct rb_deprecated_classext_struct {
    char conflict[sizeof(VALUE) * 3];
};

struct rb_classext_struct {
    VALUE super;
    struct st_table *iv_tbl;
    struct st_table *const_tbl;
};

#undef RCLASS_SUPER
#define RCLASS_EXT(c) (RCLASS(c)->ptr)
#define RCLASS_SUPER(c) (RCLASS_EXT(c)->super)
#define RCLASS_IV_TBL(c) (RCLASS_EXT(c)->iv_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#define RCLASS_M_TBL(c) (RCLASS(c)->m_tbl)
#define RCLASS_IV_INDEX_TBL(c) (RCLASS(c)->iv_index_tbl)

struct vtm; /* defined by timev.h */

/* array.c */
VALUE rb_ary_last(int, VALUE *, VALUE);

/* bignum.c */
VALUE rb_big_fdiv(VALUE x, VALUE y);
VALUE rb_big_uminus(VALUE x);

/* class.c */
VALUE rb_obj_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, VALUE *argv, VALUE obj);
int rb_obj_basic_to_s_p(VALUE);
void Init_class_hierarchy(void);

/* compile.c */
int rb_dvar_defined(ID);
int rb_local_defined(ID);
int rb_parse_in_eval(void);
int rb_parse_in_main(void);
VALUE rb_insns_name_array(void);

/* debug.c */
PRINTF_ARGS(void ruby_debug_printf(const char*, ...), 1, 2);

/* dmyext.c */
void Init_ext(void);

/* encoding.c */
ID rb_id_encoding(void);

/* encoding.c */
void rb_gc_mark_encodings(void);

/* error.c */
NORETURN(PRINTF_ARGS(void rb_compile_bug(const char*, int, const char*, ...), 3, 4));
VALUE rb_check_backtrace(VALUE);
NORETURN(void rb_async_bug_errno(const char *,int));

/* eval_error.c */
void ruby_error_print(void);
VALUE rb_get_backtrace(VALUE info);

/* eval_jump.c */
void rb_call_end_proc(VALUE data);

/* file.c */
VALUE rb_home_dir(const char *user, VALUE result);
VALUE rb_realpath_internal(VALUE basedir, VALUE path, int strict);
void Init_File(void);

/* gc.c */
void Init_heap(void);

/* inits.c */
void rb_call_inits(void);

/* io.c */
const char *ruby_get_inplace_mode(void);
void ruby_set_inplace_mode(const char *);
ssize_t rb_io_bufread(VALUE io, void *buf, size_t size);
void rb_stdio_set_default_encoding(void);

/* iseq.c */
VALUE rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE filepath, VALUE line, VALUE opt);
VALUE rb_iseq_clone(VALUE iseqval, VALUE newcbase);

/* load.c */
VALUE rb_get_load_path(void);

/* math.c */
VALUE rb_math_atan2(VALUE, VALUE);
VALUE rb_math_cos(VALUE);
VALUE rb_math_cosh(VALUE);
VALUE rb_math_exp(VALUE);
VALUE rb_math_hypot(VALUE, VALUE);
VALUE rb_math_log(int argc, VALUE *argv);
VALUE rb_math_sin(VALUE);
VALUE rb_math_sinh(VALUE);
VALUE rb_math_sqrt(VALUE);

/* newline.c */
void Init_newline(void);

/* numeric.c */
int rb_num_to_uint(VALUE val, unsigned int *ret);
int ruby_float_step(VALUE from, VALUE to, VALUE step, int excl);

/* object.c */
VALUE rb_obj_equal(VALUE obj1, VALUE obj2);

/* parse.y */
VALUE rb_parser_get_yydebug(VALUE);
VALUE rb_parser_set_yydebug(VALUE, VALUE);

/* proc.c */
VALUE rb_proc_location(VALUE self);

/* rational.c */
VALUE rb_lcm(VALUE x, VALUE y);
VALUE rb_rational_reciprocal(VALUE x);

/* re.c */
VALUE rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline);
VALUE rb_reg_check_preprocess(VALUE);

/* signal.c */
int rb_get_next_signal(void);

/* strftime.c */
size_t rb_strftime_timespec(char *s, size_t maxsize, const char *format, const struct vtm *vtm, struct timespec *ts, int gmt);

/* string.c */
int rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p);

/* struct.c */
VALUE rb_struct_init_copy(VALUE copy, VALUE s);

/* time.c */
struct timeval rb_time_timeval(VALUE);

/* thread.c */
VALUE rb_obj_is_mutex(VALUE obj);
VALUE ruby_suppress_tracing(VALUE (*func)(VALUE, int), VALUE arg, int always);
void rb_thread_execute_interrupts(VALUE th);
void rb_clear_trace_func(void);
VALUE rb_thread_backtrace(VALUE thval);
VALUE rb_get_coverages(void);

/* thread_pthread.c, thread_win32.c */
void Init_native_thread(void);

/* vm.c */
VALUE rb_obj_is_thread(VALUE obj);
void rb_vm_mark(void *ptr);
void Init_BareVM(void);
VALUE rb_vm_top_self(void);
void rb_thread_recycle_stack_release(VALUE *);
void rb_vm_change_state(void);
void rb_vm_inc_const_missing_count(void);
void rb_thread_mark(void *th);
const void **rb_vm_get_insns_address_table(void);

/* vm_dump.c */
void rb_vm_bugreport(void);

/* vm_eval.c */
void Init_vm_eval(void);
VALUE rb_current_realfilepath(void);

/* vm_method.c */
void Init_eval_method(void);

/* miniprelude.c, prelude.c */
void Init_prelude(void);

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility push(default)
#endif
const char *rb_objspace_data_type_name(VALUE obj);

/* Temporary.  This API will be removed (renamed). */
VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);

/* experimental.
 * These APIs can be changed on Ruby 1.9.4 or later.
 * We will change these APIs (spac, name and so on) if there are something wrong.
 * If you use these APIs, catch up future changes.
 */
void *rb_thread_call_with_gvl(void *(*func)(void *), void *data1);
VALUE rb_thread_call_without_gvl(
    rb_blocking_function_t *func, void *data1,
    rb_unblock_function_t *ubf, void *data2);

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility pop
#endif

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_INTERNAL_H */
