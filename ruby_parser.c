/* This is a wrapper for parse.y */

#include "internal/parse.h"
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

#define parser_encoding const void

static int
is_ascii_string2(VALUE str)
{
    return is_ascii_string(str);
}

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 6, 0)
static VALUE
syntax_error_append(VALUE exc, VALUE file, int line, int column,
                    parser_encoding *enc, const char *fmt, va_list args)
{
    return rb_syntax_error_append(exc, file, line, column, enc, fmt, args);
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
is_usascii_enc(parser_encoding *enc)
{
    return rb_is_usascii_enc(enc);
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
enc_str_new(const char *ptr, long len, parser_encoding *enc)
{
    return rb_enc_str_new(ptr, len, enc);
}

static int
enc_isalnum(OnigCodePoint c, parser_encoding *enc)
{
    return rb_enc_isalnum(c, enc);
}

static int
enc_precise_mbclen(const char *p, const char *e, parser_encoding *enc)
{
    return rb_enc_precise_mbclen(p, e, enc);
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
enc_name(parser_encoding *enc)
{
    return rb_enc_name(enc);
}

static char *
enc_prev_char(const char *s, const char *p, const char *e, parser_encoding *enc)
{
    return rb_enc_prev_char(s, p, e, enc);
}

static parser_encoding *
enc_get(VALUE obj)
{
    return rb_enc_get(obj);
}

static int
enc_asciicompat(parser_encoding *enc)
{
    return rb_enc_asciicompat(enc);
}

static parser_encoding *
utf8_encoding(void)
{
    return rb_utf8_encoding();
}

static VALUE
enc_associate(VALUE obj, parser_encoding *enc)
{
    return rb_enc_associate(obj, enc);
}

static parser_encoding *
ascii8bit_encoding(void)
{
    return rb_ascii8bit_encoding();
}

static int
enc_codelen(int c, parser_encoding *enc)
{
    return rb_enc_codelen(c, enc);
}

static int
enc_mbcput(unsigned int c, void *buf, parser_encoding *enc)
{
    return rb_enc_mbcput(c, buf, enc);
}

static parser_encoding *
enc_from_index(int idx)
{
    return rb_enc_from_index(idx);
}

static int
enc_isspace(OnigCodePoint c, parser_encoding *enc)
{
    return rb_enc_isspace(c, enc);
}

static ID
intern3(const char *name, long len, parser_encoding *enc)
{
    return rb_intern3(name, len, enc);
}

static parser_encoding *
usascii_encoding(void)
{
    return rb_usascii_encoding();
}

static int
enc_symname_type(const char *name, long len, parser_encoding *enc, unsigned int allowed_attrset)
{
    return rb_enc_symname_type(name, len, enc, allowed_attrset);
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

    return rb_reg_named_capture_assign_iter_impl(p, s, len, enc, &arg->succ_block, loc);
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

static VALUE
static_id2sym(ID id)
{
    return (((VALUE)(id)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG);
}

static long
str_coderange_scan_restartable(const char *s, const char *e, parser_encoding *enc, int *cr)
{
    return rb_str_coderange_scan_restartable(s, e, enc, cr);
}

static int
enc_mbminlen(parser_encoding *enc)
{
    return rb_enc_mbminlen(enc);
}

static bool
enc_isascii(OnigCodePoint c, parser_encoding *enc)
{
    return rb_enc_isascii(c, enc);
}

static OnigCodePoint
enc_mbc_to_codepoint(const char *p, const char *e, parser_encoding *enc)
{
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);

    return ONIGENC_MBC_TO_CODE((rb_encoding *)enc, up, ue);
}

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

    .compile_callback = rb_suppress_tracing,
    .reg_named_capture_assign = reg_named_capture_assign,

    .attr_get = rb_attr_get,

    .ary_new = rb_ary_new,
    .ary_push = rb_ary_push,
    .ary_new_from_args = rb_ary_new_from_args,
    .ary_unshift = rb_ary_unshift,

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
    .str_modify = rb_str_modify,
    .str_set_len = rb_str_set_len,
    .str_cat = rb_str_cat,
    .str_resize = rb_str_resize,
    .str_new = rb_str_new,
    .str_new_cstr = rb_str_new_cstr,
    .str_to_interned_str = rb_str_to_interned_str,
    .is_ascii_string = is_ascii_string2,
    .enc_str_new = enc_str_new,
    .str_vcatf = rb_str_vcatf,
    .string_value_cstr = rb_string_value_cstr,
    .rb_sprintf = rb_sprintf,
    .rstring_ptr = RSTRING_PTR,
    .rstring_end = RSTRING_END,
    .rstring_len = RSTRING_LEN,
    .obj_as_string = rb_obj_as_string,

    .int2num = rb_int2num_inline,

    .stderr_tty_p = rb_stderr_tty_p,
    .write_error_str = rb_write_error_str,
    .io_write = rb_io_write,
    .io_flush = rb_io_flush,
    .io_puts = rb_io_puts,

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
    .enc_isspace = enc_isspace,
    .enc_coderange_7bit = ENC_CODERANGE_7BIT,
    .enc_coderange_unknown = ENC_CODERANGE_UNKNOWN,
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
    .gc_guard = gc_guard,
    .gc_mark = rb_gc_mark,

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

    .rtest = rtest,
    .nil_p = nil_p,
    .qnil = Qnil,
    .qfalse = Qfalse,
    .eArgError = arg_error,
    .long2int = rb_long2int,

    /* For Ripper */
    .static_id2sym = static_id2sym,
    .str_coderange_scan_restartable = str_coderange_scan_restartable,
};
#endif

enum lex_type {
    lex_type_str,
    lex_type_io,
    lex_type_array,
    lex_type_generic,
};

struct ruby_parser {
    rb_parser_t *parser_params;
    enum lex_type type;
    union {
        struct lex_pointer_string lex_str;
        struct {
            VALUE file;
        } lex_io;
        struct {
            VALUE ary;
        } lex_array;
    } data;
};

static void
parser_mark(void *ptr)
{
    struct ruby_parser *parser = (struct ruby_parser*)ptr;
    rb_ruby_parser_mark(parser->parser_params);

    switch (parser->type) {
      case lex_type_str:
        rb_gc_mark(parser->data.lex_str.str);
        break;
      case lex_type_io:
        rb_gc_mark(parser->data.lex_io.file);
        break;
      case lex_type_array:
        rb_gc_mark(parser->data.lex_array.ary);
        break;
      case lex_type_generic:
        /* noop. Caller of rb_parser_compile_generic should mark the objects. */
        break;
    }
}

static void
parser_free(void *ptr)
{
    struct ruby_parser *parser = (struct ruby_parser*)ptr;
    rb_ruby_parser_free(parser->parser_params);
    xfree(parser);
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

#ifdef UNIVERSAL_PARSER
const rb_parser_config_t *
rb_ruby_parser_config(void)
{
    return &rb_global_parser_config;
}

rb_parser_t *
rb_parser_params_new(void)
{
    return rb_ruby_parser_new(&rb_global_parser_config);
}
#else
rb_parser_t *
rb_parser_params_new(void)
{
    return rb_ruby_parser_new();
}
#endif /* UNIVERSAL_PARSER */

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
rb_parser_set_script_lines(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_set_script_lines(parser->parser_params);
}

void
rb_parser_error_tolerant(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_error_tolerant(parser->parser_params);
}

void
rb_parser_keep_tokens(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    rb_ruby_parser_keep_tokens(parser->parser_params);
}

rb_parser_string_t *
rb_parser_lex_get_str(struct parser_params *p, struct lex_pointer_string *ptr_str)
{
    char *beg, *end, *start;
    long len;
    VALUE s = ptr_str->str;

    beg = RSTRING_PTR(s);
    len = RSTRING_LEN(s);
    start = beg;
    if (ptr_str->ptr) {
        if (len == ptr_str->ptr) return 0;
        beg += ptr_str->ptr;
        len -= ptr_str->ptr;
    }
    end = memchr(beg, '\n', len);
    if (end) len = ++end - beg;
    ptr_str->ptr += len;
    return rb_str_to_parser_string(p, rb_str_subseq(s, beg - start, len));
}

static rb_parser_string_t *
lex_get_str(struct parser_params *p, rb_parser_input_data input, int line_count)
{
    return rb_parser_lex_get_str(p, (struct lex_pointer_string *)input);
}

static void parser_aset_script_lines_for(VALUE path, rb_parser_ary_t *lines);

static rb_ast_t*
parser_compile(rb_parser_t *p, rb_parser_lex_gets_func *gets, VALUE fname, rb_parser_input_data input, int line)
{
    rb_ast_t *ast = rb_parser_compile(p, gets, fname, input, line);
    parser_aset_script_lines_for(fname, ast->body.script_lines);
    return ast;
}

static rb_ast_t*
parser_compile_string0(struct ruby_parser *parser, VALUE fname, VALUE s, int line)
{
    VALUE str = rb_str_new_frozen(s);

    parser->type = lex_type_str;
    parser->data.lex_str.str = str;
    parser->data.lex_str.ptr = 0;

    return parser_compile(parser->parser_params, lex_get_str, fname, (rb_parser_input_data)&parser->data, line);
}

static rb_encoding *
must_be_ascii_compatible(VALUE s)
{
    rb_encoding *enc = rb_enc_get(s);
    if (!rb_enc_asciicompat(enc)) {
        rb_raise(rb_eArgError, "invalid source encoding");
    }
    return enc;
}

static rb_ast_t*
parser_compile_string_path(struct ruby_parser *parser, VALUE f, VALUE s, int line)
{
    must_be_ascii_compatible(s);
    return parser_compile_string0(parser, f, s, line);
}

static rb_ast_t*
parser_compile_string(struct ruby_parser *parser, const char *f, VALUE s, int line)
{
    return parser_compile_string_path(parser, rb_filesystem_str_new_cstr(f), s, line);
}

VALUE rb_io_gets_internal(VALUE io);

static rb_parser_string_t *
lex_io_gets(struct parser_params *p, rb_parser_input_data input, int line_count)
{
    VALUE io = (VALUE)input;
    VALUE line = rb_io_gets_internal(io);
    if (NIL_P(line)) return 0;
    return rb_str_to_parser_string(p, line);
}

static rb_parser_string_t *
lex_gets_array(struct parser_params *p, rb_parser_input_data data, int index)
{
    VALUE array = (VALUE)data;
    VALUE str = rb_ary_entry(array, index);
    if (!NIL_P(str)) {
        StringValue(str);
        if (!rb_enc_asciicompat(rb_enc_get(str))) {
            rb_raise(rb_eArgError, "invalid source encoding");
        }
        return rb_str_to_parser_string(p, str);
    }
    else {
        return 0;
    }
}

static rb_ast_t*
parser_compile_file_path(struct ruby_parser *parser, VALUE fname, VALUE file, int start)
{
    parser->type = lex_type_io;
    parser->data.lex_io.file = file;

    return parser_compile(parser->parser_params, lex_io_gets, fname, (rb_parser_input_data)file, start);
}

static rb_ast_t*
parser_compile_array(struct ruby_parser *parser, VALUE fname, VALUE array, int start)
{
    parser->type = lex_type_array;
    parser->data.lex_array.ary = array;

    return parser_compile(parser->parser_params, lex_gets_array, fname, (rb_parser_input_data)array, start);
}

static rb_ast_t*
parser_compile_generic(struct ruby_parser *parser, rb_parser_lex_gets_func *lex_gets, VALUE fname, VALUE input, int start)
{
    parser->type = lex_type_generic;

    return parser_compile(parser->parser_params, lex_gets, fname, (rb_parser_input_data)input, start);
}

static void
ast_free(void *ptr)
{
    rb_ast_t *ast = (rb_ast_t *)ptr;
    rb_ast_free(ast);
}

static const rb_data_type_t ast_data_type = {
    "AST",
    {
        NULL,
        ast_free,
        NULL, // No dsize() because this object does not appear in ObjectSpace.
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
ast_alloc(void)
{
    return TypedData_Wrap_Struct(0, &ast_data_type, NULL);
}

VALUE
rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE file, int start)
{
    struct ruby_parser *parser;
    VALUE ast_value = ast_alloc();

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    DATA_PTR(ast_value) = parser_compile_file_path(parser, fname, file, start);
    RB_GC_GUARD(vparser);

    return ast_value;
}

VALUE
rb_parser_compile_array(VALUE vparser, VALUE fname, VALUE array, int start)
{
    struct ruby_parser *parser;
    VALUE ast_value = ast_alloc();

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    DATA_PTR(ast_value) = parser_compile_array(parser, fname, array, start);
    RB_GC_GUARD(vparser);

    return ast_value;
}

VALUE
rb_parser_compile_generic(VALUE vparser, rb_parser_lex_gets_func *lex_gets, VALUE fname, VALUE input, int start)
{
    struct ruby_parser *parser;
    VALUE ast_value = ast_alloc();

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    DATA_PTR(ast_value) = parser_compile_generic(parser, lex_gets, fname, input, start);
    RB_GC_GUARD(vparser);

    return ast_value;
}

VALUE
rb_parser_compile_string(VALUE vparser, const char *f, VALUE s, int line)
{
    struct ruby_parser *parser;
    VALUE ast_value = ast_alloc();

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    DATA_PTR(ast_value) = parser_compile_string(parser, f, s, line);
    RB_GC_GUARD(vparser);

    return ast_value;
}

VALUE
rb_parser_compile_string_path(VALUE vparser, VALUE f, VALUE s, int line)
{
    struct ruby_parser *parser;
    VALUE ast_value = ast_alloc();

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    DATA_PTR(ast_value) = parser_compile_string_path(parser, f, s, line);
    RB_GC_GUARD(vparser);

    return ast_value;
}

VALUE
rb_parser_encoding(VALUE vparser)
{
    struct ruby_parser *parser;

    TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
    return rb_enc_from_encoding(rb_ruby_parser_encoding(parser->parser_params));
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

void
rb_set_script_lines_for(VALUE vparser, VALUE path)
{
    struct ruby_parser *parser;
    VALUE hash;
    ID script_lines;
    CONST_ID(script_lines, "SCRIPT_LINES__");
    if (!rb_const_defined_at(rb_cObject, script_lines)) return;
    hash = rb_const_get_at(rb_cObject, script_lines);
    if (RB_TYPE_P(hash, T_HASH)) {
        rb_hash_aset(hash, path, Qtrue);
        TypedData_Get_Struct(vparser, struct ruby_parser, &ruby_parser_data_type, parser);
        rb_ruby_parser_set_script_lines(parser->parser_params);
    }
}

VALUE
rb_parser_build_script_lines_from(rb_parser_ary_t *lines)
{
    int i;
    if (!lines) return Qnil;
    if (lines->data_type != PARSER_ARY_DATA_SCRIPT_LINE) {
        rb_bug("unexpected rb_parser_ary_data_type (%d) for script lines", lines->data_type);
    }
    VALUE script_lines = rb_ary_new_capa(lines->len);
    for (i = 0; i < lines->len; i++) {
        rb_parser_string_t *str = (rb_parser_string_t *)lines->data[i];
        rb_ary_push(script_lines, rb_enc_str_new(str->ptr, str->len, str->enc));
    }
    return script_lines;
}

VALUE
rb_str_new_parser_string(rb_parser_string_t *str)
{
    VALUE string = rb_enc_literal_str(str->ptr, str->len, str->enc);
    rb_enc_str_coderange(string);
    return string;
}

VALUE
rb_str_new_mutable_parser_string(rb_parser_string_t *str)
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

static void
parser_aset_script_lines_for(VALUE path, rb_parser_ary_t *lines)
{
    VALUE hash, script_lines;
    ID script_lines_id;
    if (NIL_P(path) || !lines) return;
    CONST_ID(script_lines_id, "SCRIPT_LINES__");
    if (!rb_const_defined_at(rb_cObject, script_lines_id)) return;
    hash = rb_const_get_at(rb_cObject, script_lines_id);
    if (!RB_TYPE_P(hash, T_HASH)) return;
    if (rb_hash_lookup(hash, path) == Qnil) return;
    script_lines = rb_parser_build_script_lines_from(lines);
    rb_hash_aset(hash, path, script_lines);
}

VALUE
rb_ruby_ast_new(const NODE *const root)
{
    rb_ast_t *ast;
    VALUE ast_value = TypedData_Make_Struct(0, rb_ast_t, &ast_data_type, ast);
#ifdef UNIVERSAL_PARSER
    ast->config = &rb_global_parser_config;
#endif
    ast->body = (rb_ast_body_t){
        .root = root,
        .frozen_string_literal = -1,
        .coverage_enabled = -1,
        .script_lines = NULL,
        .line_count = 0,
    };
    return ast_value;
}

rb_ast_t *
rb_ruby_ast_data_get(VALUE ast_value)
{
    rb_ast_t *ast;
    if (NIL_P(ast_value)) return NULL;
    TypedData_Get_Struct(ast_value, rb_ast_t, &ast_data_type, ast);
    return ast;
}
