// Glue between Regexp (re.c) and the regexp engines: Onigmo and the Rust
// engine in regexp/. Selecting the engine and calling into Rust happen here.

#include "internal.h"
#include "internal/re.h"

#ifndef RB_DEFAULT_REGEXP_ENGINE
# define RB_DEFAULT_REGEXP_ENGINE RB_REGEXP_ENGINE_ONIGMO
#endif

#if USE_RUST_REGEXP
# include "internal/regexp_rust.h"
#endif

static rb_regexp_engine_t default_engine = RB_DEFAULT_REGEXP_ENGINE;

rb_regexp_engine_t
rb_reg_default_engine(void)
{
    return default_engine;
}

/* Returns false when +engine+ is not built into this ruby. */
bool
rb_reg_default_engine_set(rb_regexp_engine_t engine)
{
    switch (engine) {
      case RB_REGEXP_ENGINE_ONIGMO:
        break;
      case RB_REGEXP_ENGINE_RUST:
#if USE_RUST_REGEXP
        if (rb_regexp_rust_abi_version() != RB_REGEXP_RUST_ABI_VERSION) {
            rb_bug("regexp engine ABI mismatch: %u != %u",
                   rb_regexp_rust_abi_version(), RB_REGEXP_RUST_ABI_VERSION);
        }
        rb_regexp_rust_init(ONIG_ENCODING_ASCII);
        break;
#else
        return false;
#endif
      default:
        return false;
    }
    default_engine = engine;
    return true;
}

#if USE_RUST_REGEXP
#include "hrtime.h"
#include "regint.h"

#define RUST_HANDLE(reg) ((rb_regexp_rust_t *)(reg)->reserved1)

NORETURN(static void rust_panicked(void));

static void
rust_panicked(void)
{
    char msg[256] = "";
    rb_regexp_rust_take_panic_message(msg, sizeof(msg));
#if RUBY_DEBUG
    rb_bug("regexp engine panic: %s", msg);
#else
    rb_raise(rb_eRegexpError, "[BUG] regexp engine panic: %s", msg);
#endif
}

/* Emits warnings collected while compiling, the way onig_syntax_warn does. */
static void
emit_warnings(unsigned char *warnings, size_t len, const char *sourcefile, int sourceline)
{
    for (size_t i = 0; i < len; i += strlen((char *)warnings + i) + 1) {
        if (sourcefile) {
            rb_compile_warn(sourcefile, sourceline, "%s", (char *)warnings + i);
        }
        else {
            rb_warn("%s", (char *)warnings + i);
        }
    }
}

/*
 * Called at the top of onig_compile_ruby. Compiles with the Rust engine when
 * it is the default and the pattern uses the Ruby syntax and case folding,
 * filling the regex_t header. Returns false to let Onigmo compile.
 */
int
rb_reg_rust_compile_hook(regex_t *reg, const UChar *pattern, const UChar *pattern_end,
                         OnigErrorInfo *einfo, const char *sourcefile, int sourceline, int *result)
{
    if (!rb_reg_rust_engine_p()) return 0;
    if (reg->syntax != ONIG_SYNTAX_RUBY || reg->case_fold_flag != ONIGENC_CASE_FOLD_DEFAULT) return 0;

    rb_regexp_rust_t *h;
    struct rb_regexp_compile_result res;
    int flags = RB_REGEXP_WARN_ENABLED | (RTEST(ruby_verbose) ? RB_REGEXP_WARN_VERBOSE : 0);
    int r = rb_regexp_rust_compile(pattern, pattern_end - pattern, reg->options, reg->enc, flags, &h, &res);

    if (r == 0) {
        struct rb_regexp_rust_header hd;
        rb_regexp_rust_header(h, &hd);
        reg->options = hd.options;
        reg->num_mem = hd.num_mem;
        reg->case_fold_flag = hd.case_fold_flag;
        reg->reserved1 = (int *)h;
    }
    else if (r != RB_REGEXP_PANICKED && einfo && res.has_par) {
        einfo->enc = reg->enc;
        einfo->par = (UChar *)pattern + res.par_off;
        einfo->par_end = einfo->par + res.par_len;
    }

    /* Ruby code runs from here on: Warning.warn may raise. */
    if (res.warnings_len) {
        unsigned char *w = res.warnings;
        size_t wl = res.warnings_len;
        VALUE buf = rb_str_new((const char *)w, (long)wl);
        rb_regexp_rust_free_bytes(w, wl);
        emit_warnings((unsigned char *)RSTRING_PTR(buf), wl, sourcefile, sourceline);
        RB_GC_GUARD(buf);
    }
    if (r == RB_REGEXP_PANICKED) rust_panicked();

    *result = r;
    return 1;
}

struct rust_check_data {
    regex_t *reg;
    rb_hrtime_t end_time;
    int state;
};

static VALUE
check_ints_body(VALUE arg)
{
    rb_thread_check_ints();
    return Qnil;
}

/* CHECK_INTERRUPT_IN_MATCH_AT for the Rust engine: never longjmps. */
static int
rust_check(void *data)
{
    struct rust_check_data *d = data;
    if (rb_reg_timeout_p(d->reg, &d->end_time)) return ONIGERR_TIMEOUT;
    int state = 0;
    rb_protect(check_ints_body, Qnil, &state);
    if (state) {
        d->state = state;
        return RB_REGEXP_INTERRUPTED;
    }
    return 0;
}

/* The Rust engine has returned; now it is safe to longjmp. */
static OnigPosition
rust_result(OnigPosition r, struct rust_check_data *d)
{
    if (r == RB_REGEXP_INTERRUPTED) rb_jump_tag(d->state);
    if (r == RB_REGEXP_PANICKED) rust_panicked();
    return r;
}

OnigPosition
rb_reg_rust_search(regex_t *reg, const UChar *str, const UChar *end, const UChar *global_pos,
                   const UChar *start, const UChar *range, OnigRegion *region, OnigOptionType option)
{
    struct rust_check_data d = { reg, 0, 0 };
    OnigPosition r = rb_regexp_rust_search(RUST_HANDLE(reg), str, end - str,
                                           global_pos - str, start - str, range - str,
                                           region ? region->beg : NULL, region ? region->end : NULL,
                                           region ? region->num_regs : 0, option, rust_check, &d);
    return rust_result(r, &d);
}

OnigPosition
rb_reg_rust_match(regex_t *reg, const UChar *str, const UChar *end, const UChar *at,
                  OnigRegion *region, OnigOptionType option)
{
    struct rust_check_data d = { reg, 0, 0 };
    OnigPosition r = rb_regexp_rust_match(RUST_HANDLE(reg), str, end - str, at - str,
                                          region ? region->beg : NULL, region ? region->end : NULL,
                                          region ? region->num_regs : 0, option, rust_check, &d);
    return rust_result(r, &d);
}

void
rb_reg_rust_free_body(regex_t *reg)
{
    rb_regexp_rust_free(RUST_HANDLE(reg));
    reg->reserved1 = NULL;
}

size_t
rb_reg_rust_memsize(const regex_t *reg)
{
    return sizeof(regex_t) + rb_regexp_rust_memsize(RUST_HANDLE(reg));
}

int
rb_reg_rust_copy_body(regex_t *nreg, const regex_t *oreg)
{
    *nreg = *oreg;
    nreg->reserved1 = (int *)rb_regexp_rust_copy(RUST_HANDLE(oreg));
    return 0;
}

int
rb_reg_rust_linear_time_p(const regex_t *reg)
{
    return rb_regexp_rust_linear_time_p(RUST_HANDLE(reg));
}

int
rb_reg_rust_number_of_names(const regex_t *reg)
{
    return (int)rb_regexp_rust_name_count(RUST_HANDLE(reg));
}

int
rb_reg_rust_foreach_name(regex_t *reg, int (*func)(const UChar *, const UChar *, int, int *, regex_t *, void *),
                         void *arg)
{
    size_t n = rb_regexp_rust_name_count(RUST_HANDLE(reg));
    for (size_t i = 0; i < n; i++) {
        const unsigned char *name;
        size_t len;
        int ngroups;
        const int *groups;
        if (!rb_regexp_rust_name_at(RUST_HANDLE(reg), i, &name, &len, &ngroups, &groups)) break;
        int r = func(name, name + len, ngroups, (int *)groups, reg, arg);
        if (r != 0) return r;
    }
    return 0;
}

int
rb_reg_rust_name_to_group_numbers(regex_t *reg, const UChar *name, const UChar *name_end, int **nums)
{
    const int *groups;
    int n = rb_regexp_rust_name_find(RUST_HANDLE(reg), name, name_end - name, &groups);
    if (n == 0) return ONIGERR_UNDEFINED_NAME_REFERENCE;
    *nums = (int *)groups;
    return n;
}
#endif
