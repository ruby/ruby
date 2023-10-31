/* This is a wrapper for parse.y */
#ifdef UNIVERSAL_PARSER

#include "internal.h"
#include "internal/array.h"
#include "internal/bignum.h"
#include "internal/compile.h"
#include "internal/complex.h"
#include "internal/encoding.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/io.h"
#include "internal/parse.h"
#include "internal/rational.h"
#include "internal/re.h"
#include "internal/ruby_parser.h"
#include "internal/string.h"
#include "internal/symbol.h"
#include "internal/thread.h"

#include "ruby/ractor.h"
#include "ruby/ruby.h"
#include "ruby/util.h"
#include "node.h"
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

static void
bignum_negate(VALUE b)
{
    BIGNUM_NEGATE(b);
}

static int
is_ascii_string2(VALUE str)
{
    return is_ascii_string(str);
}

static void
rational_set_num(VALUE r, VALUE n)
{
    RATIONAL_SET_NUM(r, n);
}

static VALUE
rational_get_num(VALUE obj)
{
    return RRATIONAL(obj)->num;
}

static void
rcomplex_set_real(VALUE cmp, VALUE r)
{
    RCOMPLEX_SET_REAL(cmp, r);
}

static void
rcomplex_set_imag(VALUE cmp, VALUE i)
{
    RCOMPLEX_SET_IMAG(cmp, i);
}

static VALUE
rcomplex_get_real(VALUE obj)
{
    return RCOMPLEX(obj)->real;
}

static VALUE
rcomplex_get_imag(VALUE obj)
{
    return RCOMPLEX(obj)->imag;
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

static bool
hash_literal_key_p(VALUE k)
{
    switch (OBJ_BUILTIN_TYPE(k)) {
      case T_NODE:
        return false;
      default:
        return true;
    }
}

static int
literal_cmp(VALUE val, VALUE lit)
{
    if (val == lit) return 0;
    if (!hash_literal_key_p(val) || !hash_literal_key_p(lit)) return -1;
    return rb_iseq_cdhash_cmp(val, lit);
}

static st_index_t
literal_hash(VALUE a)
{
    if (!hash_literal_key_p(a)) return (st_index_t)a;
    return rb_iseq_cdhash_hash(a);
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
encoding_get(VALUE obj)
{
    return ENCODING_GET(obj);
}

static void
encoding_set(VALUE obj, int encindex)
{
    ENCODING_SET(obj, encindex);
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
undef_p(VALUE v)
{
    return RB_UNDEF_P(v);
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

static int
flonum_p(VALUE obj)
{
    return (int)RB_FLONUM_P(obj);
}

static VALUE
int2fix(long i)
{
    return INT2FIX(i);
}

static VALUE
syntax_error_new(void)
{
    return rb_class_new_instance(0, 0, rb_eSyntaxError);
}

static int
obj_frozen(VALUE obj)
{
    return (int)RB_OBJ_FROZEN(obj);
}

static VALUE
obj_write(VALUE old, VALUE *slot, VALUE young)
{
    return RB_OBJ_WRITE(old, slot, young);
}

static VALUE
obj_written(VALUE old, VALUE slot, VALUE young)
{
    return RB_OBJ_WRITTEN(old, slot, young);
}

static VALUE
default_rs(void)
{
    return rb_default_rs;
}

static VALUE
rational_raw1(VALUE x)
{
    return rb_rational_raw1(x);
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

static int
type_p(VALUE obj, int t)
{
    return (int)RB_TYPE_P(obj, t);
}

static int
fixnum_p(VALUE obj)
{
    return (int)RB_FIXNUM_P(obj);
}

static int
symbol_p(VALUE obj)
{
    return (int)RB_SYMBOL_P(obj);
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

static rb_imemo_tmpbuf_t *
tmpbuf_parser_heap(void *buf, rb_imemo_tmpbuf_t *old_heap, size_t cnt)
{
    return rb_imemo_tmpbuf_parser_heap(buf, old_heap, cnt);
}

static int
special_const_p(VALUE obj)
{
    return (int)RB_SPECIAL_CONST_P(obj);
}

static int
builtin_type(VALUE obj)
{
    return (int)RB_BUILTIN_TYPE(obj);
}

static rb_ast_t *
ast_new(VALUE nb)
{
    rb_ast_t *ast = (rb_ast_t *)rb_imemo_new(imemo_ast, 0, 0, 0, nb);
    return ast;
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

VALUE rb_io_gets_internal(VALUE io);
extern VALUE rb_mRubyVMFrozenCore;
VALUE rb_node_case_when_optimizable_literal(const NODE *const node);

void
rb_parser_config_initialize(rb_parser_config_t *config)
{
    config->counter = 0;

    config->malloc   = ruby_xmalloc;
    config->calloc   = ruby_xcalloc;
    config->realloc  = ruby_xrealloc;
    config->free     = ruby_xfree;
    config->alloc_n  = ruby_xmalloc2;
    config->alloc    = ruby_xmalloc;
    config->realloc_n = ruby_xrealloc2;
    config->zalloc = zalloc;
    config->rb_memmove = memmove2;
    config->nonempty_memcpy = nonempty_memcpy;
    config->xmalloc_mul_add = rb_xmalloc_mul_add;

    config->tmpbuf_parser_heap = tmpbuf_parser_heap;
    config->ast_new = ast_new;

    config->compile_callback         = rb_suppress_tracing;
    config->reg_named_capture_assign = reg_named_capture_assign;

    config->obj_freeze = rb_obj_freeze;
    config->obj_hide = rb_obj_hide;
    config->obj_frozen = obj_frozen;
    config->type_p = type_p;
    config->obj_freeze_raw = OBJ_FREEZE_RAW;

    config->fixnum_p = fixnum_p;
    config->symbol_p = symbol_p;

    config->attr_get = rb_attr_get;

    config->ary_new           = rb_ary_new;
    config->ary_push          = rb_ary_push;
    config->ary_new_from_args = rb_ary_new_from_args;
    config->ary_pop           = rb_ary_pop;
    config->ary_last          = rb_ary_last;
    config->ary_unshift       = rb_ary_unshift;
    config->ary_new2          = rb_ary_new2;
    config->ary_entry         = rb_ary_entry;
    config->ary_join          = rb_ary_join;
    config->ary_reverse       = rb_ary_reverse;
    config->ary_clear         = rb_ary_clear;
    config->array_len         = rb_array_len;
    config->array_aref        = RARRAY_AREF;

    config->sym_intern_ascii_cstr = rb_sym_intern_ascii_cstr;
    config->make_temporary_id     = rb_make_temporary_id;
    config->is_local_id           = is_local_id2;
    config->is_attrset_id         = is_attrset_id2;
    config->is_global_name_punct  = is_global_name_punct;
    config->id_type               = id_type;
    config->id_attrset            = rb_id_attrset;
    config->intern                = rb_intern;
    config->intern2               = rb_intern2;
    config->intern3               = intern3;
    config->intern_str            = rb_intern_str;
    config->is_notop_id           = is_notop_id2;
    config->enc_symname_type      = enc_symname_type;
    config->str_intern            = rb_str_intern;
    config->id2name               = rb_id2name;
    config->id2str                = rb_id2str;
    config->id2sym                = rb_id2sym;
    config->sym2id                = rb_sym2id;

    config->str_catf        = rb_str_catf;
    config->str_cat_cstr    = rb_str_cat_cstr;
    config->str_subseq      = rb_str_subseq;
    config->str_dup         = rb_str_dup;
    config->str_new_frozen  = rb_str_new_frozen;
    config->str_buf_new     = rb_str_buf_new;
    config->str_buf_cat     = rb_str_buf_cat;
    config->str_modify      = rb_str_modify;
    config->str_set_len     = rb_str_set_len;
    config->str_cat         = rb_str_cat;
    config->str_resize      = rb_str_resize;
    config->str_new         = rb_str_new;
    config->str_new_cstr    = rb_str_new_cstr;
    config->fstring         = rb_fstring;
    config->is_ascii_string = is_ascii_string2;
    config->enc_str_new     = enc_str_new;
    config->enc_str_buf_cat = enc_str_buf_cat;
    config->str_buf_append  = rb_str_buf_append;
    config->str_vcatf       = rb_str_vcatf;
    config->string_value_cstr = rb_string_value_cstr;
    config->rb_sprintf      = rb_sprintf;
    config->rstring_ptr     = RSTRING_PTR;
    config->rstring_end     = RSTRING_END;
    config->rstring_len     = RSTRING_LEN;
    config->filesystem_str_new_cstr = rb_filesystem_str_new_cstr;
    config->obj_as_string = rb_obj_as_string;

    config->hash_clear     = rb_hash_clear;
    config->hash_new       = rb_hash_new;
    config->hash_aset      = rb_hash_aset;
    config->hash_lookup    = rb_hash_lookup;
    config->hash_delete    = rb_hash_delete;
    config->ident_hash_new = rb_ident_hash_new;

    config->int2fix = int2fix;

    config->bignum_negate = bignum_negate;
    config->big_norm      = rb_big_norm;
    config->cstr_to_inum  = rb_cstr_to_inum;

    config->float_new   = rb_float_new;
    config->float_value = rb_float_value;

    config->num2int          = rb_num2int_inline;
    config->int_positive_pow = rb_int_positive_pow;
    config->int2num          = rb_int2num_inline;
    config->fix2long         = rb_fix2long;

    config->rational_new     = rb_rational_new;
    config->rational_raw1    = rational_raw1;
    config->rational_set_num = rational_set_num;
    config->rational_get_num = rational_get_num;

    config->complex_raw       = rb_complex_raw;
    config->rcomplex_set_real = rcomplex_set_real;
    config->rcomplex_set_imag = rcomplex_set_imag;
    config->rcomplex_get_real = rcomplex_get_real;
    config->rcomplex_get_imag = rcomplex_get_imag;

    config->stderr_tty_p    = rb_stderr_tty_p;
    config->write_error_str = rb_write_error_str;
    config->default_rs = default_rs;
    config->io_write = rb_io_write;
    config->io_flush = rb_io_flush;
    config->io_puts = rb_io_puts;
    config->io_gets_internal= rb_io_gets_internal;

    config->debug_output_stdout = rb_ractor_stdout;
    config->debug_output_stderr = rb_ractor_stderr;

    config->is_usascii_enc        = is_usascii_enc;
    config->enc_isalnum           = enc_isalnum;
    config->enc_precise_mbclen    = enc_precise_mbclen;
    config->mbclen_charfound_p    = mbclen_charfound_p;
    config->enc_name              = enc_name;
    config->enc_prev_char         = enc_prev_char;
    config->enc_get               = enc_get;
    config->enc_asciicompat       = enc_asciicompat;
    config->utf8_encoding         = utf8_encoding;
    config->enc_associate         = enc_associate;
    config->ascii8bit_encoding    = ascii8bit_encoding;
    config->enc_codelen           = enc_codelen;
    config->enc_mbcput            = enc_mbcput;
    config->char_to_option_kcode  = rb_char_to_option_kcode;
    config->ascii8bit_encindex    = rb_ascii8bit_encindex;
    config->enc_find_index        = rb_enc_find_index;
    config->enc_from_index        = enc_from_index;
    config->enc_associate_index   = rb_enc_associate_index;
    config->enc_isspace           = enc_isspace;
    config->enc_coderange_7bit    = ENC_CODERANGE_7BIT;
    config->enc_coderange_unknown = ENC_CODERANGE_UNKNOWN;
    config->enc_compatible        = enc_compatible;
    config->enc_from_encoding     = enc_from_encoding;
    config->encoding_get          = encoding_get;
    config->encoding_set          = encoding_set;
    config->encoding_is_ascii8bit = encoding_is_ascii8bit;
    config->usascii_encoding      = usascii_encoding;

    config->ractor_make_shareable = rb_ractor_make_shareable;

    config->local_defined        = local_defined;
    config->dvar_defined         = dvar_defined;

    config->literal_cmp  = literal_cmp;
    config->literal_hash = literal_hash;

    config->builtin_class_name = rb_builtin_class_name;
    config->syntax_error_append = syntax_error_append;
    config->raise = rb_raise;
    config->syntax_error_new = syntax_error_new;

    config->errinfo = rb_errinfo;
    config->set_errinfo = rb_set_errinfo;
    config->exc_raise = rb_exc_raise;
    config->make_exception = rb_make_exception;

    config->sized_xfree = ruby_sized_xfree;
    config->sized_realloc_n = ruby_sized_realloc_n;
    config->obj_write = obj_write;
    config->obj_written = obj_written;
    config->gc_register_mark_object = rb_gc_register_mark_object;
    config->gc_guard = gc_guard;
    config->gc_mark = rb_gc_mark;
    config->gc_mark_movable = rb_gc_mark_movable;
    config->gc_location = rb_gc_location;

    config->reg_compile = rb_reg_compile;
    config->reg_check_preprocess = rb_reg_check_preprocess;
    config->memcicmp = rb_memcicmp;

    config->compile_warn    = rb_compile_warn;
    config->compile_warning = rb_compile_warning;
    config->bug             = rb_bug;
    config->fatal           = rb_fatal;
    config->verbose         = ruby_verbose2;

    config->make_backtrace = rb_make_backtrace;

    config->scan_hex    = ruby_scan_hex;
    config->scan_oct    = ruby_scan_oct;
    config->scan_digits = ruby_scan_digits;
    config->strtod      = ruby_strtod;

    config->rbool = rbool;
    config->undef_p = undef_p;
    config->rtest = rtest;
    config->nil_p = nil_p;
    config->flonum_p = flonum_p;
    config->qnil  = Qnil;
    config->qtrue = Qtrue;
    config->qfalse = Qfalse;
    config->qundef = Qundef;
    config->eArgError = rb_eArgError;
    config->mRubyVMFrozenCore = rb_mRubyVMFrozenCore;
    config->long2int = rb_long2int;
    config->special_const_p = special_const_p;
    config->builtin_type = builtin_type;

    config->node_case_when_optimizable_literal = rb_node_case_when_optimizable_literal;

    /* For Ripper */
    config->static_id2sym = static_id2sym;
    config->str_coderange_scan_restartable = str_coderange_scan_restartable;
}

VALUE
rb_parser_new(void)
{
    struct ruby_parser *parser;
    rb_parser_config_t *config;
    rb_parser_t *parser_params;

    config = rb_ruby_parser_config_new(ruby_xmalloc);
    rb_parser_config_initialize(config);

    /*
     * Create parser_params ahead of vparser because
     * rb_ruby_parser_new can run GC so if create vparser
     * first, parser_mark tries to mark not initialized parser_params.
     */
    parser_params = rb_ruby_parser_new(config);
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

#else

/* For "ISO C requires a translation unit to contain at least one declaration" */
void
rb_parser_dummy(void)
{}
#endif
