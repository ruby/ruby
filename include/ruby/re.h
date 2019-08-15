/**********************************************************************

  re.h -

  $Author$
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_RE_H
#define RUBY_RE_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include <sys/types.h>
#include <stdio.h>

#include "ruby/regex.h"

RUBY_SYMBOL_EXPORT_BEGIN

typedef struct re_pattern_buffer Regexp;

struct rmatch_offset {
    long beg;
    long end;
};

struct rmatch {
    struct re_registers regs;

    struct rmatch_offset *char_offset;
    int char_offset_num_allocated;
};

struct RMatch {
    struct RBasic basic;
    VALUE str;
    struct rmatch *rmatch;
    VALUE regexp;  /* RRegexp */
};

#define RMATCH(obj)  (R_CAST(RMatch)(obj))
#define RMATCH_REGS(obj)  (&(R_CAST(RMatch)(obj))->rmatch->regs)

VALUE rb_reg_regcomp(VALUE);
long rb_reg_search(VALUE, VALUE, long, int);
VALUE rb_reg_regsub(VALUE, VALUE, struct re_registers *, VALUE);
long rb_reg_adjust_startpos(VALUE, VALUE, long, int);
void rb_match_busy(VALUE);
VALUE rb_reg_quote(VALUE);
regex_t *rb_reg_prepare_re(VALUE re, VALUE str);
int rb_reg_region_copy(struct re_registers *, const struct re_registers *);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_RE_H */
