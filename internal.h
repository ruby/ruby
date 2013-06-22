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

#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))

#define GCC_VERSION_SINCE(major, minor, patchlevel) \
  (defined(__GNUC__) && !defined(__INTEL_COMPILER) && \
   ((__GNUC__ > (major)) ||  \
    (__GNUC__ == (major) && __GNUC_MINOR__ > (minor)) || \
    (__GNUC__ == (major) && __GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ >= (patchlevel))))

#define SIGNED_INTEGER_TYPE_P(int_type) (0 > ((int_type)0)-1)
#define SIGNED_INTEGER_MAX(sint_type) \
  ((((sint_type)1) << (sizeof(sint_type) * CHAR_BIT - 2)) | \
  ((((sint_type)1) << (sizeof(sint_type) * CHAR_BIT - 2)) - 1))
#define SIGNED_INTEGER_MIN(sint_type) (-SIGNED_INTEGER_MAX(sint_type)-1)
#define UNSIGNED_INTEGER_MAX(uint_type) (~(uint_type)0)

#if SIGNEDNESS_OF_TIME_T < 0	/* signed */
# define TIMET_MAX SIGNED_INTEGER_MAX(time_t)
# define TIMET_MIN SIGNED_INTEGER_MIN(time_t)
#elif SIGNEDNESS_OF_TIME_T > 0	/* unsigned */
# define TIMET_MAX UNSIGNED_INTEGER_MAX(time_t)
# define TIMET_MIN ((time_t)0)
#endif
#define TIMET_MAX_PLUS_ONE (2*(double)(TIMET_MAX/2+1))

#define MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, min, max) ( \
    (a) == 0 ? 0 : \
    (a) == -1 ? (b) < -(max) : \
    (a) > 0 ? \
      ((b) > 0 ? (max) / (a) < (b) : (min) / (a) > (b)) : \
      ((b) > 0 ? (min) / (a) < (b) : (max) / (a) > (b)))
#define MUL_OVERFLOW_FIXNUM_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, FIXNUM_MIN, FIXNUM_MAX)
#define MUL_OVERFLOW_LONG_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, LONG_MIN, LONG_MAX)
#define MUL_OVERFLOW_INT_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, INT_MIN, INT_MAX)

/* "MS" in MSWORD and MSBYTE means "most significant" */
/* "LS" in LSWORD and LSBYTE means "least significant" */
/* For rb_integer_pack and rb_integer_unpack: */
#define INTEGER_PACK_MSWORD_FIRST       0x01
#define INTEGER_PACK_LSWORD_FIRST       0x02
#define INTEGER_PACK_MSBYTE_FIRST       0x10
#define INTEGER_PACK_LSBYTE_FIRST       0x20
#define INTEGER_PACK_NATIVE_BYTE_ORDER  0x40
#define INTEGER_PACK_2COMP              0x80
#define INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION     0x400
/* For rb_integer_unpack: */
#define INTEGER_PACK_FORCE_BIGNUM       0x100
#define INTEGER_PACK_NEGATIVE           0x200
/* Combinations: */
#define INTEGER_PACK_LITTLE_ENDIAN \
    (INTEGER_PACK_LSWORD_FIRST | \
     INTEGER_PACK_LSBYTE_FIRST)
#define INTEGER_PACK_BIG_ENDIAN \
    (INTEGER_PACK_MSWORD_FIRST | \
     INTEGER_PACK_MSBYTE_FIRST)

#ifndef swap16
# define swap16(x)      ((uint16_t)((((x)&0xFF)<<8) | (((x)>>8)&0xFF)))
#endif

#ifndef swap32
# if GCC_VERSION_SINCE(4,3,0)
#  define swap32(x) __builtin_bswap32(x)
# endif
#endif

#ifndef swap32
# define swap32(x)      ((uint32_t)((((x)&0xFF)<<24)    \
                        |(((x)>>24)&0xFF)       \
                        |(((x)&0x0000FF00)<<8)  \
                        |(((x)&0x00FF0000)>>8)  ))
#endif

#ifndef swap64
# if GCC_VERSION_SINCE(4,3,0)
#  define swap64(x) __builtin_bswap64(x)
# endif
#endif

#ifndef swap64
# ifdef HAVE_INT64_T
#  define byte_in_64bit(n) ((uint64_t)0xff << (n))
#  define swap64(x)       ((uint64_t)((((x)&byte_in_64bit(0))<<56)      \
                           |(((x)>>56)&0xFF)                    \
                           |(((x)&byte_in_64bit(8))<<40)        \
                           |(((x)&byte_in_64bit(48))>>40)       \
                           |(((x)&byte_in_64bit(16))<<24)       \
                           |(((x)&byte_in_64bit(40))>>24)       \
                           |(((x)&byte_in_64bit(24))<<8)        \
                           |(((x)&byte_in_64bit(32))>>8)))
# endif
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

#define RCLASS_EXT(c) (RCLASS(c)->ptr)
#define RCLASS_IV_TBL(c) (RCLASS_EXT(c)->iv_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#define RCLASS_M_TBL(c) (RCLASS(c)->m_tbl)
#define RCLASS_IV_INDEX_TBL(c) (RCLASS(c)->iv_index_tbl)
#define RCLASS_ORIGIN(c) (RCLASS_EXT(c)->origin)
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)

#undef RCLASS_SUPER
static inline VALUE
RCLASS_SUPER(VALUE klass)
{
    return RCLASS_EXT(klass)->super;
}

static inline VALUE
RCLASS_SET_SUPER(VALUE klass, VALUE super)
{
    OBJ_WRITE(klass, &RCLASS_EXT(klass)->super, super);
    return super;
}

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
size_t rb_absint_size(VALUE val, int *nlz_bits_ret);
size_t rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret);
int rb_absint_singlebit_p(VALUE val);

/* class.c */
VALUE rb_obj_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, VALUE *argv, VALUE obj);
int rb_obj_basic_to_s_p(VALUE);
VALUE rb_special_singleton_class(VALUE);
VALUE rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach);
VALUE rb_singleton_class_get(VALUE obj);
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

#ifdef RUBY_FUNCTION_NAME_STRING
# if defined __GNUC__ && __GNUC__ >= 4
#   pragma GCC visibility push(default)
# endif
NORETURN(void rb_sys_fail_path_in(const char *func_name, VALUE path));
# if defined __GNUC__ && __GNUC__ >= 4
#   pragma GCC visibility pop
# endif
# define rb_sys_fail_path(path) rb_sys_fail_path_in(RUBY_FUNCTION_NAME_STRING, path)
#else
# define rb_sys_fail_path(path) rb_sys_fail_str(path)
#endif

#ifdef _WIN32
/* file.c, win32/file.c */
void rb_w32_init_file(void);
#endif

/* gc.c */
void Init_heap(void);
void *ruby_mimmalloc(size_t size);
void rb_objspace_set_event_hook(const rb_event_flag_t event);

/* hash.c */
struct st_table *rb_hash_tbl_raw(VALUE hash);
#define RHASH_TBL_RAW(h) rb_hash_tbl_raw(h)

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
VALUE ruby_num_interval_step_size(VALUE from, VALUE to, VALUE step, int excl);
int ruby_float_step(VALUE from, VALUE to, VALUE step, int excl);
double ruby_float_mod(double x, double y);
int rb_num_negative_p(VALUE);
VALUE rb_int_succ(VALUE num);
VALUE rb_int_pred(VALUE num);

/* object.c */
VALUE rb_obj_equal(VALUE obj1, VALUE obj2);

struct RBasicRaw {
    VALUE flags;
    VALUE klass;
};

#define RBASIC_CLEAR_CLASS(obj)        (((struct RBasicRaw *)((VALUE)(obj)))->klass = 0)
#define RBASIC_SET_CLASS_RAW(obj, cls) (((struct RBasicRaw *)((VALUE)(obj)))->klass = (cls))
#define RBASIC_SET_CLASS(obj, cls)     do { \
    VALUE _obj_ = (obj); \
    OBJ_WRITE(_obj_, &((struct RBasicRaw *)(_obj_))->klass, cls); \
} while (0)

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
#define RB_MAX_GROUPS (65536)

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
void ruby_kill(rb_pid_t pid, int sig);

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
void rb_print_backtrace(void);

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
VALUE rb_vm_thread_backtrace(int argc, VALUE *argv, VALUE thval);
VALUE rb_vm_thread_backtrace_locations(int argc, VALUE *argv, VALUE thval);

VALUE rb_make_backtrace(void);
void rb_backtrace_print_as_bugreport(void);
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE obj);
VALUE rb_vm_backtrace_object();

RUBY_SYMBOL_EXPORT_BEGIN
const char *rb_objspace_data_type_name(VALUE obj);

/* Temporary.  This API will be removed (renamed). */
VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);

/* bignum.c */
int rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
VALUE rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags);

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

int rb_st_insert_id_and_value(VALUE obj, st_table *tbl, ID key, VALUE value);
st_table *rb_st_copy(VALUE obj, struct st_table *orig_tbl);

/* gc.c */
size_t rb_gc_count();

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_INTERNAL_H */
