#ifndef RUBY_RUBYPARSER_H
#define RUBY_RUBYPARSER_H 1
/*
 * This is a header file for librubyparser interface
 */

#include <stdarg.h> /* for va_list */

#ifdef UNIVERSAL_PARSER

#define rb_encoding void
#define OnigCodePoint unsigned int
#include "parser_st.h"
#ifndef RUBY_RUBY_H
#include "parser_value.h"
#endif

#else

#include "ruby/encoding.h"

#endif

/*
 * AST Node
 */
enum node_type {
    NODE_SCOPE,
    NODE_BLOCK,
    NODE_IF,
    NODE_UNLESS,
    NODE_CASE,
    NODE_CASE2,
    NODE_CASE3,
    NODE_WHEN,
    NODE_IN,
    NODE_WHILE,
    NODE_UNTIL,
    NODE_ITER,
    NODE_FOR,
    NODE_FOR_MASGN,
    NODE_BREAK,
    NODE_NEXT,
    NODE_REDO,
    NODE_RETRY,
    NODE_BEGIN,
    NODE_RESCUE,
    NODE_RESBODY,
    NODE_ENSURE,
    NODE_AND,
    NODE_OR,
    NODE_MASGN,
    NODE_LASGN,
    NODE_DASGN,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CDECL,
    NODE_CVASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_OP_ASGN_AND,
    NODE_OP_ASGN_OR,
    NODE_OP_CDECL,
    NODE_CALL,
    NODE_OPCALL,
    NODE_FCALL,
    NODE_VCALL,
    NODE_QCALL,
    NODE_SUPER,
    NODE_ZSUPER,
    NODE_LIST,
    NODE_ZLIST,
    NODE_VALUES,
    NODE_HASH,
    NODE_RETURN,
    NODE_YIELD,
    NODE_LVAR,
    NODE_DVAR,
    NODE_GVAR,
    NODE_IVAR,
    NODE_CONST,
    NODE_CVAR,
    NODE_NTH_REF,
    NODE_BACK_REF,
    NODE_MATCH,
    NODE_MATCH2,
    NODE_MATCH3,
    NODE_LIT,
    NODE_STR,
    NODE_DSTR,
    NODE_XSTR,
    NODE_DXSTR,
    NODE_EVSTR,
    NODE_DREGX,
    NODE_ONCE,
    NODE_ARGS,
    NODE_ARGS_AUX,
    NODE_OPT_ARG,
    NODE_KW_ARG,
    NODE_POSTARG,
    NODE_ARGSCAT,
    NODE_ARGSPUSH,
    NODE_SPLAT,
    NODE_BLOCK_PASS,
    NODE_DEFN,
    NODE_DEFS,
    NODE_ALIAS,
    NODE_VALIAS,
    NODE_UNDEF,
    NODE_CLASS,
    NODE_MODULE,
    NODE_SCLASS,
    NODE_COLON2,
    NODE_COLON3,
    NODE_DOT2,
    NODE_DOT3,
    NODE_FLIP2,
    NODE_FLIP3,
    NODE_SELF,
    NODE_NIL,
    NODE_TRUE,
    NODE_FALSE,
    NODE_ERRINFO,
    NODE_DEFINED,
    NODE_POSTEXE,
    NODE_DSYM,
    NODE_ATTRASGN,
    NODE_LAMBDA,
    NODE_ARYPTN,
    NODE_HSHPTN,
    NODE_FNDPTN,
    NODE_ERROR,
    NODE_LAST
};


#define nd_head  u1.node
#define nd_alen  u2.argc
#define nd_next  u3.node

#define nd_cond  u1.node
#define nd_body  u2.node
#define nd_else  u3.node

#define nd_resq  u2.node
#define nd_ensr  u3.node

#define nd_1st   u1.node
#define nd_2nd   u2.node

#define nd_stts  u1.node

#define nd_vid   u1.id

#define nd_var   u1.node
#define nd_iter  u3.node

#define nd_value u2.node
#define nd_aid   u3.id

#define nd_lit   u1.value

#define nd_recv  u1.node
#define nd_mid   u2.id
#define nd_args  u3.node
#define nd_ainfo u3.args

#define nd_defn  u3.node

#define nd_cpath u1.node
#define nd_super u3.node

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state

#define nd_nth   u2.argc

#define nd_alias  u1.id
#define nd_orig   u2.id
#define nd_undef  u2.node

#define nd_brace u2.argc

#define nd_pconst     u1.node
#define nd_pkwargs    u2.node
#define nd_pkwrestarg u3.node

#define nd_apinfo u3.apinfo

#define nd_fpinfo u3.fpinfo

// for NODE_SCOPE
#define nd_tbl   u1.tbl

// for NODE_ARGS_AUX
#define nd_pid   u1.id
#define nd_plen  u2.argc
#define nd_cflag u2.id

// for ripper
#define nd_cval  u3.value
#define nd_rval  u2.value
#define nd_tag   u1.id

#ifndef FLEX_ARY_LEN
/* From internal/compilers.h */
/* A macro for defining a flexible array, like: VALUE ary[FLEX_ARY_LEN]; */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
# define FLEX_ARY_LEN   /* VALUE ary[]; */
#elif defined(__GNUC__) && !defined(__STRICT_ANSI__)
# define FLEX_ARY_LEN 0 /* VALUE ary[0]; */
#else
# define FLEX_ARY_LEN 1 /* VALUE ary[1]; */
#endif
#endif

typedef struct rb_ast_id_table {
    int size;
    ID ids[FLEX_ARY_LEN];
} rb_ast_id_table_t;

typedef struct rb_code_position_struct {
    int lineno;
    int column;
} rb_code_position_t;

typedef struct rb_code_location_struct {
    rb_code_position_t beg_pos;
    rb_code_position_t end_pos;
} rb_code_location_t;

typedef struct RNode {
    VALUE flags;
    union {
        struct RNode *node;
        ID id;
        VALUE value;
        rb_ast_id_table_t *tbl;
    } u1;
    union {
        struct RNode *node;
        ID id;
        long argc;
        VALUE value;
    } u2;
    union {
        struct RNode *node;
        ID id;
        long state;
        struct rb_args_info *args;
        struct rb_ary_pattern_info *apinfo;
        struct rb_fnd_pattern_info *fpinfo;
        VALUE value;
    } u3;
    rb_code_location_t nd_loc;
    int node_id;
} NODE;

/* FL     : 0..4: T_TYPES, 5: KEEP_WB, 6: PROMOTED, 7: FINALIZE, 8: UNUSED, 9: UNUSED, 10: EXIVAR, 11: FREEZE */
/* NODE_FL: 0..4: T_TYPES, 5: KEEP_WB, 6: PROMOTED, 7: NODE_FL_NEWLINE,
 *          8..14: nd_type,
 *          15..: nd_line
 */
#define NODE_FL_NEWLINE              (((VALUE)1)<<7)

#define NODE_TYPESHIFT 8
#define NODE_TYPEMASK  (((VALUE)0x7f)<<NODE_TYPESHIFT)

#define nd_type(n) ((int) (((n)->flags & NODE_TYPEMASK)>>NODE_TYPESHIFT))
#define nd_set_type(n,t) \
    rb_node_set_type(n, t)
#define nd_init_type(n,t) \
    (n)->flags=(((n)->flags&~NODE_TYPEMASK)|((((unsigned long)(t))<<NODE_TYPESHIFT)&NODE_TYPEMASK))

struct rb_args_info {
    NODE *pre_init;
    NODE *post_init;

    int pre_args_num;  /* count of mandatory pre-arguments */
    int post_args_num; /* count of mandatory post-arguments */

    ID first_post_arg;

    ID rest_arg;
    ID block_arg;

    NODE *kw_args;
    NODE *kw_rest_arg;

    NODE *opt_args;
    unsigned int no_kwarg: 1;
    unsigned int ruby2_keywords: 1;
    unsigned int forwarding: 1;

    VALUE imemo;
};

struct rb_ary_pattern_info {
    NODE *pre_args;
    NODE *rest_arg;
    NODE *post_args;
};

struct rb_fnd_pattern_info {
    NODE *pre_rest_arg;
    NODE *args;
    NODE *post_rest_arg;
};

typedef struct node_buffer_struct node_buffer_t;
/* T_IMEMO/ast */
typedef struct rb_ast_body_struct {
    const NODE *root;
    VALUE script_lines;
    // script_lines is either:
    // - a Fixnum that represents the line count of the original source, or
    // - an Array that contains the lines of the original source
    signed int frozen_string_literal:2; /* -1: not specified, 0: false, 1: true */
    signed int coverage_enabled:2; /* -1: not specified, 0: false, 1: true */
} rb_ast_body_t;
typedef struct rb_ast_struct {
    VALUE flags;
    node_buffer_t *node_buffer;
    rb_ast_body_t body;
} rb_ast_t;



/*
 * Parser Interface
 */


typedef struct parser_params rb_parser_t;
#ifndef INTERNAL_IMEMO_H
typedef struct rb_imemo_tmpbuf_struct rb_imemo_tmpbuf_t;
#endif

#ifdef UNIVERSAL_PARSER
typedef struct rb_parser_config_struct {
    /*
     * Reference counter.
     *   This is needed because both parser and ast refer
     *   same config pointer.
     *   We can remove this, once decuple parser and ast from Ruby GC.
     */
    int counter;

    /* Memory */
    void *(*malloc)(size_t size);
    void *(*calloc)(size_t number, size_t size);
    void *(*realloc)(void *ptr, size_t newsiz);
    void (*free)(void *ptr);
    void *(*alloc_n)(size_t nelems, size_t elemsiz);
    void *(*alloc)(size_t elemsiz);
    void *(*realloc_n)(void *ptr, size_t newelems, size_t newsiz);
    void *(*zalloc)(size_t elemsiz);
    void *(*rb_memmove)(void *dest, const void *src, size_t t, size_t n);
    void *(*nonempty_memcpy)(void *dest, const void *src, size_t t, size_t n);
    void *(*xmalloc_mul_add)(size_t x, size_t y, size_t z);

    /* imemo */
    // TODO: Should it return `rb_strterm_t *'?
    VALUE (*new_strterm)(VALUE v1, VALUE v2, VALUE v3, VALUE v0, int heredoc);
    int (*strterm_is_heredoc)(VALUE strterm);
    VALUE (*tmpbuf_auto_free_pointer)(void);
    void *(*tmpbuf_set_ptr)(VALUE v, void *ptr);
    rb_imemo_tmpbuf_t *(*tmpbuf_parser_heap)(void *buf, rb_imemo_tmpbuf_t *old_heap, size_t cnt);
    rb_ast_t *(*ast_new)(VALUE nb);

    // VALUE rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg);
    VALUE (*compile_callback)(VALUE (*func)(VALUE), VALUE arg);
    NODE *(*reg_named_capture_assign)(struct parser_params* p, VALUE regexp, const rb_code_location_t *loc);

    /* Object */
    VALUE (*obj_freeze)(VALUE obj);
    VALUE (*obj_hide)(VALUE obj);
    int (*obj_frozen)(VALUE obj);
    int (*type_p)(VALUE, int);
    void (*obj_freeze_raw)(VALUE obj);

    int (*fixnum_p)(VALUE);
    int (*symbol_p)(VALUE);

    /* Variable */
    VALUE (*attr_get)(VALUE obj, ID id);

    /* Array */
    VALUE (*ary_new)(void);
    VALUE (*ary_push)(VALUE ary, VALUE elem);
    VALUE (*ary_new_from_args)(long n, ...);
    VALUE (*ary_pop)(VALUE ary);
    VALUE (*ary_last)(int argc, const VALUE *argv, VALUE ary);
    VALUE (*ary_unshift)(VALUE ary, VALUE item);
    VALUE (*ary_new2)(long capa); // ary_new_capa
    VALUE (*ary_entry)(VALUE ary, long offset);
    VALUE (*ary_join)(VALUE ary, VALUE sep);
    VALUE (*ary_reverse)(VALUE ary);
    VALUE (*ary_clear)(VALUE ary);
    long (*array_len)(VALUE a);
    VALUE (*array_aref)(VALUE, long);

    /* Symbol */
    VALUE (*sym_intern_ascii_cstr)(const char *ptr);
    ID (*make_temporary_id)(size_t n);
    int (*is_local_id)(ID);
    int (*is_attrset_id)(ID);
    int (*is_global_name_punct)(const int c);
    int (*id_type)(ID id);
    ID (*id_attrset)(ID);
    ID (*intern)(const char *name);
    ID (*intern2)(const char *name, long len);
    ID (*intern3)(const char *name, long len, rb_encoding *enc);
    ID (*intern_str)(VALUE str);
    int (*is_notop_id)(ID);
    int (*enc_symname_type)(const char *name, long len, rb_encoding *enc, unsigned int allowed_attrset);
    VALUE (*str_intern)(VALUE str);
    const char *(*id2name)(ID id);
    VALUE (*id2str)(ID id);
    VALUE (*id2sym)(ID x);
    ID (*sym2id)(VALUE sym);

    /* String */
    VALUE (*str_catf)(VALUE str, const char *format, ...);
    VALUE (*str_cat_cstr)(VALUE str, const char *ptr);
    VALUE (*str_subseq)(VALUE str, long beg, long len);
    VALUE (*str_dup)(VALUE str);
    VALUE (*str_new_frozen)(VALUE orig);
    VALUE (*str_buf_new)(long capa);
    VALUE (*str_buf_cat)(VALUE, const char*, long);
    void (*str_modify)(VALUE str);
    void (*str_set_len)(VALUE str, long len);
    VALUE (*str_cat)(VALUE str, const char *ptr, long len);
    VALUE (*str_resize)(VALUE str, long len);
    VALUE (*str_new)(const char *ptr, long len);
    VALUE (*str_new_cstr)(const char *ptr);
    VALUE (*fstring)(VALUE);
    int (*is_ascii_string)(VALUE str);
    VALUE (*enc_str_new)(const char *ptr, long len, rb_encoding *enc);
    VALUE (*enc_str_buf_cat)(VALUE str, const char *ptr, long len, rb_encoding *enc);
    VALUE (*str_buf_append)(VALUE str, VALUE str2);
    VALUE (*str_vcatf)(VALUE str, const char *fmt, va_list ap);
    char *(*string_value_cstr)(volatile VALUE *ptr);
    VALUE (*rb_sprintf)(const char *format, ...);
    char *(*rstring_ptr)(VALUE str);
    char *(*rstring_end)(VALUE str);
    long (*rstring_len)(VALUE str);
    VALUE (*filesystem_str_new_cstr)(const char *ptr);
    VALUE (*obj_as_string)(VALUE);

    /* Hash */
    VALUE (*hash_clear)(VALUE hash);
    VALUE (*hash_new)(void);
    VALUE (*hash_aset)(VALUE hash, VALUE key, VALUE val);
    VALUE (*hash_lookup)(VALUE hash, VALUE key);
    VALUE (*ident_hash_new)(void);

    /* Fixnum */
    VALUE (*int2fix)(long i);

    /* Bignum */
    void (*bignum_negate)(VALUE b);
    VALUE (*big_norm)(VALUE x);
    VALUE (*cstr_to_inum)(const char *str, int base, int badcheck);

    /* Float */
    VALUE (*float_new)(double d);
    double (*float_value)(VALUE v);

    /* Numeric */
    int (*num2int)(VALUE val);
    VALUE (*int_positive_pow)(long x, unsigned long y);
    VALUE (*int2num)(int v);
    long (*fix2long)(VALUE val);

    /* Rational */
    VALUE (*rational_new)(VALUE x, VALUE y);
    VALUE (*rational_raw1)(VALUE x);
    void (*rational_set_num)(VALUE r, VALUE n);
    VALUE (*rational_get_num)(VALUE obj);

    /* Complex */
    VALUE (*complex_raw)(VALUE x, VALUE y);
    void (*rcomplex_set_real)(VALUE cmp, VALUE r);
    void (*rcomplex_set_imag)(VALUE cmp, VALUE i);
    VALUE (*rcomplex_get_real)(VALUE obj);
    VALUE (*rcomplex_get_imag)(VALUE obj);

    /* IO */
    int (*stderr_tty_p)(void);
    void (*write_error_str)(VALUE mesg);
    VALUE (*default_rs)(void);
    VALUE (*io_write)(VALUE io, VALUE str);
    VALUE (*io_flush)(VALUE io);
    VALUE (*io_puts)(int argc, const VALUE *argv, VALUE out);
    VALUE (*io_gets_internal)(VALUE io);

    /* IO (Ractor) */
    VALUE (*debug_output_stdout)(void);
    VALUE (*debug_output_stderr)(void);

    /* Encoding */
    int (*is_usascii_enc)(rb_encoding *enc);
    int (*enc_isalnum)(OnigCodePoint c, rb_encoding *enc);
    int (*enc_precise_mbclen)(const char *p, const char *e, rb_encoding *enc);
    int (*mbclen_charfound_p)(int len);
    const char *(*enc_name)(rb_encoding *enc);
    char *(*enc_prev_char)(const char *s, const char *p, const char *e, rb_encoding *enc);
    rb_encoding* (*enc_get)(VALUE obj);
    int (*enc_asciicompat)(rb_encoding *enc);
    rb_encoding *(*utf8_encoding)(void);
    VALUE (*enc_associate)(VALUE obj, rb_encoding *enc);
    rb_encoding *(*ascii8bit_encoding)(void);
    int (*enc_codelen)(int c, rb_encoding *enc);
    int (*enc_mbcput)(unsigned int c, void *buf, rb_encoding *enc);
    int (*char_to_option_kcode)(int c, int *option, int *kcode);
    int (*ascii8bit_encindex)(void);
    int (*enc_find_index)(const char *name);
    rb_encoding *(*enc_from_index)(int idx);
    VALUE (*enc_associate_index)(VALUE obj, int encindex);
    int (*enc_isspace)(OnigCodePoint c, rb_encoding *enc);
    int enc_coderange_7bit;
    int enc_coderange_unknown;
    rb_encoding *(*enc_compatible)(VALUE str1, VALUE str2);
    VALUE (*enc_from_encoding)(rb_encoding *enc);
    int (*encoding_get)(VALUE obj);
    void (*encoding_set)(VALUE obj, int encindex);
    int (*encoding_is_ascii8bit)(VALUE obj);
    rb_encoding *(*usascii_encoding)(void);

    /* Ractor */
    VALUE (*ractor_make_shareable)(VALUE obj);

    /* Compile */
    // int rb_local_defined(ID id, const rb_iseq_t *iseq);
    int (*local_defined)(ID, const void*);
    // int rb_dvar_defined(ID id, const rb_iseq_t *iseq);
    int (*dvar_defined)(ID, const void*);

    /* Compile (parse.y) */
    int (*literal_cmp)(VALUE val, VALUE lit);
    parser_st_index_t (*literal_hash)(VALUE a);

    /* Error (Exception) */
    const char *(*builtin_class_name)(VALUE x);
    VALUE (*syntax_error_append)(VALUE, VALUE, int, int, rb_encoding*, const char*, va_list);
    void (*raise)(VALUE exc, const char *fmt, ...);
    VALUE (*syntax_error_new)(void);

    /* Eval */
    VALUE (*errinfo)(void);
    void (*set_errinfo)(VALUE err);
    void (*exc_raise)(VALUE mesg);
    VALUE (*make_exception)(int argc, const VALUE *argv);

    /* GC */
    void (*sized_xfree)(void *x, size_t size);
    void *(*sized_realloc_n)(void *ptr, size_t new_count, size_t element_size, size_t old_count);
    VALUE (*obj_write)(VALUE, VALUE *, VALUE);
    VALUE (*obj_written)(VALUE, VALUE, VALUE);
    void (*gc_register_mark_object)(VALUE object);
    void (*gc_guard)(VALUE);
    void (*gc_mark)(VALUE);
    void (*gc_mark_movable)(VALUE ptr);
    VALUE (*gc_location)(VALUE value);

    /* Re */
    VALUE (*reg_compile)(VALUE str, int options, const char *sourcefile, int sourceline);
    VALUE (*reg_check_preprocess)(VALUE str);
    int (*memcicmp)(const void *x, const void *y, long len);

    /* Error */
    void (*compile_warn)(const char *file, int line, const char *fmt, ...);
    void (*compile_warning)(const char *file, int line, const char *fmt, ...);
    void (*bug)(const char *fmt, ...);
    void (*fatal)(const char *fmt, ...);
    VALUE (*verbose)(void);

    /* VM */
    VALUE (*make_backtrace)(void);

    /* Util */
    unsigned long (*scan_hex)(const char *start, size_t len, size_t *retlen);
    unsigned long (*scan_oct)(const char *start, size_t len, size_t *retlen);
    unsigned long (*scan_digits)(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);
    double (*strtod)(const char *s00, char **se);

    /* Misc */
    VALUE (*rbool)(VALUE);
    int (*undef_p)(VALUE);
    int (*rtest)(VALUE obj);
    int (*nil_p)(VALUE obj);
    int (*flonum_p)(VALUE obj);
    VALUE qnil;
    VALUE qtrue;
    VALUE qfalse;
    VALUE qundef;
    VALUE eArgError;
    VALUE mRubyVMFrozenCore;
    int (*long2int)(long);
    int (*special_const_p)(VALUE);
    int (*builtin_type)(VALUE);

    VALUE (*node_case_when_optimizable_literal)(const NODE *const node);

    /* For Ripper */
    VALUE (*static_id2sym)(ID id);
    long (*str_coderange_scan_restartable)(const char *s, const char *e, rb_encoding *enc, int *cr);
} rb_parser_config_t;

#undef rb_encoding
#undef OnigCodePoint
#endif /* UNIVERSAL_PARSER */

RUBY_SYMBOL_EXPORT_BEGIN
void rb_ruby_parser_free(void *ptr);
rb_ast_t* rb_ruby_parser_compile_string(rb_parser_t *p, const char *f, VALUE s, int line);

#ifdef UNIVERSAL_PARSER
rb_parser_config_t *rb_ruby_parser_config_new(void *(*malloc)(size_t size));
void rb_ruby_parser_config_free(rb_parser_config_t *config);
rb_parser_t *rb_ruby_parser_allocate(rb_parser_config_t *config);
rb_parser_t *rb_ruby_parser_new(rb_parser_config_t *config);
#endif
RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_RUBYPARSER_H */
