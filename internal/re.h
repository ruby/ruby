#ifndef INTERNAL_RE_H                                    /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Regexp.
 */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/ruby.h"          /* for VALUE */
#include "ruby/re.h"            /* for struct RMatch and struct re_registers */

#define RREGEXP_INITIALIZED FL_USER5

#define RMATCH_ONIG FL_USER1
#define RMATCH_OFFSETS_EXTERNAL FL_USER2

static inline OnigPosition *
RMATCH_BEG_PTR(VALUE match)
{
    if (FL_TEST_RAW(match, RMATCH_ONIG)) {
        return RMATCH(match)->as.onig.beg;
    }
    else {
        return &RMATCH(match)->as.embed[0];
    }
}

static inline OnigPosition *
RMATCH_END_PTR(VALUE match)
{
    if (FL_TEST_RAW(match, RMATCH_ONIG)) {
        return RMATCH(match)->as.onig.end;
    }
    else {
        return &RMATCH(match)->as.embed[RMATCH(match)->num_regs];
    }
}

static inline long
RMATCH_BEG(VALUE match, int i)
{
    return RMATCH_BEG_PTR(match)[i];
}

static inline long
RMATCH_END(VALUE match, int i)
{
    return RMATCH_END_PTR(match)[i];
}

static inline int
RMATCH_NREGS(VALUE match)
{
    return RMATCH(match)->num_regs;
}

/* re.c */
VALUE rb_reg_s_alloc(VALUE klass);
VALUE rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline);
VALUE rb_reg_check_preprocess(VALUE);
long rb_reg_search0(VALUE, VALUE, long, int, int, VALUE *);
VALUE rb_reg_match_p(VALUE re, VALUE str, long pos);
VALUE rb_reg_regsub_match(VALUE str, VALUE src, VALUE match);
VALUE rb_match_init_copy(VALUE copy, VALUE orig);
/* move courier（ractor.c）用の MatchData 転送。 */
void *rb_match_move_dump(VALUE match, VALUE *regexp_out, VALUE *str_out, int *num_regs_out);
VALUE rb_match_move_alloc(VALUE klass, int num_regs);
void rb_match_move_load(VALUE match, VALUE regexp, VALUE str, int num_regs, const void *blob);
void rb_match_move_free(void *blob);
bool rb_reg_start_with_p(VALUE re, VALUE str);
VALUE rb_reg_hash(VALUE re);
VALUE rb_reg_equal(VALUE re1, VALUE re2);
VALUE rb_backref_set_string(VALUE string, long pos, long len);
void rb_match_unbusy(VALUE);
int rb_match_count(VALUE match);
VALUE rb_reg_new_from_values(long cnt, const VALUE *elements, int opt);
VALUE rb_reg_last_defined(VALUE match);

#define ARG_REG_OPTION_MASK \
    (ONIG_OPTION_IGNORECASE|ONIG_OPTION_MULTILINE|ONIG_OPTION_EXTEND)
#define ARG_ENCODING_FIXED    16
#define ARG_ENCODING_NONE     32

#endif /* INTERNAL_RE_H */
