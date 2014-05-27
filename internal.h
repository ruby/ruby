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

#ifdef HAVE_VALGRIND_MEMCHECK_H
# include <valgrind/memcheck.h>
# ifndef VALGRIND_MAKE_MEM_DEFINED
#  define VALGRIND_MAKE_MEM_DEFINED(p, n) VALGRIND_MAKE_READABLE((p), (n))
# endif
# ifndef VALGRIND_MAKE_MEM_UNDEFINED
#  define VALGRIND_MAKE_MEM_UNDEFINED(p, n) VALGRIND_MAKE_WRITABLE((p), (n))
# endif
#else
# define VALGRIND_MAKE_MEM_DEFINED(p, n) 0
# define VALGRIND_MAKE_MEM_UNDEFINED(p, n) 0
#endif

#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))

#define STATIC_ASSERT(name, expr) typedef int static_assert_##name##_check[1 - 2*!(expr)]

#define GCC_VERSION_SINCE(major, minor, patchlevel) \
  (defined(__GNUC__) && !defined(__INTEL_COMPILER) && \
   ((__GNUC__ > (major)) ||  \
    (__GNUC__ == (major) && __GNUC_MINOR__ > (minor)) || \
    (__GNUC__ == (major) && __GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ >= (patchlevel))))

#define SIGNED_INTEGER_TYPE_P(int_type) (0 > ((int_type)0)-1)
#define SIGNED_INTEGER_MAX(sint_type) \
  (sint_type) \
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

#ifndef swap16
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP16
#  define swap16(x) __builtin_bswap16(x)
# endif
#endif

#ifndef swap16
# define swap16(x)      ((uint16_t)((((x)&0xFF)<<8) | (((x)>>8)&0xFF)))
#endif

#ifndef swap32
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP32
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
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP64
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

static inline int
nlz_int(unsigned int x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZ)
    if (x == 0) return SIZEOF_INT * CHAR_BIT;
    return __builtin_clz(x);
#else
    unsigned int y;
# if 64 < SIZEOF_INT * CHAR_BIT
    int n = 128;
# elif 32 < SIZEOF_INT * CHAR_BIT
    int n = 64;
# else
    int n = 32;
# endif
# if 64 < SIZEOF_INT * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_INT * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
#endif
}

static inline int
nlz_long(unsigned long x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZL)
    if (x == 0) return SIZEOF_LONG * CHAR_BIT;
    return __builtin_clzl(x);
#else
    unsigned long y;
# if 64 < SIZEOF_LONG * CHAR_BIT
    int n = 128;
# elif 32 < SIZEOF_LONG * CHAR_BIT
    int n = 64;
# else
    int n = 32;
# endif
# if 64 < SIZEOF_LONG * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_LONG * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
#endif
}

#ifdef HAVE_LONG_LONG
static inline int
nlz_long_long(unsigned LONG_LONG x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZLL)
    if (x == 0) return SIZEOF_LONG_LONG * CHAR_BIT;
    return __builtin_clzll(x);
#else
    unsigned LONG_LONG y;
# if 64 < SIZEOF_LONG_LONG * CHAR_BIT
    int n = 128;
# elif 32 < SIZEOF_LONG_LONG * CHAR_BIT
    int n = 64;
# else
    int n = 32;
# endif
# if 64 < SIZEOF_LONG_LONG * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_LONG_LONG * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
#endif
}
#endif

#ifdef HAVE_UINT128_T
static inline int
nlz_int128(uint128_t x)
{
    uint128_t y;
    int n = 128;
    y = x >> 64; if (y) {n -= 64; x = y;}
    y = x >> 32; if (y) {n -= 32; x = y;}
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
}
#endif

#if defined(HAVE_UINT128_T)
#   define bit_length(x) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     sizeof(x) <= SIZEOF_LONG ? SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)) : \
     sizeof(x) <= SIZEOF_LONG_LONG ? SIZEOF_LONG_LONG * CHAR_BIT - nlz_long_long((unsigned LONG_LONG)(x)) : \
     SIZEOF_INT128_T * CHAR_BIT - nlz_int128((uint128_t)(x)))
#elif defined(HAVE_LONG_LONG)
#   define bit_length(x) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     sizeof(x) <= SIZEOF_LONG ? SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)) : \
     SIZEOF_LONG_LONG * CHAR_BIT - nlz_long_long((unsigned LONG_LONG)(x)))
#else
#   define bit_length(x) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)))
#endif

struct rb_deprecated_classext_struct {
    char conflict[sizeof(VALUE) * 3];
};

struct rb_subclass_entry;
typedef struct rb_subclass_entry rb_subclass_entry_t;

struct rb_subclass_entry {
    VALUE klass;
    rb_subclass_entry_t *next;
};

#if defined(HAVE_LONG_LONG)
typedef unsigned LONG_LONG rb_serial_t;
#define SERIALT2NUM ULL2NUM
#elif defined(HAVE_UINT64_T)
typedef uint64_t rb_serial_t;
#define SERIALT2NUM SIZET2NUM
#else
typedef unsigned long rb_serial_t;
#define SERIALT2NUM ULONG2NUM
#endif

struct rb_classext_struct {
    struct st_table *iv_index_tbl;
    struct st_table *iv_tbl;
    struct st_table *const_tbl;
    rb_subclass_entry_t *subclasses;
    rb_subclass_entry_t **parent_subclasses;
    /**
     * In the case that this is an `ICLASS`, `module_subclasses` points to the link
     * in the module's `subclasses` list that indicates that the klass has been
     * included. Hopefully that makes sense.
     */
    rb_subclass_entry_t **module_subclasses;
    rb_serial_t class_serial;
    VALUE origin;
    VALUE refined_class;
    rb_alloc_func_t allocator;
};

struct method_table_wrapper {
    st_table *tbl;
    size_t serial;
};

/* class.c */
void rb_class_subclass_add(VALUE super, VALUE klass);
void rb_class_remove_from_super_subclasses(VALUE);

#define RCLASS_EXT(c) (RCLASS(c)->ptr)
#define RCLASS_IV_TBL(c) (RCLASS_EXT(c)->iv_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#define RCLASS_M_TBL_WRAPPER(c) (RCLASS(c)->m_tbl_wrapper)
#define RCLASS_M_TBL(c) (RCLASS_M_TBL_WRAPPER(c) ? RCLASS_M_TBL_WRAPPER(c)->tbl : 0)
#define RCLASS_IV_INDEX_TBL(c) (RCLASS_EXT(c)->iv_index_tbl)
#define RCLASS_ORIGIN(c) (RCLASS_EXT(c)->origin)
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)
#define RCLASS_SERIAL(c) (RCLASS_EXT(c)->class_serial)

static inline void
RCLASS_M_TBL_INIT(VALUE c)
{
    struct method_table_wrapper *wrapper;
    wrapper = ALLOC(struct method_table_wrapper);
    wrapper->tbl = st_init_numtable();
    wrapper->serial = 0;
    RCLASS_M_TBL_WRAPPER(c) = wrapper;
}

#undef RCLASS_SUPER
static inline VALUE
RCLASS_SUPER(VALUE klass)
{
    return RCLASS(klass)->super;
}

static inline VALUE
RCLASS_SET_SUPER(VALUE klass, VALUE super)
{
    if (super) {
	rb_class_remove_from_super_subclasses(klass);
	rb_class_subclass_add(super, klass);
    }
    RB_OBJ_WRITE(klass, &RCLASS(klass)->super, super);
    return super;
}

struct vtm; /* defined by timev.h */

/* array.c */
VALUE rb_ary_last(int, VALUE *, VALUE);
void rb_ary_set_len(VALUE, long);
void rb_ary_delete_same(VALUE, VALUE);

/* bignum.c */
VALUE rb_big_fdiv(VALUE x, VALUE y);
VALUE rb_big_uminus(VALUE x);
VALUE rb_integer_float_cmp(VALUE x, VALUE y);
VALUE rb_integer_float_eq(VALUE x, VALUE y);

/* class.c */
void rb_class_foreach_subclass(VALUE klass, void(*f)(VALUE));
void rb_class_detach_subclasses(VALUE);
void rb_class_detach_module_subclasses(VALUE);
void rb_class_remove_from_module_subclasses(VALUE);
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
void ruby_register_rollback_func_for_ensure(VALUE (*ensure_func)(ANYARGS), VALUE (*rollback_func)(ANYARGS));

/* debug.c */
PRINTF_ARGS(void ruby_debug_printf(const char*, ...), 1, 2);

/* dmyext.c */
void Init_ext(void);

/* encoding.c */
#ifdef RUBY_ENCODING_H
enum ruby_preserved_encindex {
    ENCINDEX_ASCII,
    ENCINDEX_UTF_8,
    ENCINDEX_US_ASCII,

    /* preserved indexes */
    ENCINDEX_UTF_16BE,
    ENCINDEX_UTF_16LE,
    ENCINDEX_UTF_32BE,
    ENCINDEX_UTF_32LE,
    ENCINDEX_UTF_16,
    ENCINDEX_UTF_32,
    ENCINDEX_UTF8_MAC,

    /* for old options of regexp */
    ENCINDEX_EUC_JP,
    ENCINDEX_Windows_31J,

    ENCINDEX_BUILTIN_MAX
};
#endif
#define rb_ascii8bit_encindex() ENCINDEX_ASCII
#define rb_utf8_encindex()      ENCINDEX_UTF_8
#define rb_usascii_encindex()   ENCINDEX_US_ASCII
ID rb_id_encoding(void);
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
VALUE rb_home_dir_of(VALUE user, VALUE result);
VALUE rb_default_home_dir(VALUE result);
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
NORETURN(void rb_syserr_fail_path_in(const char *func_name, int err, VALUE path));
# if defined __GNUC__ && __GNUC__ >= 4
#   pragma GCC visibility pop
# endif
# define rb_sys_fail_path(path) rb_sys_fail_path_in(RUBY_FUNCTION_NAME_STRING, path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
#else
# define rb_sys_fail_path(path) rb_sys_fail_str(path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_str((err), (path))
#endif

/* gc.c */
void Init_heap(void);
void *ruby_mimmalloc(size_t size);
void ruby_mimfree(void *ptr);
void rb_objspace_set_event_hook(const rb_event_flag_t event);
void rb_gc_writebarrier_remember_promoted(VALUE obj);
void ruby_gc_set_params(int safe_level);

#if defined(HAVE_MALLOC_USABLE_SIZE) || defined(HAVE_MALLOC_SIZE) || defined(_WIN32)
#define ruby_sized_xrealloc(ptr, new_size, old_size) ruby_xrealloc(ptr, new_size)
#define ruby_sized_xrealloc2(ptr, new_count, element_size, old_count) ruby_xrealloc(ptr, new_count, element_size)
#define ruby_sized_xfree(ptr, size) ruby_xfree(ptr)
#define SIZED_REALLOC_N(var,type,n,old_n) REALLOC_N(var, type, n)
#else
void *ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size) RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_sized_xrealloc2(void *ptr, size_t new_count, size_t element_size, size_t old_count) RUBY_ATTR_ALLOC_SIZE((2, 3));
void ruby_sized_xfree(void *x, size_t size);
#define SIZED_REALLOC_N(var,type,n,old_n) ((var)=(type*)ruby_sized_xrealloc((char*)(var), (n) * sizeof(type), (old_n) * sizeof(type)))
#endif

void rb_gc_resurrect(VALUE ptr);

/* hash.c */
struct st_table *rb_hash_tbl_raw(VALUE hash);
#define RHASH_TBL_RAW(h) rb_hash_tbl_raw(h)
VALUE rb_hash_keys(VALUE hash);
VALUE rb_hash_values(VALUE hash);
#define HASH_DELETED  FL_USER1
#define HASH_PROC_DEFAULT FL_USER2

/* inits.c */
void rb_call_inits(void);

/* io.c */
const char *ruby_get_inplace_mode(void);
void ruby_set_inplace_mode(const char *);
ssize_t rb_io_bufread(VALUE io, void *buf, size_t size);
void rb_stdio_set_default_encoding(void);
void rb_write_error_str(VALUE mesg);
VALUE rb_io_flush_raw(VALUE, int);

/* iseq.c */
VALUE rb_iseq_clone(VALUE iseqval, VALUE newcbase);
VALUE rb_iseq_path(VALUE iseqval);
VALUE rb_iseq_absolute_path(VALUE iseqval);
VALUE rb_iseq_label(VALUE iseqval);
VALUE rb_iseq_base_label(VALUE iseqval);
VALUE rb_iseq_first_lineno(VALUE iseqval);
VALUE rb_iseq_klass(VALUE iseqval); /* completely temporary fucntion */
VALUE rb_iseq_method_name(VALUE self);

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

#if USE_FLONUM
#define RUBY_BIT_ROTL(v, n) (((v) << (n)) | ((v) >> ((sizeof(v) * 8) - n)))
#define RUBY_BIT_ROTR(v, n) (((v) >> (n)) | ((v) << ((sizeof(v) * 8) - n)))
#endif

static inline double
rb_float_value_inline(VALUE v)
{
#if USE_FLONUM
    if (FLONUM_P(v)) {
	if (v != (VALUE)0x8000000000000002) { /* LIKELY */
	    union {
		double d;
		VALUE v;
	    } t;

	    VALUE b63 = (v >> 63);
	    /* e: xx1... -> 011... */
	    /*    xx0... -> 100... */
	    /*      ^b63           */
	    t.v = RUBY_BIT_ROTR((2 - b63) | (v & ~0x03), 3);
	    return t.d;
	}
	else {
	    return 0.0;
	}
    }
#endif
    return ((struct RFloat *)v)->float_value;
}

static inline VALUE
rb_float_new_inline(double d)
{
#if USE_FLONUM
    union {
	double d;
	VALUE v;
    } t;
    int bits;

    t.d = d;
    bits = (int)((VALUE)(t.v >> 60) & 0x7);
    /* bits contains 3 bits of b62..b60. */
    /* bits - 3 = */
    /*   b011 -> b000 */
    /*   b100 -> b001 */

    if (t.v != 0x3000000000000000 /* 1.72723e-77 */ &&
	!((bits-3) & ~0x01)) {
	return (RUBY_BIT_ROTL(t.v, 3) & ~(VALUE)0x01) | 0x02;
    }
    else if (t.v == (VALUE)0) {
	/* +0.0 */
	return 0x8000000000000002;
    }
    /* out of range */
#endif
    return rb_float_new_in_heap(d);
}

#define rb_float_value(v) rb_float_value_inline(v)
#define rb_float_new(d)   rb_float_new_inline(d)

/* object.c */
VALUE rb_obj_equal(VALUE obj1, VALUE obj2);
VALUE rb_class_search_ancestor(VALUE klass, VALUE super);

struct RBasicRaw {
    VALUE flags;
    VALUE klass;
};

#define RBASIC_CLEAR_CLASS(obj)        (((struct RBasicRaw *)((VALUE)(obj)))->klass = 0)
#define RBASIC_SET_CLASS_RAW(obj, cls) (((struct RBasicRaw *)((VALUE)(obj)))->klass = (cls))
#define RBASIC_SET_CLASS(obj, cls)     do { \
    VALUE _obj_ = (obj); \
    RB_OBJ_WRITE(_obj_, &((struct RBasicRaw *)(_obj_))->klass, cls); \
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
void rb_gc_mark_symbols(int full_mark);

/* proc.c */
VALUE rb_proc_location(VALUE self);
st_index_t rb_hash_proc(st_index_t hash, VALUE proc);
int rb_block_arity(void);

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
VALUE rb_fstring(VALUE);
int rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p);
int rb_str_symname_p(VALUE);
VALUE rb_str_quote_unprintable(VALUE);
VALUE rb_id_quote_unprintable(ID);
#define QUOTE(str) rb_str_quote_unprintable(str)
#define QUOTE_ID(id) rb_id_quote_unprintable(id)
void rb_str_fill_terminator(VALUE str, const int termlen);
VALUE rb_str_locktmp_ensure(VALUE str, VALUE (*func)(VALUE), VALUE arg);
#ifdef RUBY_ENCODING_H
VALUE rb_external_str_with_enc(VALUE str, rb_encoding *eenc);
#endif
#define STR_NOEMBED FL_USER1
#define STR_SHARED  FL_USER2 /* = ELTS_SHARED */
#define STR_ASSOC   FL_USER3
#define STR_SHARED_P(s) FL_ALL((s), STR_NOEMBED|ELTS_SHARED)
#define STR_ASSOC_P(s)  FL_ALL((s), STR_NOEMBED|STR_ASSOC)
#define STR_NOCAPA  (STR_NOEMBED|ELTS_SHARED|STR_ASSOC)
#define STR_NOCAPA_P(s) (FL_TEST((s),STR_NOEMBED) && FL_ANY((s),ELTS_SHARED|STR_ASSOC))
#define STR_EMBED_P(str) (!FL_TEST((str), STR_NOEMBED))
#define is_ascii_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT)
#define is_broken_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_BROKEN)

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

/* vm_insnhelper.h */
rb_serial_t rb_next_class_serial(void);

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
VALUE rb_check_block_call(VALUE, ID, int, const VALUE *, rb_block_call_func_t, VALUE);
typedef void rb_check_funcall_hook(int, VALUE, ID, int, const VALUE *, VALUE);
VALUE rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
				 rb_check_funcall_hook *hook, VALUE arg);
VALUE rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, int *stateptr);

/* vm_insnhelper.c */
VALUE rb_equal_opt(VALUE obj1, VALUE obj2);
int rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *);
VALUE rb_extract_keywords(VALUE *orighash);

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
VALUE rb_backtrace_to_location_ary(VALUE obj);
void rb_backtrace_print_to(VALUE output);
VALUE rb_vm_backtrace_object(void);

RUBY_SYMBOL_EXPORT_BEGIN
const char *rb_objspace_data_type_name(VALUE obj);

/* Temporary.  This API will be removed (renamed). */
VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);

/* bignum.c */
VALUE rb_big_mul_normal(VALUE x, VALUE y);
VALUE rb_big_mul_balance(VALUE x, VALUE y);
VALUE rb_big_mul_karatsuba(VALUE x, VALUE y);
VALUE rb_big_mul_toom3(VALUE x, VALUE y);
VALUE rb_big_sq_fast(VALUE x);
VALUE rb_big_divrem_normal(VALUE x, VALUE y);
VALUE rb_big2str_poweroftwo(VALUE x, int base);
VALUE rb_big2str_generic(VALUE x, int base);
VALUE rb_str2big_poweroftwo(VALUE arg, int base, int badcheck);
VALUE rb_str2big_normal(VALUE arg, int base, int badcheck);
VALUE rb_str2big_karatsuba(VALUE arg, int base, int badcheck);
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
VALUE rb_big_mul_gmp(VALUE x, VALUE y);
VALUE rb_big_divrem_gmp(VALUE x, VALUE y);
VALUE rb_big2str_gmp(VALUE x, int base);
VALUE rb_str2big_gmp(VALUE arg, int base, int badcheck);
#endif

/* error.c */
int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);

/* file.c */
#ifdef __APPLE__
VALUE rb_str_normalize_ospath(const char *ptr, long len);
#endif

/* io.c */
void rb_maygvl_fd_fix_cloexec(int fd);

/* numeric.c */
VALUE rb_int_positive_pow(long x, unsigned long y);

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

/* rational.c */
VALUE rb_gcd_normal(VALUE self, VALUE other);
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
VALUE rb_gcd_gmp(VALUE x, VALUE y);
#endif

/* util.c */
extern const signed char ruby_digit36_to_number_table[];

/* variable.c */
void rb_gc_mark_global_tbl(void);
void rb_mark_generic_ivar(VALUE);
void rb_mark_generic_ivar_tbl(void);

int rb_st_insert_id_and_value(VALUE obj, st_table *tbl, ID key, VALUE value);
st_table *rb_st_copy(VALUE obj, struct st_table *orig_tbl);

/* gc.c */
size_t rb_obj_memsize_of(VALUE);
#define RB_OBJ_GC_FLAGS_MAX 5
size_t rb_obj_gc_flags(VALUE, ID[], size_t);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_INTERNAL_H */
