/**********************************************************************

  intern.h -

  $Author$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifndef RUBY_INTERN_H
#define RUBY_INTERN_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#if !defined(__has_attribute)
#define __has_attribute(x) 0
#endif

#include "ruby/defines.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
#else
# include <varargs.h>
#endif

#include "ruby/st.h"

/* On mswin, MJIT header transformation can't be used since cl.exe can't output
   preprocessed output preserving macros. So this `MJIT_STATIC` is needed
   to force non-static function to static on MJIT header to avoid symbol conflict. */
#ifdef MJIT_HEADER
# define MJIT_STATIC static
#else
# define MJIT_STATIC
#endif

RUBY_SYMBOL_EXPORT_BEGIN

/*
 * Functions and variables that are used by more than one source file of
 * the kernel.
 */

#define UNLIMITED_ARGUMENTS (-1)

/* array.c */
void rb_mem_clear(VALUE*, long);
VALUE rb_assoc_new(VALUE, VALUE);
VALUE rb_check_array_type(VALUE);
VALUE rb_ary_new(void);
VALUE rb_ary_new_capa(long capa);
VALUE rb_ary_new_from_args(long n, ...);
VALUE rb_ary_new_from_values(long n, const VALUE *elts);
VALUE rb_ary_tmp_new(long);
void rb_ary_free(VALUE);
void rb_ary_modify(VALUE);
VALUE rb_ary_freeze(VALUE);
VALUE rb_ary_shared_with_p(VALUE, VALUE);
VALUE rb_ary_aref(int, const VALUE*, VALUE);
VALUE rb_ary_subseq(VALUE, long, long);
void rb_ary_store(VALUE, long, VALUE);
VALUE rb_ary_dup(VALUE);
VALUE rb_ary_resurrect(VALUE ary);
VALUE rb_ary_to_ary(VALUE);
VALUE rb_ary_to_s(VALUE);
VALUE rb_ary_cat(VALUE, const VALUE *, long);
VALUE rb_ary_push(VALUE, VALUE);
VALUE rb_ary_pop(VALUE);
VALUE rb_ary_shift(VALUE);
VALUE rb_ary_unshift(VALUE, VALUE);
VALUE rb_ary_entry(VALUE, long);
VALUE rb_ary_each(VALUE);
VALUE rb_ary_join(VALUE, VALUE);
VALUE rb_ary_reverse(VALUE);
VALUE rb_ary_rotate(VALUE, long);
VALUE rb_ary_sort(VALUE);
VALUE rb_ary_sort_bang(VALUE);
VALUE rb_ary_delete(VALUE, VALUE);
VALUE rb_ary_delete_at(VALUE, long);
VALUE rb_ary_clear(VALUE);
VALUE rb_ary_plus(VALUE, VALUE);
VALUE rb_ary_concat(VALUE, VALUE);
VALUE rb_ary_assoc(VALUE, VALUE);
VALUE rb_ary_rassoc(VALUE, VALUE);
VALUE rb_ary_includes(VALUE, VALUE);
VALUE rb_ary_cmp(VALUE, VALUE);
VALUE rb_ary_replace(VALUE copy, VALUE orig);
VALUE rb_get_values_at(VALUE, long, int, const VALUE*, VALUE(*)(VALUE,long));
VALUE rb_ary_resize(VALUE ary, long len);
#define rb_ary_new2 rb_ary_new_capa
#define rb_ary_new3 rb_ary_new_from_args
#define rb_ary_new4 rb_ary_new_from_values
/* bignum.c */
VALUE rb_big_new(size_t, int);
int rb_bigzero_p(VALUE x);
VALUE rb_big_clone(VALUE);
void rb_big_2comp(VALUE);
VALUE rb_big_norm(VALUE);
void rb_big_resize(VALUE big, size_t len);
VALUE rb_cstr_to_inum(const char*, int, int);
VALUE rb_str_to_inum(VALUE, int, int);
VALUE rb_cstr2inum(const char*, int);
VALUE rb_str2inum(VALUE, int);
VALUE rb_big2str(VALUE, int);
long rb_big2long(VALUE);
#define rb_big2int(x) rb_big2long(x)
unsigned long rb_big2ulong(VALUE);
#define rb_big2uint(x) rb_big2ulong(x)
#if HAVE_LONG_LONG
LONG_LONG rb_big2ll(VALUE);
unsigned LONG_LONG rb_big2ull(VALUE);
#endif  /* HAVE_LONG_LONG */
void rb_big_pack(VALUE val, unsigned long *buf, long num_longs);
VALUE rb_big_unpack(unsigned long *buf, long num_longs);
int rb_uv_to_utf8(char[6],unsigned long);
VALUE rb_dbl2big(double);
double rb_big2dbl(VALUE);
VALUE rb_big_cmp(VALUE, VALUE);
VALUE rb_big_eq(VALUE, VALUE);
VALUE rb_big_eql(VALUE, VALUE);
VALUE rb_big_plus(VALUE, VALUE);
VALUE rb_big_minus(VALUE, VALUE);
VALUE rb_big_mul(VALUE, VALUE);
VALUE rb_big_div(VALUE, VALUE);
VALUE rb_big_idiv(VALUE, VALUE);
VALUE rb_big_modulo(VALUE, VALUE);
VALUE rb_big_divmod(VALUE, VALUE);
VALUE rb_big_pow(VALUE, VALUE);
VALUE rb_big_and(VALUE, VALUE);
VALUE rb_big_or(VALUE, VALUE);
VALUE rb_big_xor(VALUE, VALUE);
VALUE rb_big_lshift(VALUE, VALUE);
VALUE rb_big_rshift(VALUE, VALUE);

/* For rb_integer_pack and rb_integer_unpack: */
/* "MS" in MSWORD and MSBYTE means "most significant" */
/* "LS" in LSWORD and LSBYTE means "least significant" */
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
int rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
VALUE rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
size_t rb_absint_size(VALUE val, int *nlz_bits_ret);
size_t rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret);
int rb_absint_singlebit_p(VALUE val);

/* rational.c */
VALUE rb_rational_raw(VALUE, VALUE);
#define rb_rational_raw1(x) rb_rational_raw((x), INT2FIX(1))
#define rb_rational_raw2(x,y) rb_rational_raw((x), (y))
VALUE rb_rational_new(VALUE, VALUE);
#define rb_rational_new1(x) rb_rational_new((x), INT2FIX(1))
#define rb_rational_new2(x,y) rb_rational_new((x), (y))
VALUE rb_Rational(VALUE, VALUE);
#define rb_Rational1(x) rb_Rational((x), INT2FIX(1))
#define rb_Rational2(x,y) rb_Rational((x), (y))
VALUE rb_rational_num(VALUE rat);
VALUE rb_rational_den(VALUE rat);
VALUE rb_flt_rationalize_with_prec(VALUE, VALUE);
VALUE rb_flt_rationalize(VALUE);
/* complex.c */
VALUE rb_complex_raw(VALUE, VALUE);
#define rb_complex_raw1(x) rb_complex_raw((x), INT2FIX(0))
#define rb_complex_raw2(x,y) rb_complex_raw((x), (y))
VALUE rb_complex_new(VALUE, VALUE);
#define rb_complex_new1(x) rb_complex_new((x), INT2FIX(0))
#define rb_complex_new2(x,y) rb_complex_new((x), (y))
VALUE rb_complex_new_polar(VALUE abs, VALUE arg);
DEPRECATED_BY(rb_complex_new_polar, VALUE rb_complex_polar(VALUE abs, VALUE arg));
VALUE rb_complex_real(VALUE z);
VALUE rb_complex_imag(VALUE z);
VALUE rb_complex_plus(VALUE x, VALUE y);
VALUE rb_complex_minus(VALUE x, VALUE y);
VALUE rb_complex_mul(VALUE x, VALUE y);
VALUE rb_complex_div(VALUE x, VALUE y);
VALUE rb_complex_uminus(VALUE z);
VALUE rb_complex_conjugate(VALUE z);
VALUE rb_complex_abs(VALUE z);
VALUE rb_complex_arg(VALUE z);
VALUE rb_complex_pow(VALUE base, VALUE exp);
VALUE rb_dbl_complex_new(double real, double imag);
#define rb_complex_add rb_complex_plus
#define rb_complex_sub rb_complex_minus
#define rb_complex_nagate rb_complex_uminus

VALUE rb_Complex(VALUE, VALUE);
#define rb_Complex1(x) rb_Complex((x), INT2FIX(0))
#define rb_Complex2(x,y) rb_Complex((x), (y))
/* class.c */
VALUE rb_class_new(VALUE);
VALUE rb_mod_init_copy(VALUE, VALUE);
VALUE rb_singleton_class_clone(VALUE);
void rb_singleton_class_attached(VALUE,VALUE);
void rb_check_inheritable(VALUE);
VALUE rb_define_class_id(ID, VALUE);
VALUE rb_define_class_id_under(VALUE, ID, VALUE);
VALUE rb_module_new(void);
VALUE rb_define_module_id(ID);
VALUE rb_define_module_id_under(VALUE, ID);
VALUE rb_mod_included_modules(VALUE);
VALUE rb_mod_include_p(VALUE, VALUE);
VALUE rb_mod_ancestors(VALUE);
VALUE rb_class_instance_methods(int, const VALUE*, VALUE);
VALUE rb_class_public_instance_methods(int, const VALUE*, VALUE);
VALUE rb_class_protected_instance_methods(int, const VALUE*, VALUE);
VALUE rb_class_private_instance_methods(int, const VALUE*, VALUE);
VALUE rb_obj_singleton_methods(int, const VALUE*, VALUE);
void rb_define_method_id(VALUE, ID, VALUE (*)(ANYARGS), int);
void rb_undef(VALUE, ID);
void rb_define_protected_method(VALUE, const char*, VALUE (*)(ANYARGS), int);
void rb_define_private_method(VALUE, const char*, VALUE (*)(ANYARGS), int);
void rb_define_singleton_method(VALUE, const char*, VALUE(*)(ANYARGS), int);
VALUE rb_singleton_class(VALUE);
/* compar.c */
int rb_cmpint(VALUE, VALUE, VALUE);
NORETURN(void rb_cmperr(VALUE, VALUE));
/* cont.c */
VALUE rb_fiber_new(rb_block_call_func_t, VALUE);
VALUE rb_fiber_resume(VALUE fib, int argc, const VALUE *argv);
VALUE rb_fiber_resume_kw(VALUE fib, int argc, const VALUE *argv, int kw_splat);
VALUE rb_fiber_yield(int argc, const VALUE *argv);
VALUE rb_fiber_yield_kw(int argc, const VALUE *argv, int kw_splat);
VALUE rb_fiber_current(void);
VALUE rb_fiber_alive_p(VALUE);
/* enum.c */
VALUE rb_enum_values_pack(int, const VALUE*);
/* enumerator.c */
VALUE rb_enumeratorize(VALUE, VALUE, int, const VALUE *);
typedef VALUE rb_enumerator_size_func(VALUE, VALUE, VALUE);
VALUE rb_enumeratorize_with_size(VALUE, VALUE, int, const VALUE *, rb_enumerator_size_func *);
VALUE rb_enumeratorize_with_size_kw(VALUE, VALUE, int, const VALUE *, rb_enumerator_size_func *, int);
#ifndef RUBY_EXPORT
#define rb_enumeratorize_with_size(obj, id, argc, argv, size_fn) \
    rb_enumeratorize_with_size(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn))
#define rb_enumeratorize_with_size_kw(obj, id, argc, argv, size_fn, kw_splat) \
    rb_enumeratorize_with_size_kw(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn), kw_splat)
#endif
#define SIZED_ENUMERATOR(obj, argc, argv, size_fn) \
    rb_enumeratorize_with_size((obj), ID2SYM(rb_frame_this_func()), \
			       (argc), (argv), (size_fn))
#define SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat) \
    rb_enumeratorize_with_size_kw((obj), ID2SYM(rb_frame_this_func()), \
                                  (argc), (argv), (size_fn), (kw_splat))
#define RETURN_SIZED_ENUMERATOR(obj, argc, argv, size_fn) do {		\
	if (!rb_block_given_p())					\
	    return SIZED_ENUMERATOR(obj, argc, argv, size_fn);		\
    } while (0)
#define RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat) do { \
        if (!rb_block_given_p())                                            \
            return SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat);              \
    } while (0)
#define RETURN_ENUMERATOR(obj, argc, argv) RETURN_SIZED_ENUMERATOR(obj, argc, argv, 0)
#define RETURN_ENUMERATOR_KW(obj, argc, argv, kw_splat) RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, 0, kw_splat)
typedef struct {
    VALUE begin;
    VALUE end;
    VALUE step;
    int exclude_end;
} rb_arithmetic_sequence_components_t;
int rb_arithmetic_sequence_extract(VALUE, rb_arithmetic_sequence_components_t *);
/* error.c */
VALUE rb_exc_new(VALUE, const char*, long);
VALUE rb_exc_new_cstr(VALUE, const char*);
VALUE rb_exc_new_str(VALUE, VALUE);
#define rb_exc_new2 rb_exc_new_cstr
#define rb_exc_new3 rb_exc_new_str
PRINTF_ARGS(NORETURN(void rb_loaderror(const char*, ...)), 1, 2);
PRINTF_ARGS(NORETURN(void rb_loaderror_with_path(VALUE path, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_name_error(ID, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_name_error_str(VALUE, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_frozen_error_raise(VALUE, const char*, ...)), 2, 3);
NORETURN(void rb_invalid_str(const char*, const char*));
NORETURN(void rb_error_frozen(const char*));
NORETURN(void rb_error_frozen_object(VALUE));
void rb_error_untrusted(VALUE);
void rb_check_frozen(VALUE);
void rb_check_trusted(VALUE);
#define rb_check_frozen_internal(obj) do { \
	VALUE frozen_obj = (obj); \
	if (RB_UNLIKELY(RB_OBJ_FROZEN(frozen_obj))) { \
	    rb_error_frozen_object(frozen_obj); \
	} \
    } while (0)
#ifdef __GNUC__
#define rb_check_frozen(obj) __extension__({rb_check_frozen_internal(obj);})
#else
static inline void
rb_check_frozen_inline(VALUE obj)
{
    rb_check_frozen_internal(obj);
}
#define rb_check_frozen(obj) rb_check_frozen_inline(obj)
static inline void
rb_check_trusted_inline(VALUE obj)
{
    rb_check_trusted(obj);
}
#define rb_check_trusted(obj) rb_check_trusted_inline(obj)
#endif
void rb_check_copyable(VALUE obj, VALUE orig);

#define RB_OBJ_INIT_COPY(obj, orig) \
    ((obj) != (orig) && (rb_obj_init_copy((obj), (orig)), 1))
#define OBJ_INIT_COPY(obj, orig) RB_OBJ_INIT_COPY(obj, orig)

/* eval.c */
int rb_sourceline(void);
const char *rb_sourcefile(void);
VALUE rb_check_funcall(VALUE, ID, int, const VALUE*);
VALUE rb_check_funcall_kw(VALUE, ID, int, const VALUE*, int);

NORETURN(MJIT_STATIC void rb_error_arity(int, int, int));
static inline int
rb_check_arity(int argc, int min, int max)
{
    if ((argc < min) || (max != UNLIMITED_ARGUMENTS && argc > max))
	rb_error_arity(argc, min, max);
    return argc;
}
#define rb_check_arity rb_check_arity /* for ifdef */

#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)
typedef struct {
    int maxfd;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
void rb_fd_zero(rb_fdset_t *);
void rb_fd_set(int, rb_fdset_t *);
void rb_fd_clr(int, rb_fdset_t *);
int rb_fd_isset(int, const rb_fdset_t *);
void rb_fd_copy(rb_fdset_t *, const fd_set *, int);
void rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);

struct timeval;
int rb_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);

#define rb_fd_ptr(f)	((f)->fdset)
#define rb_fd_max(f)	((f)->maxfd)

#elif defined(_WIN32)

typedef struct {
    int capa;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
#define rb_fd_zero(f)		((f)->fdset->fd_count = 0)
void rb_fd_set(int, rb_fdset_t *);
#define rb_fd_clr(n, f)		rb_w32_fdclr((n), (f)->fdset)
#define rb_fd_isset(n, f)	rb_w32_fdisset((n), (f)->fdset)
#define rb_fd_copy(d, s, n)	rb_w32_fd_copy((d), (s), (n))
void rb_w32_fd_copy(rb_fdset_t *, const fd_set *, int);
#define rb_fd_dup(d, s)	rb_w32_fd_dup((d), (s))
void rb_w32_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);
static inline int
rb_fd_select(int n, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout)
{
    return rb_w32_select(n,
                         rfds ? rfds->fdset : NULL,
                         wfds ? wfds->fdset : NULL,
                         efds ? efds->fdset : NULL,
                         timeout);
}
#define rb_fd_resize(n, f)	((void)(f))

#define rb_fd_ptr(f)	((f)->fdset)
#define rb_fd_max(f)	((f)->fdset->fd_count)

#else

typedef fd_set rb_fdset_t;
#define rb_fd_zero(f)	FD_ZERO(f)
#define rb_fd_set(n, f)	FD_SET((n), (f))
#define rb_fd_clr(n, f)	FD_CLR((n), (f))
#define rb_fd_isset(n, f) FD_ISSET((n), (f))
#define rb_fd_copy(d, s, n) (*(d) = *(s))
#define rb_fd_dup(d, s) (*(d) = *(s))
#define rb_fd_resize(n, f)	((void)(f))
#define rb_fd_ptr(f)	(f)
#define rb_fd_init(f)	FD_ZERO(f)
#define rb_fd_init_copy(d, s) (*(d) = *(s))
#define rb_fd_term(f)	((void)(f))
#define rb_fd_max(f)	FD_SETSIZE
#define rb_fd_select(n, rfds, wfds, efds, timeout)	select((n), (rfds), (wfds), (efds), (timeout))

#endif

NORETURN(void rb_exc_raise(VALUE));
NORETURN(void rb_exc_fatal(VALUE));
NORETURN(VALUE rb_f_exit(int, const VALUE*));
NORETURN(VALUE rb_f_abort(int, const VALUE*));
void rb_remove_method(VALUE, const char*);
void rb_remove_method_id(VALUE, ID);
#define HAVE_RB_DEFINE_ALLOC_FUNC 1
typedef VALUE (*rb_alloc_func_t)(VALUE);
void rb_define_alloc_func(VALUE, rb_alloc_func_t);
void rb_undef_alloc_func(VALUE);
rb_alloc_func_t rb_get_alloc_func(VALUE);
void rb_clear_constant_cache(void);
void rb_clear_method_cache_by_class(VALUE);
void rb_alias(VALUE, ID, ID);
void rb_attr(VALUE,ID,int,int,int);
int rb_method_boundp(VALUE, ID, int);
int rb_method_basic_definition_p(VALUE, ID);
VALUE rb_eval_cmd(VALUE, VALUE, int);
VALUE rb_eval_cmd_kw(VALUE, VALUE, int);
int rb_obj_respond_to(VALUE, ID, int);
int rb_respond_to(VALUE, ID);
NORETURN(VALUE rb_f_notimplement(int argc, const VALUE *argv, VALUE obj, VALUE marker));
#if !defined(RUBY_EXPORT) && defined(_WIN32)
RUBY_EXTERN VALUE (*const rb_f_notimplement_)(int, const VALUE *, VALUE, VALUE marker);
#define rb_f_notimplement (*rb_f_notimplement_)
#endif
NORETURN(void rb_interrupt(void));
VALUE rb_apply(VALUE, ID, VALUE);
void rb_backtrace(void);
ID rb_frame_this_func(void);
VALUE rb_obj_instance_eval(int, const VALUE*, VALUE);
VALUE rb_obj_instance_exec(int, const VALUE*, VALUE);
VALUE rb_mod_module_eval(int, const VALUE*, VALUE);
VALUE rb_mod_module_exec(int, const VALUE*, VALUE);
void rb_load(VALUE, int);
void rb_load_protect(VALUE, int, int*);
NORETURN(void rb_jump_tag(int));
int rb_provided(const char*);
int rb_feature_provided(const char *, const char **);
void rb_provide(const char*);
VALUE rb_f_require(VALUE, VALUE);
VALUE rb_require_safe(VALUE, int); /* Remove in 3.0 */
VALUE rb_require_string(VALUE);
void rb_obj_call_init(VALUE, int, const VALUE*);
void rb_obj_call_init_kw(VALUE, int, const VALUE*, int);
VALUE rb_class_new_instance(int, const VALUE*, VALUE);
VALUE rb_class_new_instance_kw(int, const VALUE*, VALUE, int);
VALUE rb_block_proc(void);
VALUE rb_block_lambda(void);
VALUE rb_proc_new(rb_block_call_func_t, VALUE);
VALUE rb_obj_is_proc(VALUE);
VALUE rb_proc_call(VALUE, VALUE);
VALUE rb_proc_call_kw(VALUE, VALUE, int);
VALUE rb_proc_call_with_block(VALUE, int argc, const VALUE *argv, VALUE);
VALUE rb_proc_call_with_block_kw(VALUE, int argc, const VALUE *argv, VALUE, int);
int rb_proc_arity(VALUE);
VALUE rb_proc_lambda_p(VALUE);
VALUE rb_binding_new(void);
VALUE rb_obj_method(VALUE, VALUE);
VALUE rb_obj_is_method(VALUE);
VALUE rb_method_call(int, const VALUE*, VALUE);
VALUE rb_method_call_kw(int, const VALUE*, VALUE, int);
VALUE rb_method_call_with_block(int, const VALUE *, VALUE, VALUE);
VALUE rb_method_call_with_block_kw(int, const VALUE *, VALUE, VALUE, int);
int rb_mod_method_arity(VALUE, ID);
int rb_obj_method_arity(VALUE, ID);
VALUE rb_protect(VALUE (*)(VALUE), VALUE, int*);
void rb_set_end_proc(void (*)(VALUE), VALUE);
void rb_thread_schedule(void);
void rb_thread_wait_fd(int);
int rb_thread_fd_writable(int);
void rb_thread_fd_close(int);
int rb_thread_alone(void);
void rb_thread_sleep(int);
void rb_thread_sleep_forever(void);
void rb_thread_sleep_deadly(void);
VALUE rb_thread_stop(void);
VALUE rb_thread_wakeup(VALUE);
VALUE rb_thread_wakeup_alive(VALUE);
VALUE rb_thread_run(VALUE);
VALUE rb_thread_kill(VALUE);
VALUE rb_thread_create(VALUE (*)(void *), void*);
int rb_thread_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);
void rb_thread_wait_for(struct timeval);
VALUE rb_thread_current(void);
VALUE rb_thread_main(void);
VALUE rb_thread_local_aref(VALUE, ID);
VALUE rb_thread_local_aset(VALUE, ID, VALUE);
void rb_thread_atfork(void);
void rb_thread_atfork_before_exec(void);
VALUE rb_exec_recursive(VALUE(*)(VALUE, VALUE, int),VALUE,VALUE);
VALUE rb_exec_recursive_paired(VALUE(*)(VALUE, VALUE, int),VALUE,VALUE,VALUE);
VALUE rb_exec_recursive_outer(VALUE(*)(VALUE, VALUE, int),VALUE,VALUE);
VALUE rb_exec_recursive_paired_outer(VALUE(*)(VALUE, VALUE, int),VALUE,VALUE,VALUE);
/* dir.c */
VALUE rb_dir_getwd(void);
/* file.c */
VALUE rb_file_s_expand_path(int, const VALUE *);
VALUE rb_file_expand_path(VALUE, VALUE);
VALUE rb_file_s_absolute_path(int, const VALUE *);
VALUE rb_file_absolute_path(VALUE, VALUE);
VALUE rb_file_dirname(VALUE fname);
int rb_find_file_ext_safe(VALUE*, const char* const*, int); /* Remove in 3.0 */
VALUE rb_find_file_safe(VALUE, int); /* Remove in 3.0 */
int rb_find_file_ext(VALUE*, const char* const*);
VALUE rb_find_file(VALUE);
VALUE rb_file_directory_p(VALUE,VALUE);
VALUE rb_str_encode_ospath(VALUE);
int rb_is_absolute_path(const char *);
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
/* hash.c */
void rb_st_foreach_safe(struct st_table *, int (*)(st_data_t, st_data_t, st_data_t), st_data_t);
#define st_foreach_safe rb_st_foreach_safe
VALUE rb_check_hash_type(VALUE);
void rb_hash_foreach(VALUE, int (*)(VALUE, VALUE, VALUE), VALUE);
VALUE rb_hash(VALUE);
VALUE rb_hash_new(void);
VALUE rb_hash_dup(VALUE);
VALUE rb_hash_freeze(VALUE);
VALUE rb_hash_aref(VALUE, VALUE);
VALUE rb_hash_lookup(VALUE, VALUE);
VALUE rb_hash_lookup2(VALUE, VALUE, VALUE);
VALUE rb_hash_fetch(VALUE, VALUE);
VALUE rb_hash_aset(VALUE, VALUE, VALUE);
VALUE rb_hash_clear(VALUE);
VALUE rb_hash_delete_if(VALUE);
VALUE rb_hash_delete(VALUE,VALUE);
VALUE rb_hash_set_ifnone(VALUE hash, VALUE ifnone);
void rb_hash_bulk_insert(long, const VALUE *, VALUE);
typedef VALUE rb_hash_update_func(VALUE newkey, VALUE oldkey, VALUE value);
VALUE rb_hash_update_by(VALUE hash1, VALUE hash2, rb_hash_update_func *func);
struct st_table *rb_hash_tbl(VALUE, const char *file, int line);
int rb_path_check(const char*);
int rb_env_path_tainted(void);
VALUE rb_env_clear(void);
VALUE rb_hash_size(VALUE);
void rb_hash_free(VALUE);
/* io.c */
#define rb_defout rb_stdout
RUBY_EXTERN VALUE rb_fs;
RUBY_EXTERN VALUE rb_output_fs;
RUBY_EXTERN VALUE rb_rs;
RUBY_EXTERN VALUE rb_default_rs;
RUBY_EXTERN VALUE rb_output_rs;
VALUE rb_io_write(VALUE, VALUE);
VALUE rb_io_gets(VALUE);
VALUE rb_io_getbyte(VALUE);
VALUE rb_io_ungetc(VALUE, VALUE);
VALUE rb_io_ungetbyte(VALUE, VALUE);
VALUE rb_io_close(VALUE);
VALUE rb_io_flush(VALUE);
VALUE rb_io_eof(VALUE);
VALUE rb_io_binmode(VALUE);
VALUE rb_io_ascii8bit_binmode(VALUE);
VALUE rb_io_addstr(VALUE, VALUE);
VALUE rb_io_printf(int, const VALUE*, VALUE);
VALUE rb_io_print(int, const VALUE*, VALUE);
VALUE rb_io_puts(int, const VALUE*, VALUE);
VALUE rb_io_fdopen(int, int, const char*);
VALUE rb_io_get_io(VALUE);
VALUE rb_file_open(const char*, const char*);
VALUE rb_file_open_str(VALUE, const char*);
VALUE rb_gets(void);
void rb_write_error(const char*);
void rb_write_error2(const char*, long);
void rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds);
int rb_pipe(int *pipes);
int rb_reserved_fd_p(int fd);
int rb_cloexec_open(const char *pathname, int flags, mode_t mode);
int rb_cloexec_dup(int oldfd);
int rb_cloexec_dup2(int oldfd, int newfd);
int rb_cloexec_pipe(int fildes[2]);
int rb_cloexec_fcntl_dupfd(int fd, int minfd);
#define RB_RESERVED_FD_P(fd) rb_reserved_fd_p(fd)
void rb_update_max_fd(int fd);
void rb_fd_fix_cloexec(int fd);
/* marshal.c */
VALUE rb_marshal_dump(VALUE, VALUE);
VALUE rb_marshal_load(VALUE);
void rb_marshal_define_compat(VALUE newclass, VALUE oldclass, VALUE (*dumper)(VALUE), VALUE (*loader)(VALUE, VALUE));
/* numeric.c */
NORETURN(void rb_num_zerodiv(void));
#define RB_NUM_COERCE_FUNCS_NEED_OPID 1
VALUE rb_num_coerce_bin(VALUE, VALUE, ID);
VALUE rb_num_coerce_cmp(VALUE, VALUE, ID);
VALUE rb_num_coerce_relop(VALUE, VALUE, ID);
VALUE rb_num_coerce_bit(VALUE, VALUE, ID);
VALUE rb_num2fix(VALUE);
VALUE rb_fix2str(VALUE, int);
CONSTFUNC(VALUE rb_dbl_cmp(double, double));
/* object.c */
int rb_eql(VALUE, VALUE);
VALUE rb_any_to_s(VALUE);
VALUE rb_inspect(VALUE);
VALUE rb_obj_is_instance_of(VALUE, VALUE);
VALUE rb_obj_is_kind_of(VALUE, VALUE);
VALUE rb_obj_alloc(VALUE);
VALUE rb_obj_clone(VALUE);
VALUE rb_obj_dup(VALUE);
VALUE rb_obj_init_copy(VALUE,VALUE);
VALUE rb_obj_taint(VALUE);
PUREFUNC(VALUE rb_obj_tainted(VALUE));
VALUE rb_obj_untaint(VALUE);
VALUE rb_obj_untrust(VALUE);
PUREFUNC(VALUE rb_obj_untrusted(VALUE));
VALUE rb_obj_trust(VALUE);
VALUE rb_obj_freeze(VALUE);
PUREFUNC(VALUE rb_obj_frozen_p(VALUE));
VALUE rb_obj_id(VALUE);
VALUE rb_memory_id(VALUE);
VALUE rb_obj_class(VALUE);
PUREFUNC(VALUE rb_class_real(VALUE));
PUREFUNC(VALUE rb_class_inherited_p(VALUE, VALUE));
VALUE rb_class_superclass(VALUE);
VALUE rb_class_get_superclass(VALUE);
VALUE rb_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_to_integer(VALUE, const char *);
VALUE rb_check_to_float(VALUE);
VALUE rb_to_int(VALUE);
VALUE rb_check_to_int(VALUE);
VALUE rb_Integer(VALUE);
VALUE rb_to_float(VALUE);
VALUE rb_Float(VALUE);
VALUE rb_String(VALUE);
VALUE rb_Array(VALUE);
VALUE rb_Hash(VALUE);
double rb_cstr_to_dbl(const char*, int);
double rb_str_to_dbl(VALUE, int);
/* parse.y */
ID rb_id_attrset(ID);
CONSTFUNC(int rb_is_const_id(ID));
CONSTFUNC(int rb_is_global_id(ID));
CONSTFUNC(int rb_is_instance_id(ID));
CONSTFUNC(int rb_is_attrset_id(ID));
CONSTFUNC(int rb_is_class_id(ID));
CONSTFUNC(int rb_is_local_id(ID));
CONSTFUNC(int rb_is_junk_id(ID));
int rb_symname_p(const char*);
int rb_sym_interned_p(VALUE);
VALUE rb_backref_get(void);
void rb_backref_set(VALUE);
VALUE rb_lastline_get(void);
void rb_lastline_set(VALUE);
/* process.c */
void rb_last_status_set(int status, rb_pid_t pid);
VALUE rb_last_status_get(void);
int rb_proc_exec(const char*);
NORETURN(VALUE rb_f_exec(int, const VALUE*));
rb_pid_t rb_waitpid(rb_pid_t pid, int *status, int flags);
void rb_syswait(rb_pid_t pid);
rb_pid_t rb_spawn(int, const VALUE*);
rb_pid_t rb_spawn_err(int, const VALUE*, char*, size_t);
VALUE rb_proc_times(VALUE);
VALUE rb_detach_process(rb_pid_t pid);
/* range.c */
VALUE rb_range_new(VALUE, VALUE, int);
VALUE rb_range_beg_len(VALUE, long*, long*, long, int);
int rb_range_values(VALUE range, VALUE *begp, VALUE *endp, int *exclp);
/* random.c */
unsigned int rb_genrand_int32(void);
double rb_genrand_real(void);
void rb_reset_random_seed(void);
VALUE rb_random_bytes(VALUE rnd, long n);
VALUE rb_random_int(VALUE rnd, VALUE max);
unsigned int rb_random_int32(VALUE rnd);
double rb_random_real(VALUE rnd);
unsigned long rb_random_ulong_limited(VALUE rnd, unsigned long limit);
unsigned long rb_genrand_ulong_limited(unsigned long i);
/* re.c */
#define rb_memcmp memcmp
int rb_memcicmp(const void*,const void*,long);
void rb_match_busy(VALUE);
VALUE rb_reg_nth_defined(int, VALUE);
VALUE rb_reg_nth_match(int, VALUE);
int rb_reg_backref_number(VALUE match, VALUE backref);
VALUE rb_reg_last_match(VALUE);
VALUE rb_reg_match_pre(VALUE);
VALUE rb_reg_match_post(VALUE);
VALUE rb_reg_match_last(VALUE);
#define HAVE_RB_REG_NEW_STR 1
VALUE rb_reg_new_str(VALUE, int);
VALUE rb_reg_new(const char *, long, int);
VALUE rb_reg_alloc(void);
VALUE rb_reg_init_str(VALUE re, VALUE s, int options);
VALUE rb_reg_match(VALUE, VALUE);
VALUE rb_reg_match2(VALUE);
int rb_reg_options(VALUE);
/* ruby.c */
#define rb_argv rb_get_argv()
RUBY_EXTERN VALUE rb_argv0;
VALUE rb_get_argv(void);
void *rb_load_file(const char*);
void *rb_load_file_str(VALUE);
/* signal.c */
VALUE rb_f_kill(int, const VALUE*);
#ifdef POSIX_SIGNAL
#define posix_signal ruby_posix_signal
RETSIGTYPE (*posix_signal(int, RETSIGTYPE (*)(int)))(int);
#endif
const char *ruby_signal_name(int);
void ruby_default_signal(int);
/* sprintf.c */
VALUE rb_f_sprintf(int, const VALUE*);
PRINTF_ARGS(VALUE rb_sprintf(const char*, ...), 1, 2);
VALUE rb_vsprintf(const char*, va_list);
PRINTF_ARGS(VALUE rb_str_catf(VALUE, const char*, ...), 2, 3);
VALUE rb_str_vcatf(VALUE, const char*, va_list);
VALUE rb_str_format(int, const VALUE *, VALUE);
/* string.c */
VALUE rb_str_new(const char*, long);
VALUE rb_str_new_cstr(const char*);
VALUE rb_str_new_shared(VALUE);
VALUE rb_str_new_frozen(VALUE);
VALUE rb_str_new_with_class(VALUE, const char*, long);
VALUE rb_tainted_str_new_cstr(const char*);
VALUE rb_tainted_str_new(const char*, long);
VALUE rb_external_str_new(const char*, long);
VALUE rb_external_str_new_cstr(const char*);
VALUE rb_locale_str_new(const char*, long);
VALUE rb_locale_str_new_cstr(const char*);
VALUE rb_filesystem_str_new(const char*, long);
VALUE rb_filesystem_str_new_cstr(const char*);
VALUE rb_str_buf_new(long);
VALUE rb_str_buf_new_cstr(const char*);
VALUE rb_str_buf_new2(const char*);
VALUE rb_str_tmp_new(long);
VALUE rb_usascii_str_new(const char*, long);
VALUE rb_usascii_str_new_cstr(const char*);
VALUE rb_utf8_str_new(const char*, long);
VALUE rb_utf8_str_new_cstr(const char*);
VALUE rb_str_new_static(const char *, long);
VALUE rb_usascii_str_new_static(const char *, long);
VALUE rb_utf8_str_new_static(const char *, long);
void rb_str_free(VALUE);
void rb_str_shared_replace(VALUE, VALUE);
VALUE rb_str_buf_append(VALUE, VALUE);
VALUE rb_str_buf_cat(VALUE, const char*, long);
VALUE rb_str_buf_cat2(VALUE, const char*);
VALUE rb_str_buf_cat_ascii(VALUE, const char*);
VALUE rb_obj_as_string(VALUE);
VALUE rb_check_string_type(VALUE);
void rb_must_asciicompat(VALUE);
VALUE rb_str_dup(VALUE);
VALUE rb_str_resurrect(VALUE str);
VALUE rb_str_locktmp(VALUE);
VALUE rb_str_unlocktmp(VALUE);
VALUE rb_str_dup_frozen(VALUE);
#define rb_str_dup_frozen rb_str_new_frozen
VALUE rb_str_plus(VALUE, VALUE);
VALUE rb_str_times(VALUE, VALUE);
long rb_str_sublen(VALUE, long);
VALUE rb_str_substr(VALUE, long, long);
VALUE rb_str_subseq(VALUE, long, long);
char *rb_str_subpos(VALUE, long, long*);
void rb_str_modify(VALUE);
void rb_str_modify_expand(VALUE, long);
VALUE rb_str_freeze(VALUE);
void rb_str_set_len(VALUE, long);
VALUE rb_str_resize(VALUE, long);
VALUE rb_str_cat(VALUE, const char*, long);
VALUE rb_str_cat_cstr(VALUE, const char*);
VALUE rb_str_cat2(VALUE, const char*);
VALUE rb_str_append(VALUE, VALUE);
VALUE rb_str_concat(VALUE, VALUE);
st_index_t rb_memhash(const void *ptr, long len);
st_index_t rb_hash_start(st_index_t);
st_index_t rb_hash_uint32(st_index_t, uint32_t);
st_index_t rb_hash_uint(st_index_t, st_index_t);
st_index_t rb_hash_end(st_index_t);
#define rb_hash_uint32(h, i) st_hash_uint32((h), (i))
#define rb_hash_uint(h, i) st_hash_uint((h), (i))
#define rb_hash_end(h) st_hash_end(h)
st_index_t rb_str_hash(VALUE);
int rb_str_hash_cmp(VALUE,VALUE);
int rb_str_comparable(VALUE, VALUE);
int rb_str_cmp(VALUE, VALUE);
VALUE rb_str_equal(VALUE str1, VALUE str2);
VALUE rb_str_drop_bytes(VALUE, long);
void rb_str_update(VALUE, long, long, VALUE);
VALUE rb_str_replace(VALUE, VALUE);
VALUE rb_str_inspect(VALUE);
VALUE rb_str_dump(VALUE);
VALUE rb_str_split(VALUE, const char*);
rb_gvar_setter_t rb_str_setter;
VALUE rb_str_intern(VALUE);
VALUE rb_sym_to_s(VALUE);
long rb_str_strlen(VALUE);
VALUE rb_str_length(VALUE);
long rb_str_offset(VALUE, long);
PUREFUNC(size_t rb_str_capacity(VALUE));
VALUE rb_str_ellipsize(VALUE, long);
VALUE rb_str_scrub(VALUE, VALUE);
/* symbol.c */
VALUE rb_sym_all_symbols(void);

#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
#define rb_str_new(str, len) RB_GNUC_EXTENSION_BLOCK(	\
    (__builtin_constant_p(str) && __builtin_constant_p(len)) ? \
	rb_str_new_static((str), (len)) : \
	rb_str_new((str), (len))	  \
)
#define rb_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK(	\
    (__builtin_constant_p(str)) ?		\
	rb_str_new_static((str), (long)strlen(str)) : \
	rb_str_new_cstr(str)			\
)
#define rb_usascii_str_new(str, len) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str) && __builtin_constant_p(len)) ? \
	rb_usascii_str_new_static((str), (len)) : \
	rb_usascii_str_new((str), (len))	  \
)
#define rb_utf8_str_new(str, len) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str) && __builtin_constant_p(len)) ? \
	rb_utf8_str_new_static((str), (len)) : \
	rb_utf8_str_new((str), (len))	  \
)
#define rb_tainted_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?	       \
	rb_tainted_str_new((str), (long)strlen(str)) : \
	rb_tainted_str_new_cstr(str)	       \
)
#define rb_usascii_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?	       \
	rb_usascii_str_new_static((str), (long)strlen(str)) : \
	rb_usascii_str_new_cstr(str)	       \
)
#define rb_utf8_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?		\
	rb_utf8_str_new_static((str), (long)strlen(str)) : \
	rb_utf8_str_new_cstr(str)		\
)
#define rb_external_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?		\
	rb_external_str_new((str), (long)strlen(str)) : \
	rb_external_str_new_cstr(str)		\
)
#define rb_locale_str_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?	       \
	rb_locale_str_new((str), (long)strlen(str)) :  \
	rb_locale_str_new_cstr(str)	       \
)
#define rb_str_buf_new_cstr(str) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str)) ?		\
	rb_str_buf_cat(rb_str_buf_new((long)strlen(str)), \
		       (str), (long)strlen(str)) : \
	rb_str_buf_new_cstr(str)		\
)
#define rb_str_cat_cstr(str, ptr) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(ptr)) ?	        \
	rb_str_cat((str), (ptr), (long)strlen(ptr)) : \
	rb_str_cat_cstr((str), (ptr))		\
)
#define rb_exc_new_cstr(klass, ptr) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(ptr)) ?	        \
	rb_exc_new((klass), (ptr), (long)strlen(ptr)) : \
	rb_exc_new_cstr((klass), (ptr))		\
)
#endif
#define rb_str_new2 rb_str_new_cstr
#define rb_str_new3 rb_str_new_shared
#define rb_str_new4 rb_str_new_frozen
#define rb_str_new5 rb_str_new_with_class
#define rb_tainted_str_new2 rb_tainted_str_new_cstr
#define rb_str_buf_new2 rb_str_buf_new_cstr
#define rb_usascii_str_new2 rb_usascii_str_new_cstr
#define rb_str_buf_cat rb_str_cat
#define rb_str_buf_cat2 rb_str_cat_cstr
#define rb_str_cat2 rb_str_cat_cstr
#define rb_strlen_lit(str) (sizeof(str "") - 1)
#define rb_str_new_lit(str) rb_str_new_static((str), rb_strlen_lit(str))
#define rb_usascii_str_new_lit(str) rb_usascii_str_new_static((str), rb_strlen_lit(str))
#define rb_utf8_str_new_lit(str) rb_utf8_str_new_static((str), rb_strlen_lit(str))
#define rb_enc_str_new_lit(str, enc) rb_enc_str_new_static((str), rb_strlen_lit(str), (enc))
#define rb_str_new_literal(str) rb_str_new_lit(str)
#define rb_usascii_str_new_literal(str) rb_usascii_str_new_lit(str)
#define rb_utf8_str_new_literal(str) rb_utf8_str_new_lit(str)
#define rb_enc_str_new_literal(str, enc) rb_enc_str_new_lit(str, enc)

/* struct.c */
VALUE rb_struct_new(VALUE, ...);
VALUE rb_struct_define(const char*, ...);
VALUE rb_struct_define_under(VALUE, const char*, ...);
VALUE rb_struct_alloc(VALUE, VALUE);
VALUE rb_struct_initialize(VALUE, VALUE);
VALUE rb_struct_aref(VALUE, VALUE);
VALUE rb_struct_aset(VALUE, VALUE, VALUE);
VALUE rb_struct_getmember(VALUE, ID);
VALUE rb_struct_s_members(VALUE);
VALUE rb_struct_members(VALUE);
VALUE rb_struct_size(VALUE s);
VALUE rb_struct_alloc_noinit(VALUE);
VALUE rb_struct_define_without_accessor(const char *, VALUE, rb_alloc_func_t, ...);
VALUE rb_struct_define_without_accessor_under(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, ...);

/* thread.c */
typedef void rb_unblock_function_t(void *);
typedef VALUE rb_blocking_function_t(void *);
void rb_thread_check_ints(void);
int rb_thread_interrupted(VALUE thval);

#define RUBY_UBF_IO ((rb_unblock_function_t *)-1)
#define RUBY_UBF_PROCESS ((rb_unblock_function_t *)-1)
VALUE rb_mutex_new(void);
VALUE rb_mutex_locked_p(VALUE mutex);
VALUE rb_mutex_trylock(VALUE mutex);
VALUE rb_mutex_lock(VALUE mutex);
VALUE rb_mutex_unlock(VALUE mutex);
VALUE rb_mutex_sleep(VALUE self, VALUE timeout);
VALUE rb_mutex_synchronize(VALUE mutex, VALUE (*func)(VALUE arg), VALUE arg);
/* time.c */
struct timespec;
void rb_timespec_now(struct timespec *);
VALUE rb_time_new(time_t, long);
VALUE rb_time_nano_new(time_t, long);
VALUE rb_time_timespec_new(const struct timespec *, int);
VALUE rb_time_num_new(VALUE, VALUE);
struct timeval rb_time_interval(VALUE num);
struct timeval rb_time_timeval(VALUE time);
struct timespec rb_time_timespec(VALUE time);
struct timespec rb_time_timespec_interval(VALUE num);
VALUE rb_time_utc_offset(VALUE time);
/* variable.c */
VALUE rb_mod_name(VALUE);
VALUE rb_class_path(VALUE);
VALUE rb_class_path_cached(VALUE);
void rb_set_class_path(VALUE, VALUE, const char*);
void rb_set_class_path_string(VALUE, VALUE, VALUE);
VALUE rb_path_to_class(VALUE);
VALUE rb_path2class(const char*);
VALUE rb_class_name(VALUE);
VALUE rb_autoload_load(VALUE, ID);
VALUE rb_autoload_p(VALUE, ID);
VALUE rb_f_trace_var(int, const VALUE*);
VALUE rb_f_untrace_var(int, const VALUE*);
VALUE rb_f_global_variables(void);
void rb_alias_variable(ID, ID);
void rb_copy_generic_ivar(VALUE,VALUE);
void rb_free_generic_ivar(VALUE);
VALUE rb_ivar_get(VALUE, ID);
VALUE rb_ivar_set(VALUE, ID, VALUE);
VALUE rb_ivar_defined(VALUE, ID);
void rb_ivar_foreach(VALUE, int (*)(ID, VALUE, st_data_t), st_data_t);
st_index_t rb_ivar_count(VALUE);
VALUE rb_attr_get(VALUE, ID);
VALUE rb_obj_instance_variables(VALUE);
VALUE rb_obj_remove_instance_variable(VALUE, VALUE);
void *rb_mod_const_at(VALUE, void*);
void *rb_mod_const_of(VALUE, void*);
VALUE rb_const_list(void*);
VALUE rb_mod_constants(int, const VALUE *, VALUE);
VALUE rb_mod_remove_const(VALUE, VALUE);
int rb_const_defined(VALUE, ID);
int rb_const_defined_at(VALUE, ID);
int rb_const_defined_from(VALUE, ID);
VALUE rb_const_get(VALUE, ID);
VALUE rb_const_get_at(VALUE, ID);
VALUE rb_const_get_from(VALUE, ID);
void rb_const_set(VALUE, ID, VALUE);
VALUE rb_const_remove(VALUE, ID);
#if 0 /* EXPERIMENTAL: remove if no problem */
NORETURN(VALUE rb_mod_const_missing(VALUE,VALUE));
#endif
VALUE rb_cvar_defined(VALUE, ID);
void rb_cvar_set(VALUE, ID, VALUE);
VALUE rb_cvar_get(VALUE, ID);
void rb_cv_set(VALUE, const char*, VALUE);
VALUE rb_cv_get(VALUE, const char*);
void rb_define_class_variable(VALUE, const char*, VALUE);
VALUE rb_mod_class_variables(int, const VALUE*, VALUE);
VALUE rb_mod_remove_cvar(VALUE, VALUE);

ID rb_frame_callee(void);
int rb_frame_method_id_and_class(ID *idp, VALUE *klassp);
VALUE rb_str_succ(VALUE);
VALUE rb_time_succ(VALUE);
VALUE rb_make_backtrace(void);
VALUE rb_make_exception(int, const VALUE*);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
extern "C++" {
#endif

#if defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
# define rb_f_notimplement_p(f) __builtin_types_compatible_p(__typeof__(f),__typeof__(rb_f_notimplement))
#else
# define rb_f_notimplement_p(f) 0
#endif

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P) && !defined(_WIN32) && !defined(__CYGWIN__)
#if defined(__has_attribute) && __has_attribute(transparent_union) && __has_attribute(unused) && __has_attribute(weakref) && __has_attribute(nonnull)
#define RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,funcargs) \
    __attribute__((__unused__,__weakref__(#def),__nonnull__ nonnull))static void defname(RB_UNWRAP_MACRO decl,VALUE(*func)funcargs,int arity);
#endif
#endif

#if defined(RB_METHOD_DEFINITION_DECL_C) || defined(__cplusplus)
#ifndef RB_METHOD_DEFINITION_DECL_C
#define RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,funcargs) \
    static inline void defname(RB_UNWRAP_MACRO decl,VALUE(*func)funcargs,int arity) \
    { \
        def(RB_UNWRAP_MACRO vars,(VALUE(*)(ANYARGS))(func),arity); \
    }
#endif

#define RB_UNWRAP_MACRO(...) __VA_ARGS__

#ifdef __cplusplus
#define RB_METHOD_DEFINITION_DECL_CXX_BEGIN(def) template <int Arity> struct def##_tmpl {};
#define RB_METHOD_DEFINITION_DECL_CXX(def,defname,decl,vars,funcargs,arity) \
    template <> struct def##_tmpl<arity> { \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)funcargs) {::defname(RB_UNWRAP_MACRO vars, func, arity);} \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)(...)) {::defname(RB_UNWRAP_MACRO vars, reinterpret_cast<VALUE(*)funcargs>(func), arity);} \
    };
#else
#define RB_METHOD_DEFINITION_DECL_CXX_BEGIN(def) /* nothing */
#define RB_METHOD_DEFINITION_DECL_CXX(def,defname,decl,vars,funcargs,arity) /* nothing */
#endif
#define RB_METHOD_DEFINITION_DECL_1(def,nonnull,defname,arity,decl,vars,funcargs) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,funcargs) \
    RB_METHOD_DEFINITION_DECL_CXX(def,defname,decl,vars,funcargs,arity)

#define RB_METHOD_DEFINITION_DECL(def,nonnull,decl,vars) \
RB_METHOD_DEFINITION_DECL_CXX_BEGIN(def) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##0 ,0 ,decl,vars,(VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##1 ,1 ,decl,vars,(VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##2 ,2 ,decl,vars,(VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##3 ,3 ,decl,vars,(VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##4 ,4 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##5 ,5 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##6 ,6 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##7 ,7 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##8 ,8 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##9 ,9 ,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##10,10,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##11,11,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##12,12,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##13,13,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##14,14,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##15,15,decl,vars,(VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_M3(def,nonnull,def##m3,decl,vars) \
RB_METHOD_DEFINITION_DECL_1(def,nonnull,def##m2,-2,decl,vars,(VALUE,VALUE)) \
RB_METHOD_DEFINITION_DECL_M1(def,nonnull,def##m1,decl,vars) /* END */
#ifdef __cplusplus
#define RB_METHOD_DEFINITION_DECL_M1(def,nonnull,defname,decl,vars) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,(int,VALUE*,VALUE)) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,(int,const VALUE*,VALUE)) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,(int,const VALUE*,VALUE,VALUE)) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,(...)) \
    template <> struct def##_tmpl<-1> { \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)(int,VALUE*,VALUE)) {::defname(RB_UNWRAP_MACRO vars, func, -1);} \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)(int,const VALUE*,VALUE)) {::defname(RB_UNWRAP_MACRO vars, func, -1);} \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)(int,const VALUE*,VALUE,VALUE)) {::defname(RB_UNWRAP_MACRO vars, func, -1);} \
        static void define(RB_UNWRAP_MACRO decl, VALUE (*func)(...)) {::defname(RB_UNWRAP_MACRO vars, func, -1);} \
    };
#define RB_METHOD_DEFINITION_DECL_M3(def,nonnull,defname,decl,vars) /* nothing */
#else
#define RB_METHOD_DEFINITION_DECL_M1(def,nonnull,defname,decl,vars) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,(int,union{VALUE*x;const VALUE*y;}__attribute__((__transparent_union__)),VALUE))
#define RB_METHOD_DEFINITION_DECL_M3(def,nonnull,defname,decl,vars) \
    RB_METHOD_DEFINITION_DECL_C(def,nonnull,defname,decl,vars,())
#endif

#endif

#ifdef RB_METHOD_DEFINITION_DECL

RB_METHOD_DEFINITION_DECL(rb_define_method_id, (3), (VALUE klass, ID name), (klass, name))
#ifdef __cplusplus
#define rb_define_method_id(m, n, f, a) rb_define_method_id_tmpl<a>::define(m, n, f)
#else
#define rb_define_method_id_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_method_id15,rb_define_method_idm3)
#define rb_define_method_id_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_method_id14,rb_define_method_id_choose_prototype15(n))
#define rb_define_method_id_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_method_id13,rb_define_method_id_choose_prototype14(n))
#define rb_define_method_id_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_method_id12,rb_define_method_id_choose_prototype13(n))
#define rb_define_method_id_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_method_id11,rb_define_method_id_choose_prototype12(n))
#define rb_define_method_id_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_method_id10,rb_define_method_id_choose_prototype11(n))
#define rb_define_method_id_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_method_id9, rb_define_method_id_choose_prototype10(n))
#define rb_define_method_id_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_method_id8, rb_define_method_id_choose_prototype9(n))
#define rb_define_method_id_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_method_id7, rb_define_method_id_choose_prototype8(n))
#define rb_define_method_id_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_method_id6, rb_define_method_id_choose_prototype7(n))
#define rb_define_method_id_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_method_id5, rb_define_method_id_choose_prototype6(n))
#define rb_define_method_id_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_method_id4, rb_define_method_id_choose_prototype5(n))
#define rb_define_method_id_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_method_id3, rb_define_method_id_choose_prototype4(n))
#define rb_define_method_id_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_method_id2, rb_define_method_id_choose_prototype3(n))
#define rb_define_method_id_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_method_id1, rb_define_method_id_choose_prototype2(n))
#define rb_define_method_id_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_method_id0, rb_define_method_id_choose_prototype1(n))
#define rb_define_method_id_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_method_idm1,rb_define_method_id_choose_prototype0(n))
#define rb_define_method_id_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_method_idm2,rb_define_method_id_choose_prototypem1(n))
#define rb_define_method_id_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_method_idm3,rb_define_method_id_choose_prototypem2(n))
#define rb_define_method_id(klass, mid, func, arity) rb_define_method_id_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

RB_METHOD_DEFINITION_DECL(rb_define_protected_method, (2,3), (VALUE klass, const char *name), (klass, name))
#ifdef __cplusplus
#define rb_define_protected_method(m, n, f, a) rb_define_protected_method_tmpl<a>::define(m, n, f)
#else
#define rb_define_protected_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_protected_method15,rb_define_protected_methodm3)
#define rb_define_protected_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_protected_method14,rb_define_protected_method_choose_prototype15(n))
#define rb_define_protected_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_protected_method13,rb_define_protected_method_choose_prototype14(n))
#define rb_define_protected_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_protected_method12,rb_define_protected_method_choose_prototype13(n))
#define rb_define_protected_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_protected_method11,rb_define_protected_method_choose_prototype12(n))
#define rb_define_protected_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_protected_method10,rb_define_protected_method_choose_prototype11(n))
#define rb_define_protected_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_protected_method9, rb_define_protected_method_choose_prototype10(n))
#define rb_define_protected_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_protected_method8, rb_define_protected_method_choose_prototype9(n))
#define rb_define_protected_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_protected_method7, rb_define_protected_method_choose_prototype8(n))
#define rb_define_protected_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_protected_method6, rb_define_protected_method_choose_prototype7(n))
#define rb_define_protected_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_protected_method5, rb_define_protected_method_choose_prototype6(n))
#define rb_define_protected_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_protected_method4, rb_define_protected_method_choose_prototype5(n))
#define rb_define_protected_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_protected_method3, rb_define_protected_method_choose_prototype4(n))
#define rb_define_protected_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_protected_method2, rb_define_protected_method_choose_prototype3(n))
#define rb_define_protected_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_protected_method1, rb_define_protected_method_choose_prototype2(n))
#define rb_define_protected_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_protected_method0, rb_define_protected_method_choose_prototype1(n))
#define rb_define_protected_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_protected_methodm1,rb_define_protected_method_choose_prototype0(n))
#define rb_define_protected_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_protected_methodm2,rb_define_protected_method_choose_prototypem1(n))
#define rb_define_protected_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_protected_methodm3,rb_define_protected_method_choose_prototypem2(n))
#define rb_define_protected_method(klass, mid, func, arity) rb_define_protected_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

RB_METHOD_DEFINITION_DECL(rb_define_private_method, (2,3), (VALUE klass, const char *name), (klass, name))
#ifdef __cplusplus
#define rb_define_private_method(m, n, f, a) rb_define_private_method_tmpl<a>::define(m, n, f)
#else
#define rb_define_private_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_private_method15,rb_define_private_methodm3)
#define rb_define_private_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_private_method14,rb_define_private_method_choose_prototype15(n))
#define rb_define_private_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_private_method13,rb_define_private_method_choose_prototype14(n))
#define rb_define_private_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_private_method12,rb_define_private_method_choose_prototype13(n))
#define rb_define_private_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_private_method11,rb_define_private_method_choose_prototype12(n))
#define rb_define_private_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_private_method10,rb_define_private_method_choose_prototype11(n))
#define rb_define_private_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_private_method9, rb_define_private_method_choose_prototype10(n))
#define rb_define_private_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_private_method8, rb_define_private_method_choose_prototype9(n))
#define rb_define_private_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_private_method7, rb_define_private_method_choose_prototype8(n))
#define rb_define_private_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_private_method6, rb_define_private_method_choose_prototype7(n))
#define rb_define_private_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_private_method5, rb_define_private_method_choose_prototype6(n))
#define rb_define_private_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_private_method4, rb_define_private_method_choose_prototype5(n))
#define rb_define_private_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_private_method3, rb_define_private_method_choose_prototype4(n))
#define rb_define_private_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_private_method2, rb_define_private_method_choose_prototype3(n))
#define rb_define_private_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_private_method1, rb_define_private_method_choose_prototype2(n))
#define rb_define_private_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_private_method0, rb_define_private_method_choose_prototype1(n))
#define rb_define_private_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_private_methodm1,rb_define_private_method_choose_prototype0(n))
#define rb_define_private_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_private_methodm2,rb_define_private_method_choose_prototypem1(n))
#define rb_define_private_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_private_methodm3,rb_define_private_method_choose_prototypem2(n))
#define rb_define_private_method(klass, mid, func, arity) rb_define_private_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

RB_METHOD_DEFINITION_DECL(rb_define_singleton_method, (2,3), (VALUE klass, const char *name), (klass, name))
#ifdef __cplusplus
#define rb_define_singleton_method(m, n, f, a) rb_define_singleton_method_tmpl<a>::define(m, n, f)
#else
#define rb_define_singleton_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_singleton_method15,rb_define_singleton_methodm3)
#define rb_define_singleton_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_singleton_method14,rb_define_singleton_method_choose_prototype15(n))
#define rb_define_singleton_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_singleton_method13,rb_define_singleton_method_choose_prototype14(n))
#define rb_define_singleton_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_singleton_method12,rb_define_singleton_method_choose_prototype13(n))
#define rb_define_singleton_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_singleton_method11,rb_define_singleton_method_choose_prototype12(n))
#define rb_define_singleton_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_singleton_method10,rb_define_singleton_method_choose_prototype11(n))
#define rb_define_singleton_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_singleton_method9, rb_define_singleton_method_choose_prototype10(n))
#define rb_define_singleton_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_singleton_method8, rb_define_singleton_method_choose_prototype9(n))
#define rb_define_singleton_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_singleton_method7, rb_define_singleton_method_choose_prototype8(n))
#define rb_define_singleton_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_singleton_method6, rb_define_singleton_method_choose_prototype7(n))
#define rb_define_singleton_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_singleton_method5, rb_define_singleton_method_choose_prototype6(n))
#define rb_define_singleton_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_singleton_method4, rb_define_singleton_method_choose_prototype5(n))
#define rb_define_singleton_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_singleton_method3, rb_define_singleton_method_choose_prototype4(n))
#define rb_define_singleton_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_singleton_method2, rb_define_singleton_method_choose_prototype3(n))
#define rb_define_singleton_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_singleton_method1, rb_define_singleton_method_choose_prototype2(n))
#define rb_define_singleton_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_singleton_method0, rb_define_singleton_method_choose_prototype1(n))
#define rb_define_singleton_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_singleton_methodm1,rb_define_singleton_method_choose_prototype0(n))
#define rb_define_singleton_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_singleton_methodm2,rb_define_singleton_method_choose_prototypem1(n))
#define rb_define_singleton_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_singleton_methodm3,rb_define_singleton_method_choose_prototypem2(n))
#define rb_define_singleton_method(klass, mid, func, arity) rb_define_singleton_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

#endif

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C++" { */
#endif

#endif /* RUBY_INTERN_H */
