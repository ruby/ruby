/* This is a wrapper for parse.y */

#include "internal/re.h"
#include "internal/ruby_parser.h"

#include "node.h"
#include "rubyparser.h"
#include "internal/error.h"

#ifdef UNIVERSAL_PARSER

#include "internal.h"
#include "internal/array.h"
#include "internal/bignum.h"
#include "internal/compile.h"
#include "internal/complex.h"
#include "internal/encoding.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/io.h"
#include "internal/parse.h"
#include "internal/rational.h"
#include "internal/re.h"
#include "internal/string.h"
#include "internal/symbol.h"
#include "internal/thread.h"

#include "ruby/ractor.h"
#include "ruby/ruby.h"
#include "ruby/util.h"
#include "internal.h"
#include "vm_core.h"
#include "symbol.h"

struct ruby_parser {
    rb_parser_t *parser_params;
};

static void
parser_mark(void *ptr)
{
    struct ruby_parser *parser = (struct ruby_parser*)ptr;
    rb_ruby_parser_mark(parser->parser_params);
}

static void
parser_free(void *ptr)
{
    struct ruby_parser *parser = (struct ruby_parser*)ptr;
    rb_ruby_parser_free(parser->parser_params);
}

static size_t
parser_memsize(const void *ptr)
{
    struct ruby_parser *parser = (struct ruby_parser*)ptr;
    return rb_ruby_parser_memsize(parser->parser_params);
}

static const rb_data_type_t ruby_parser_data_type = {
    "parser",
    {
        parser_mark,
        parser_free,
        parser_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static int
is_ascii_string2(VALUE str)
{
    return is_ascii_string(str);
}

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 6, 0)
static VALUE
syntax_error_append(VALUE exc, VALUE file, int line, int column,
                       void *enc, const char *fmt, va_list args)
{
    return rb_syntax_error_append(exc, file, line, column, (rb_encoding *)enc, fmt, args);
}

static int
local_defined(ID id, const void *p)
{
    return rb_local_defined(id, (const rb_iseq_t *)p);
}

static int
dvar_defined(ID id, const void *p)
{
    return rb_dvar_defined(id, (const rb_iseq_t *)p);
}

static int
is_usascii_enc(void *enc)
{
    return rb_is_usascii_enc((rb_encoding *)enc);
}

static int
is_local_id2(ID id)
{
    return is_local_id(id);
}

static int
is_attrset_id2(ID id)
{
    return is_attrset_id(id);
}

static int
is_notop_id2(ID id)
{
    return is_notop_id(id);
}

static VALUE
enc_str_new(const char *ptr, long len, void *enc)
{
    return rb_enc_str_new(ptr, len, (rb_encoding *)enc);
}

static int
enc_isalnum(OnigCodePoint c, void *enc)
{
    return rb_enc_isalnum(c, (rb_encoding *)enc);
}

static int
enc_precise_mbclen(const char *p, const char *e, void *enc)
{
    return rb_enc_precise_mbclen(p, e, (rb_encoding *)enc);
}

static int
mbclen_charfound_p(int len)
{
    return MBCLEN_CHARFOUND_P(len);
}

static int
mbclen_charfound_len(int len)
{
    return MBCLEN_CHARFOUND_LEN(len);
}

static const char *
enc_name(void *enc)
{
    return rb_enc_name((rb_encoding *)enc);
}

static char *
enc_prev_char(const char *s, const char *p, const char *e, void *enc)
{
    return rb_enc_prev_char(s, p, e, (rb_encoding *)enc);
}

static void *
enc_get(VALUE obj)
{
    return (void *)rb_enc_get(obj);
}

static int
enc_asciicompat(void *enc)
{
    return rb_enc_asciicompat((rb_encoding *)enc);
}

static void *
utf8_encoding(void)
{
    return (void *)rb_utf8_encoding();
}

static VALUE
enc_associate(VALUE obj, void *enc)
{
    return rb_enc_associate(obj, (rb_encoding *)enc);
}

static void *
ascii8bit_encoding(void)
{
    return (void *)rb_ascii8bit_encoding();
}

static int
enc_codelen(int c, void *enc)
{
    return rb_enc_codelen(c, (rb_encoding *)enc);
}

static VALUE
enc_str_buf_cat(VALUE str, const char *ptr, long len, void *enc)
{
    return rb_enc_str_buf_cat(str, ptr, len, (rb_encoding *)enc);
}

static int
enc_mbcput(unsigned int c, void *buf, void *enc)
{
    return rb_enc_mbcput(c, buf, (rb_encoding *)enc);
}

static void *
enc_from_index(int idx)
{
    return (void *)rb_enc_from_index(idx);
}

static int
enc_isspace(OnigCodePoint c, void *enc)
{
    return rb_enc_isspace(c, (rb_encoding *)enc);
}

static ID
intern3(const char *name, long len, void *enc)
{
    return rb_intern3(name, len, (rb_encoding *)enc);
}

static void *
enc_compatible(VALUE str1, VALUE str2)
{
    return (void *)rb_enc_compatible(str1, str2);
}

static VALUE
enc_from_encoding(void *enc)
{
    return rb_enc_from_encoding((rb_encoding *)enc);
}

static int
encoding_is_ascii8bit(VALUE obj)
{
    return ENCODING_IS_ASCII8BIT(obj);
}

static void *
usascii_encoding(void)
{
    return (void *)rb_usascii_encoding();
}

static int
enc_symname_type(const char *name, long len, void *enc, unsigned int allowed_attrset)
{
    return rb_enc_symname_type(name, len, (rb_encoding *)enc, allowed_attrset);
}

typedef struct {
    struct parser_params *parser;
    rb_encoding *enc;
    NODE *succ_block;
    const rb_code_location_t *loc;
} reg_named_capture_assign_t;

static int
reg_named_capture_assign_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg0)
{
    reg_named_capture_assign_t *arg = (reg_named_capture_assign_t*)arg0;
    struct parser_params* p = arg->parser;
    rb_encoding *enc = arg->enc;
    const rb_code_location_t *loc = arg->loc;
    long len = name_end - name;
    const char *s = (const char *)name;

    return rb_reg_named_capture_assign_iter_impl(p, s, len, (void *)enc, &arg->succ_block, loc);
}

static NODE *
reg_named_capture_assign(struct parser_params* p, VALUE regexp, const rb_code_location_t *loc)
{
    reg_named_capture_assign_t arg;

    arg.parser = p;
    arg.enc = rb_enc_get(regexp);
    arg.succ_block = 0;
    arg.loc = loc;
    onig_foreach_name(RREGEXP_PTR(regexp), reg_named_capture_assign_iter, &arg);

    if (!arg.succ_block) return 0;
    return RNODE_BLOCK(arg.succ_block)->nd_next;
}

static VALUE
rbool(VALUE v)
{
    return RBOOL(v);
}

static int
rtest(VALUE obj)
{
    return (int)RB_TEST(obj);
}

static int
nil_p(VALUE obj)
{
    return (int)NIL_P(obj);
}

static VALUE
syntax_error_new(void)
{
    return rb_class_new_instance(0, 0, rb_eSyntaxError);
}

static VALUE
obj_write(VALUE old, VALUE *slot, VALUE young)
{
    return RB_OBJ_WRITE(old, slot, young);
}

static VALUE
default_rs(void)
{
    return rb_default_rs;
}

static void *
memmove2(void *dest, const void *src, size_t t, size_t n)
{
    return memmove(dest, src, rbimpl_size_mul_or_raise(t, n));
}

static void *
nonempty_memcpy(void *dest, const void *src, size_t t, size_t n)
{
    return ruby_nonempty_memcpy(dest, src, rbimpl_size_mul_or_raise(t, n));
}

static VALUE
ruby_verbose2(void)
{
    return ruby_verbose;
}

static int *
rb_errno_ptr2(void)
{
    return rb_errno_ptr();
}

static void *
zalloc(size_t elemsiz)
{
    return ruby_xcalloc(1, elemsiz);
}

static void
gc_guard(VALUE obj)
{
    RB_GC_GUARD(obj);
}

static VALUE
arg_error(void)
{
    return rb_eArgError;
}

static rb_ast_t *
ast_new(VALUE nb)
{
    return IMEMO_NEW(rb_ast_t, imemo_ast, nb);
}

static VALUE
static_id2sym(ID id)
{
    return (((VALUE)(id)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG);
}

static long
str_coderange_scan_restartable(const char *s, const char *e, void *enc, int *cr)
{
    return rb_str_coderange_scan_restartable(s, e, (rb_encoding *)enc, cr);
}

static int
enc_mbminlen(void *enc)
{
    return rb_enc_mbminlen((rb_encoding *)enc);
}

static bool
enc_isascii(OnigCodePoint c, void *enc)
{
    return rb_enc_isascii(c, (rb_encoding *)enc);
}

static OnigCodePoint
enc_mbc_to_codepoint(const char *p, const char *e, void *enc)
{
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);

    return ONIGENC_MBC_TO_CODE((rb_encoding *)enc, up, ue);
}

VALUE rb_io_gets_internal(VALUE io);
extern VALUE rb_eArgError;

static const rb_parser_config_t rb_global_parser_config = {
    .malloc = ruby_xmalloc,
    .calloc = ruby_xcalloc,
    .realloc = ruby_xrealloc,
    .free = ruby_xfree,
    .alloc_n = ruby_xmalloc2,
    .alloc = ruby_xmalloc,
    .realloc_n = ruby_xrealloc2,
    .zalloc = zalloc,
    .rb_memmove = memmove2,
    .nonempty_memcpy = nonempty_memcpy,
    .xmalloc_mul_add = rb_xmalloc_mul_add,

    .ast_new = ast_new,

    .compile_callback = rb_suppress_tracing,
    .reg_named_capture_assign = reg_named_capture_assign,

    .attr_get = rb_attr_get,

    .ary_new = rb_ary_new,
    .ary_push = rb_ary_push,
    .ary_new_from_args = rb_ary_new_from_args,
    .ary_unshift = rb_ary_unshift,
    .ary_modify = rb_ary_modify,
    .array_len = rb_array_len,
    .array_aref = RARRAY_AREF,

    .make_temporary_id = rb_make_temporary_id,
    .is_local_id = is_local_id2,
    .is_attrset_id = is_attrset_id2,
    .is_global_name_punct = is_global_name_punct,
    .id_type = id_type,
    .id_attrset = rb_id_attrset,
    .intern = rb_intern,
    .intern2 = rb_intern2,
    .intern3 = intern3,
    .intern_str = rb_intern_str,
    .is_notop_id = is_notop_id2,
    .enc_symname_type = enc_symname_type,
    .id2name = rb_id2name,
    .id2str = rb_id2str,
    .id2sym = rb_id2sym,
    .sym2id = rb_sym2id,

    .str_catf = rb_str_catf,
    .str_cat_cstr = rb_str_cat_cstr,
    .str_subseq = rb_str_subseq,
    .str_new_frozen = rb_str_new_frozen,
    .str_buf_new = rb_str_buf_new,
    .str_buf_cat = rb_str_buf_cat,
    .str_modify = rb_str_modify,
    .str_set_len = rb_str_set_len,
    .str_cat = rb_str_cat,
    .str_resize = rb_str_resize,
    .str_new = rb_str_new,
    .str_new_cstr = rb_str_new_cstr,
    .str_to_interned_str = rb_str_to_interned_str,
    .is_ascii_string = is_ascii_string2,
    .enc_str_new = enc_str_new,
    .enc_str_buf_cat = enc_str_buf_cat,
    .str_buf_append = rb_str_buf_append,
    .str_vcatf = rb_str_vcatf,
    .string_value_cstr = rb_string_value_cstr,
    .rb_sprintf = rb_sprintf,
    .rstring_ptr = RSTRING_PTR,
    .rstring_end = RSTRING_END,
    .rstring_len = RSTRING_LEN,
    .filesystem_str_new_cstr = rb_filesystem_str_new_cstr,
    .obj_as_string = rb_obj_as_string,

    .int2num = rb_int2num_inline,

    .stderr_tty_p = rb_stderr_tty_p,
    .write_error_str = rb_write_error_str,
    .default_rs = default_rs,
    .io_write = rb_io_write,
    .io_flush = rb_io_flush,
    .io_puts = rb_io_puts,
    .io_gets_internal = rb_io_gets_internal,

    .debug_output_stdout = rb_ractor_stdout,
    .debug_output_stderr = rb_ractor_stderr,

    .is_usascii_enc = is_usascii_enc,
    .enc_isalnum = enc_isalnum,
    .enc_precise_mbclen = enc_precise_mbclen,
    .mbclen_charfound_p = mbclen_charfound_p,
    .mbclen_charfound_len = mbclen_charfound_len,
    .enc_name = enc_name,
    .enc_prev_char = enc_prev_char,
    .enc_get = enc_get,
    .enc_asciicompat = enc_asciicompat,
    .utf8_encoding = utf8_encoding,
    .enc_associate = enc_associate,
    .ascii8bit_encoding = ascii8bit_encoding,
    .enc_codelen = enc_codelen,
    .enc_mbcput = enc_mbcput,
    .enc_find_index = rb_enc_find_index,
    .enc_from_index = enc_from_index,
    .enc_associate_index = rb_enc_associate_index,
    .enc_isspace = enc_isspace,
    .enc_coderange_7bit = ENC_CODERANGE_7BIT,
    .enc_coderange_unknown = ENC_CODERANGE_UNKNOWN,
    .enc_compatible = enc_compatible,
    .enc_from_encoding = enc_from_encoding,
    .encoding_is_ascii8bit = encoding_is_ascii8bit,
    .usascii_encoding = usascii_encoding,
    .enc_coderange_broken = ENC_CODERANGE_BROKEN,
    .enc_mbminlen = enc_mbminlen,
    .enc_isascii = enc_isascii,
    .enc_mbc_to_codepoint = enc_mbc_to_codepoint,

    .local_defined = local_defined,
    .dvar_defined = dvar_defined,

    .syntax_error_append = syntax_error_append,
    .raise = rb_raise,
    .syntax_error_new = syntax_error_new,

    .errinfo = rb_errinfo,
    .set_errinfo = rb_set_errinfo,
    .exc_raise = rb_exc_raise,
    .make_exception = rb_make_exception,

    .sized_xfree = ruby_sized_xfree,
    .sized_realloc_n = ruby_sized_realloc_n,
    .obj_write = obj_write,
    .gc_guard = gc_guard,
    .gc_mark = rb_gc_mark,
    .gc_mark_and_move = rb_gc_mark_and_move,

    .reg_compile = rb_reg_compile,
    .reg_check_preprocess = rb_reg_check_preprocess,
    .memcicmp = rb_memcicmp,

    .compile_warn = rb_compile_warn,
    .compile_warning = rb_compile_warning,
    .bug = rb_bug,
    .fatal = rb_fatal,
    .verbose = ruby_verbose2,
    .errno_ptr = rb_errno_ptr2,

    .make_backtrace = rb_make_backtrace,

    .scan_hex = ruby_scan_hex,
    .scan_oct = ruby_scan_oct,
    .scan_digits = ruby_scan_digits,
    .strtod = ruby_strtod,

    .rbool = rbool,
    .rtest = rtest,
    .nil_p = nil_p,
    .qnil = Qnil,
    .qtrue = Qtrue,
    .qfalse = Qfalse,
    .eArgError = arg_error,
    .long2int = rb_long2int,

    /* For Ripper */
    .static_id2sym = static_id2sym,
    .str_coderange_scan_restartable = str_coderange_scan_restartable,
};

const rb_parser_config_t *
rb_ruby_parser_config(void)
{
    return &rb_global_parser_config;
}

rb_parser_t *
rb_parser_params_allocate(void)
{
    return rb_ruby_parser_allocate(&rb_global_parser_config);
}

rb_parser_t *
rb_parser_params_new(void)
{
    return rb_ruby_parser_new(&rb_global_parser_config);
}

VALUE
rb_parser_new(void)
{
    struct ruby_parser *parser;
    rb_parser_t *parser_params;

    /*
     * Create parser_params ahead of vparser because
     * rb_ruby_parser_new can run GC so if create vparser
     * first, parser_mark tries to mark not initialized parser_params.
     */
    parser_params = rb_parser_params_new();
    VALUE vparser = TypedData_Make_Struct(0, struct ruby_parser,
                                         &ruby_parser_data_type, parser);
    parser->parser_params = parser_params;

    return vparser;
}

void
rb_parser_set_options(VALUE vparser, int print, int loop, int chomp, int split)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_set_options(parser->parser_params, print, loop, chomp, split);
}

VALUE
rb_parser_set_context(VALUE vparser, const struct rb_iseq_struct *base, int main)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_set_context(parser->parser_params, base, main);
    return vparser;
}

void
rb_parser_set_script_lines(VALUE vparser, VALUE lines)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_set_script_lines(parser->parser_params, lines);
}

void
rb_parser_error_tolerant(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_error_tolerant(parser->parser_params);
}

rb_ast_t*
rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE file, int start)
{
    struct ruby_parser *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    ast = rb_ruby_parser_compile_file_path(parser->parser_params, fname, file, start);
    RB_GC_GUARD(vparser);

    return ast;
}

void
rb_parser_keep_tokens(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_keep_tokens(parser->parser_params);
}

rb_ast_t*
rb_parser_compile_generic(VALUE vparser, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int start)
{
    struct ruby_parser *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    ast = rb_ruby_parser_compile_generic(parser->parser_params, lex_gets, fname, input, start);
    RB_GC_GUARD(vparser);

    return ast;
}

rb_ast_t*
rb_parser_compile_string(VALUE vparser, const char *f, VALUE s, int line)
{
    struct ruby_parser *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    ast = rb_ruby_parser_compile_string(parser->parser_params, f, s, line);
    RB_GC_GUARD(vparser);

    return ast;
}

rb_ast_t*
rb_parser_compile_string_path(VALUE vparser, VALUE f, VALUE s, int line)
{
    struct ruby_parser *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    ast = rb_ruby_parser_compile_string_path(parser->parser_params, f, s, line);
    RB_GC_GUARD(vparser);

    return ast;
}

VALUE
rb_parser_encoding(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    return rb_ruby_parser_encoding(parser->parser_params);
}

VALUE
rb_parser_end_seen_p(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    return RBOOL(rb_ruby_parser_end_seen_p(parser->parser_params));
}

VALUE
rb_parser_set_yydebug(VALUE vparser, VALUE flag)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_set_yydebug(parser->parser_params, RTEST(flag));
    return flag;
}
#endif

VALUE
rb_str_new_parser_string(rb_parser_string_t *str)
{
    return rb_enc_str_new(str->ptr, str->len, str->enc);
}

static VALUE
negative_numeric(VALUE val)
{
    if (FIXNUM_P(val)) {
        return LONG2FIX(-FIX2LONG(val));
    }
    if (SPECIAL_CONST_P(val)) {
#if USE_FLONUM
        if (FLONUM_P(val)) {
            return DBL2NUM(-RFLOAT_VALUE(val));
        }
#endif
        goto unknown;
    }
    switch (BUILTIN_TYPE(val)) {
      case T_BIGNUM:
        BIGNUM_NEGATE(val);
        val = rb_big_norm(val);
        break;
      case T_RATIONAL:
        RATIONAL_SET_NUM(val, negative_numeric(RRATIONAL(val)->num));
        break;
      case T_COMPLEX:
        RCOMPLEX_SET_REAL(val, negative_numeric(RCOMPLEX(val)->real));
        RCOMPLEX_SET_IMAG(val, negative_numeric(RCOMPLEX(val)->imag));
        break;
      case T_FLOAT:
        val = DBL2NUM(-RFLOAT_VALUE(val));
        break;
      unknown:
      default:
        rb_bug("unknown literal type (%s) passed to negative_numeric",
               rb_builtin_class_name(val));
        break;
    }
    return val;
}

static VALUE
integer_value(const char *val, int base)
{
    return rb_cstr_to_inum(val, base, FALSE);
}

static VALUE
rational_value(const char *node_val, int base, int seen_point)
{
    VALUE lit;
    char* val = strdup(node_val);
    if (seen_point > 0) {
        int len = (int)(strlen(val));
        char *point = &val[seen_point];
        size_t fraclen = len-seen_point-1;
        memmove(point, point+1, fraclen+1);

        lit = rb_rational_new(integer_value(val, base), rb_int_positive_pow(10, fraclen));
    }
    else {
        lit = rb_rational_raw1(integer_value(val, base));
    }

    free(val);

    return lit;
}

VALUE
rb_node_integer_literal_val(const NODE *n)
{
    const rb_node_integer_t *node = RNODE_INTEGER(n);
    VALUE val = integer_value(node->val, node->base);
    if (node->minus) {
        val = negative_numeric(val);
    }
    return val;
}

VALUE
rb_node_float_literal_val(const NODE *n)
{
    const rb_node_float_t *node = RNODE_FLOAT(n);
    double d = strtod(node->val, 0);
    if (node->minus) {
        d = -d;
    }
    VALUE val = DBL2NUM(d);
    return val;
}

VALUE
rb_node_rational_literal_val(const NODE *n)
{
    VALUE lit;
    const rb_node_rational_t *node = RNODE_RATIONAL(n);

    lit = rational_value(node->val, node->base, node->seen_point);

    if (node->minus) {
        lit = negative_numeric(lit);
    }

    return lit;
}

VALUE
rb_node_imaginary_literal_val(const NODE *n)
{
    VALUE lit;
    const rb_node_imaginary_t *node = RNODE_IMAGINARY(n);

    enum rb_numeric_type type = node->type;

    switch (type) {
      case integer_literal:
        lit = integer_value(node->val, node->base);
        break;
      case float_literal:{
        double d = strtod(node->val, 0);
        lit = DBL2NUM(d);
        break;
      }
      case rational_literal:
        lit = rational_value(node->val, node->base, node->seen_point);
        break;
      default:
        rb_bug("unreachable");
    }

    lit = rb_complex_raw(INT2FIX(0), lit);

    if (node->minus) {
        lit = negative_numeric(lit);
    }
    return lit;
}

VALUE
rb_node_str_string_val(const NODE *node)
{
    rb_parser_string_t *str = RNODE_STR(node)->string;
    return rb_str_new_parser_string(str);
}

VALUE
rb_node_sym_string_val(const NODE *node)
{
    rb_parser_string_t *str = RNODE_SYM(node)->string;
    return ID2SYM(rb_intern3(str->ptr, str->len, str->enc));
}

VALUE
rb_node_dstr_string_val(const NODE *node)
{
    rb_parser_string_t *str = RNODE_DSTR(node)->string;
    return str ? rb_str_new_parser_string(str) : Qnil;
}

VALUE
rb_node_dregx_string_val(const NODE *node)
{
    rb_parser_string_t *str = RNODE_DREGX(node)->string;
    return rb_str_new_parser_string(str);
}

VALUE
rb_node_regx_string_val(const NODE *node)
{
    rb_node_regx_t *node_reg = RNODE_REGX(node);
    rb_parser_string_t *string = node_reg->string;
    VALUE str = rb_enc_str_new(string->ptr, string->len, string->enc);

    return rb_reg_compile(str, node_reg->options, NULL, 0);
}

VALUE
rb_node_line_lineno_val(const NODE *node)
{
    return INT2FIX(node->nd_loc.beg_pos.lineno);
}

VALUE
rb_node_file_path_val(const NODE *node)
{
    return rb_str_new_parser_string(RNODE_FILE(node)->path);
}

VALUE
rb_node_encoding_val(const NODE *node)
{
    return rb_enc_from_encoding(RNODE_ENCODING(node)->enc);
}

VALUE
rb_script_lines_for(VALUE path)
{
    VALUE hash, lines;
    ID script_lines;
    CONST_ID(script_lines, "SCRIPT_LINES__");
    if (!rb_const_defined_at(rb_cObject, script_lines)) return Qnil;
    hash = rb_const_get_at(rb_cObject, script_lines);
    if (!RB_TYPE_P(hash, T_HASH)) return Qnil;
    rb_hash_aset(hash, path, lines = rb_ary_new());
    return lines;
}
