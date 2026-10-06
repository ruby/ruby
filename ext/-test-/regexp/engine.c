/* Compares the compiled form of a pattern between Onigmo and the Rust
 * engine. Both engines receive the same bytes; Ruby's own preprocessing of
 * Regexp sources is not involved. */

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "ruby/onigmo.h"
#include "internal/re.h"
#if USE_RUST_REGEXP
# include "internal/regexp_rust.h"
#endif

struct compiled_info {
    int num_mem, num_repeat, num_null_check, num_call;
    unsigned int capture_history, bt_mem_start, bt_mem_end;
    int stack_pop_level;
    unsigned int options;
    int optimize, threshold_len, anchor;
    size_t anchor_dmin, anchor_dmax;
    int sub_anchor;
    size_t dmin, dmax;
    const unsigned char *program;
    size_t program_len;
    const unsigned char *exact;
    size_t exact_len;
    const unsigned char *map;
    const int *repeat_range;
    size_t repeat_range_len;
};

#define SET(h, k, v) rb_hash_aset((h), ID2SYM(rb_intern(k)), (v))

static VALUE
info_to_hash(const struct compiled_info *ci, VALUE names)
{
    VALUE h = rb_hash_new();
    SET(h, "num_mem", INT2NUM(ci->num_mem));
    SET(h, "num_repeat", INT2NUM(ci->num_repeat));
    SET(h, "num_null_check", INT2NUM(ci->num_null_check));
    SET(h, "num_call", INT2NUM(ci->num_call));
    SET(h, "capture_history", UINT2NUM(ci->capture_history));
    SET(h, "bt_mem_start", UINT2NUM(ci->bt_mem_start));
    SET(h, "bt_mem_end", UINT2NUM(ci->bt_mem_end));
    SET(h, "stack_pop_level", INT2NUM(ci->stack_pop_level));
    SET(h, "options", UINT2NUM(ci->options));
    SET(h, "optimize", INT2NUM(ci->optimize));
    SET(h, "threshold_len", INT2NUM(ci->threshold_len));
    SET(h, "anchor", INT2NUM(ci->anchor));
    SET(h, "anchor_dmin", SIZET2NUM(ci->anchor_dmin));
    SET(h, "anchor_dmax", SIZET2NUM(ci->anchor_dmax));
    SET(h, "sub_anchor", INT2NUM(ci->sub_anchor));
    SET(h, "dmin", SIZET2NUM(ci->dmin));
    SET(h, "dmax", SIZET2NUM(ci->dmax));
    SET(h, "program", rb_str_new((const char *)ci->program, (long)ci->program_len));
    SET(h, "exact", ci->exact ? rb_str_new((const char *)ci->exact, (long)ci->exact_len) : rb_str_new(0, 0));
    SET(h, "map", rb_str_new((const char *)ci->map, ONIG_CHAR_TABLE_SIZE));
    VALUE rr = rb_ary_new();
    for (size_t i = 0; i < ci->repeat_range_len; i++) {
        rb_ary_push(rr, rb_assoc_new(INT2NUM(ci->repeat_range[i * 2]), INT2NUM(ci->repeat_range[i * 2 + 1])));
    }
    SET(h, "repeat_range", rr);
    SET(h, "names", names);
    return h;
}

static int
onigmo_name_iter(const OnigUChar *name, const OnigUChar *name_end, int ngroups, int *groups,
                 regex_t *reg, void *arg)
{
    VALUE g = rb_ary_new();
    for (int i = 0; i < ngroups; i++) rb_ary_push(g, INT2NUM(groups[i]));
    rb_ary_push((VALUE)arg, rb_assoc_new(rb_str_new((const char *)name, name_end - name), g));
    return 0;
}

static VALUE
compile_onigmo(VALUE src, unsigned int options, rb_encoding *enc)
{
    regex_t *reg;
    OnigErrorInfo einfo;
    const char *p = RSTRING_PTR(src);
    /* onig_new compiles with the default engine; this side must be Onigmo. */
    rb_regexp_engine_t saved = rb_reg_default_engine();
    rb_reg_default_engine_set(RB_REGEXP_ENGINE_ONIGMO);
    int r = onig_new(&reg, (const OnigUChar *)p, (const OnigUChar *)p + RSTRING_LEN(src),
                     options, enc, ONIG_SYNTAX_RUBY, &einfo);
    rb_reg_default_engine_set(saved);
    if (r) {
        OnigUChar buf[ONIG_MAX_ERROR_MESSAGE_LEN];
        onig_error_code_to_str(buf, r, &einfo);
        return rb_ary_new_from_args(3, ID2SYM(rb_intern("error")), INT2NUM(r), rb_str_new_cstr((char *)buf));
    }
    struct compiled_info ci = {
        reg->num_mem, reg->num_repeat, reg->num_null_check, reg->num_call,
        reg->capture_history, reg->bt_mem_start, reg->bt_mem_end,
        reg->stack_pop_level, reg->options,
        reg->optimize, reg->threshold_len, reg->anchor,
        reg->anchor_dmin, reg->anchor_dmax, reg->sub_anchor, reg->dmin, reg->dmax,
        reg->p, reg->used,
        reg->exact, reg->exact ? (size_t)(reg->exact_end - reg->exact) : 0,
        reg->map,
        (const int *)reg->repeat_range, (size_t)reg->num_repeat,
    };
    VALUE names = rb_ary_new();
    onig_foreach_name(reg, onigmo_name_iter, (void *)names);
    VALUE h = info_to_hash(&ci, names);
    onig_free(reg);
    return h;
}

#if USE_RUST_REGEXP
static VALUE
compile_rust(VALUE src, unsigned int options, rb_encoding *enc)
{
    static int inited;
    if (!inited) {
        rb_regexp_rust_init(ONIG_ENCODING_ASCII);
        inited = 1;
    }
    rb_regexp_rust_t *h;
    struct rb_regexp_compile_result res;
    int flags = RB_REGEXP_WARN_ENABLED | (RTEST(ruby_verbose) ? RB_REGEXP_WARN_VERBOSE : 0);
    int r = rb_regexp_rust_compile((const unsigned char *)RSTRING_PTR(src), RSTRING_LEN(src),
                                   options, enc, flags, &h, &res);
    /* Emitted only after the engine returned: rb_warn may raise. */
    for (size_t i = 0; i < res.warnings_len; i += strlen((char *)res.warnings + i) + 1) {
        rb_warn("%s", (char *)res.warnings + i);
    }
    rb_regexp_rust_free_bytes(res.warnings, res.warnings_len);
    if (r == RB_REGEXP_PANICKED) {
        char msg[256];
        rb_regexp_rust_take_panic_message(msg, sizeof(msg));
        rb_raise(rb_eRegexpError, "[BUG] regexp engine panic: %s", msg);
    }
    if (r) {
        return rb_ary_new_from_args(3, ID2SYM(rb_intern("error")), INT2NUM(r), rb_str_new_cstr((char *)res.message));
    }
    struct rb_regexp_rust_info ri;
    rb_regexp_rust_info(h, &ri);
    struct compiled_info ci = {
        ri.num_mem, ri.num_repeat, ri.num_null_check, ri.num_call,
        ri.capture_history, ri.bt_mem_start, ri.bt_mem_end,
        ri.stack_pop_level, ri.options,
        ri.optimize, ri.threshold_len, ri.anchor,
        ri.anchor_dmin, ri.anchor_dmax, ri.sub_anchor, ri.dmin, ri.dmax,
        ri.program, ri.program_len, ri.exact, ri.exact_len, ri.map,
        ri.repeat_range, ri.repeat_range_len,
    };
    VALUE names = rb_ary_new();
    size_t n = rb_regexp_rust_name_count(h);
    for (size_t i = 0; i < n; i++) {
        const unsigned char *name;
        size_t len;
        int ngroups;
        const int *groups;
        rb_regexp_rust_name_at(h, i, &name, &len, &ngroups, &groups);
        VALUE g = rb_ary_new();
        for (int j = 0; j < ngroups; j++) rb_ary_push(g, INT2NUM(groups[j]));
        rb_ary_push(names, rb_assoc_new(rb_str_new((const char *)name, (long)len), g));
    }
    VALUE hash = info_to_hash(&ci, names);
    rb_regexp_rust_free(h);
    return hash;
}
#endif

/*
 * Bug::Regexp.compile_info(engine, source, options = 0) -> Hash or [:error, code, message]
 *
 * The encoding of +source+ is the encoding the pattern is compiled for.
 */
static VALUE
bug_reg_compile_info(int argc, VALUE *argv, VALUE self)
{
    VALUE engine, src, opts;
    rb_scan_args(argc, argv, "21", &engine, &src, &opts);
    StringValue(src);
    unsigned int options = NIL_P(opts) ? 0 : NUM2UINT(opts);
    rb_encoding *enc = rb_enc_get(src);

    if (engine == ID2SYM(rb_intern("onigmo"))) {
        return compile_onigmo(src, options, enc);
    }
#if USE_RUST_REGEXP
    if (engine == ID2SYM(rb_intern("rust"))) {
        return compile_rust(src, options, enc);
    }
#endif
    rb_raise(rb_eArgError, "unknown or unavailable regexp engine: %"PRIsVALUE, engine);
}

static VALUE
bug_reg_rust_available_p(VALUE self)
{
    return USE_RUST_REGEXP ? Qtrue : Qfalse;
}

void
Init_engine(VALUE klass)
{
    rb_define_singleton_method(klass, "compile_info", bug_reg_compile_info, -1);
    rb_define_singleton_method(klass, "rust_available?", bug_reg_rust_available_p, 0);
}
