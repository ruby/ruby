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
    VALUE origin;
    VALUE refined_class;
    rb_alloc_func_t allocator;
};

#undef RCLASS_SUPER
#define RCLASS_EXT(c) (RCLASS(c)->ptr)
#define RCLASS_SUPER(c) (RCLASS_EXT(c)->super)
#define RCLASS_IV_TBL(c) (RCLASS_EXT(c)->iv_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#define RCLASS_M_TBL(c) (RCLASS(c)->m_tbl)
#define RCLASS_IV_INDEX_TBL(c) (RCLASS(c)->iv_index_tbl)
#define RCLASS_ORIGIN(c) (RCLASS_EXT(c)->origin)
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)

struct vtm; /* defined by timev.h */

/* array.c */
VALUE rb_ary_last(int, VALUE *, VALUE);
void rb_ary_set_len(VALUE, long);
VALUE rb_ary_cat(VALUE, const VALUE *, long);
void rb_ary_delete_same(VALUE, VALUE);

/* bignum.c */
VALUE rb_big_fdiv(VALUE x, VALUE y);
VALUE rb_big_uminus(VALUE x);
VALUE rb_integer_float_cmp(VALUE x, VALUE y);
VALUE rb_integer_float_eq(VALUE x, VALUE y);

/* class.c */
VALUE rb_obj_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, VALUE *argv, VALUE obj);
int rb_obj_basic_to_s_p(VALUE);
VALUE rb_special_singleton_class(VALUE);
VALUE rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach);
void Init_class_hierarchy(void);

/* compar.c */
VALUE rb_invcmp(VALUE, VALUE);

/* compile.c */
int rb_dvar_defined(ID);
int rb_local_defined(ID);
int rb_parse_in_eval(void);
int rb_parse_in_main(void);
const char * rb_insns_name(int i);
VALUE rb_insns_name_array(void);

/* cont.c */
VALUE rb_obj_is_fiber(VALUE);
void rb_fiber_reset_root_local_storage(VALUE);

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
const char *rb_builtin_type_name(int t);
const char *rb_builtin_class_name(VALUE x);

/* eval.c */
VALUE rb_refinement_module_get_refined_class(VALUE module);

/* eval_error.c */
void ruby_error_print(void);
VALUE rb_get_backtrace(VALUE info);

/* eval_jump.c */
void rb_call_end_proc(VALUE data);
void rb_mark_end_proc(void);

/* file.c */
VALUE rb_home_dir(const char *user, VALUE result);
VALUE rb_realpath_internal(VALUE basedir, VALUE path, int strict);
void rb_file_const(const char*, VALUE);
int rb_file_load_ok(const char *);
VALUE rb_file_expand_path_fast(VALUE, VALUE);
VALUE rb_file_expand_path_internal(VALUE, VALUE, int, int, VALUE);
VALUE rb_get_path_check_to_string(VALUE, int);
VALUE rb_get_path_check_convert(VALUE, VALUE, int);
void Init_File(void);

#ifdef _WIN32
/* file.c, win32/file.c */
void rb_w32_init_file(void);
#endif

/* gc.c */
void Init_heap(void);
void *ruby_mimmalloc(size_t size);

/* inits.c */
void rb_call_inits(void);

/* io.c */
const char *ruby_get_inplace_mode(void);
void ruby_set_inplace_mode(const char *);
ssize_t rb_io_bufread(VALUE io, void *buf, size_t size);
void rb_stdio_set_default_encoding(void);
void rb_write_error_str(VALUE mesg);

/* iseq.c */
VALUE rb_iseq_clone(VALUE iseqval, VALUE newcbase);

/* load.c */
VALUE rb_get_load_path(void);
VALUE rb_get_expanded_load_path(void);
NORETURN(void rb_load_fail(VALUE, const char*));

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
VALUE num_interval_step_size(VALUE from, VALUE to, VALUE step, int excl);
int ruby_float_step(VALUE from, VALUE to, VALUE step, int excl);
double ruby_float_mod(double x, double y);

/* object.c */
VALUE rb_obj_equal(VALUE obj1, VALUE obj2);

/* parse.y */
VALUE rb_parser_get_yydebug(VALUE);
VALUE rb_parser_set_yydebug(VALUE, VALUE);
int rb_is_const_name(VALUE name);
int rb_is_class_name(VALUE name);
int rb_is_global_name(VALUE name);
int rb_is_instance_name(VALUE name);
int rb_is_attrset_name(VALUE name);
int rb_is_local_name(VALUE name);
int rb_is_method_name(VALUE name);
int rb_is_junk_name(VALUE name);
void rb_gc_mark_parser(void);
void rb_gc_mark_symbols(void);

/* proc.c */
VALUE rb_proc_location(VALUE self);
st_index_t rb_hash_proc(st_index_t hash, VALUE proc);

/* process.c */

struct rb_execarg {
    int use_shell;
    union {
        struct {
            VALUE shell_script;
        } sh;
        struct {
            VALUE command_name;
            VALUE command_abspath; /* full path string or nil */
            VALUE argv_str;
            VALUE argv_buf;
        } cmd;
    } invoke;
    VALUE redirect_fds;
    VALUE envp_str;
    VALUE envp_buf;
    VALUE dup2_tmpbuf;
    unsigned pgroup_given : 1;
    unsigned umask_given : 1;
    unsigned unsetenv_others_given : 1;
    unsigned unsetenv_others_do : 1;
    unsigned close_others_given : 1;
    unsigned close_others_do : 1;
    unsigned chdir_given : 1;
    unsigned new_pgroup_given : 1;
    unsigned new_pgroup_flag : 1;
    unsigned uid_given : 1;
    unsigned gid_given : 1;
    rb_pid_t pgroup_pgid; /* asis(-1), new pgroup(0), specified pgroup (0<V). */
    VALUE rlimit_limits; /* Qfalse or [[rtype, softlim, hardlim], ...] */
    mode_t umask_mask;
    rb_uid_t uid;
    rb_gid_t gid;
    VALUE fd_dup2;
    VALUE fd_close;
    VALUE fd_open;
    VALUE fd_dup2_child;
    int close_others_maxhint;
    VALUE env_modification; /* Qfalse or [[k1,v1], ...] */
    VALUE chdir_dir;
};

/* argv_str contains extra two elements.
 * The beginning one is for /bin/sh used by exec_with_sh.
 * The last one for terminating NULL used by execve.
 * See rb_exec_fillarg() in process.c. */
#define ARGVSTR2ARGC(argv_str) (RSTRING_LEN(argv_str) / sizeof(char *) - 2)
#define ARGVSTR2ARGV(argv_str) ((char **)RSTRING_PTR(argv_str) + 1)

rb_pid_t rb_fork_ruby(int *status);
void rb_last_status_clear(void);

/* rational.c */
VALUE rb_lcm(VALUE x, VALUE y);
VALUE rb_rational_reciprocal(VALUE x);

/* re.c */
VALUE rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline);
VALUE rb_reg_check_preprocess(VALUE);

/* signal.c */
int rb_get_next_signal(void);
int rb_sigaltstack_size(void);

/* strftime.c */
#ifdef RUBY_ENCODING_H
size_t rb_strftime_timespec(char *s, size_t maxsize, const char *format, rb_encoding *enc,
	const struct vtm *vtm, struct timespec *ts, int gmt);
size_t rb_strftime(char *s, size_t maxsize, const char *format, rb_encoding *enc,
            const struct vtm *vtm, VALUE timev, int gmt);
#endif

/* string.c */
int rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p);
int rb_str_symname_p(VALUE);
VALUE rb_str_quote_unprintable(VALUE);
VALUE rb_id_quote_unprintable(ID);
#define QUOTE(str) rb_str_quote_unprintable(str)
#define QUOTE_ID(id) rb_id_quote_unprintable(id)

/* struct.c */
VALUE rb_struct_init_copy(VALUE copy, VALUE s);

/* time.c */
struct timeval rb_time_timeval(VALUE);

/* thread.c */
VALUE rb_obj_is_mutex(VALUE obj);
VALUE rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg);
void rb_thread_execute_interrupts(VALUE th);
void rb_clear_trace_func(void);
VALUE rb_get_coverages(void);
VALUE rb_thread_shield_new(void);
VALUE rb_thread_shield_wait(VALUE self);
VALUE rb_thread_shield_release(VALUE self);
VALUE rb_thread_shield_destroy(VALUE self);
void rb_mutex_allow_trap(VALUE self, int val);
VALUE rb_uninterruptible(VALUE (*b_proc)(ANYARGS), VALUE data);
VALUE rb_mutex_owned_p(VALUE self);

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
VALUE rb_sourcefilename(void);

/* vm_dump.c */
void rb_vm_bugreport(void);

/* vm_eval.c */
void Init_vm_eval(void);
VALUE rb_current_realfilepath(void);
VALUE rb_check_block_call(VALUE, ID, int, VALUE *, VALUE (*)(ANYARGS), VALUE);
typedef void rb_check_funcall_hook(int, VALUE, ID, int, VALUE *, VALUE);
VALUE rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, VALUE *argv,
				 rb_check_funcall_hook *hook, VALUE arg);

/* vm_method.c */
void Init_eval_method(void);
int rb_method_defined_by(VALUE obj, ID mid, VALUE (*cfunc)(ANYARGS));

/* miniprelude.c, prelude.c */
void Init_prelude(void);

/* vm_backtrace.c */
void Init_vm_backtrace(void);
VALUE vm_thread_backtrace(int argc, VALUE *argv, VALUE thval);
VALUE vm_thread_backtrace_locations(int argc, VALUE *argv, VALUE thval);

VALUE rb_make_backtrace(void);
void rb_backtrace_print_as_bugreport(void);
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE obj);
VALUE rb_vm_backtrace_object();

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility push(default)
#endif
const char *rb_objspace_data_type_name(VALUE obj);

/* Temporary.  This API will be removed (renamed). */
VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);

/* io.c */
void rb_maygvl_fd_fix_cloexec(int fd);

/* process.c */
int rb_exec_async_signal_safe(const struct rb_execarg *e, char *errmsg, size_t errmsg_buflen);
rb_pid_t rb_fork_async_signal_safe(int *status, int (*chfunc)(void*, char *, size_t), void *charg, VALUE fds, char *errmsg, size_t errmsg_buflen);
VALUE rb_execarg_new(int argc, VALUE *argv, int accept_shell);
struct rb_execarg *rb_execarg_get(VALUE execarg_obj); /* dangerous.  needs GC guard. */
VALUE rb_execarg_init(int argc, VALUE *argv, int accept_shell, VALUE execarg_obj);
int rb_execarg_addopt(VALUE execarg_obj, VALUE key, VALUE val);
void rb_execarg_fixup(VALUE execarg_obj);
int rb_execarg_run_options(const struct rb_execarg *e, struct rb_execarg *s, char* errmsg, size_t errmsg_buflen);
VALUE rb_execarg_extract_options(VALUE execarg_obj, VALUE opthash);
void rb_execarg_setenv(VALUE execarg_obj, VALUE env);

/* variable.c */
void rb_gc_mark_global_tbl(void);
void rb_mark_generic_ivar(VALUE);
void rb_mark_generic_ivar_tbl(void);

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
