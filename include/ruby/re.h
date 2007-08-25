/**********************************************************************

  re.h -

  $Author$
  $Date$
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

typedef struct re_pattern_buffer Regexp;

struct RMatch {
    struct RBasic basic;
    VALUE str;
    struct re_registers *regs;
    VALUE regexp;  /* RRegexp */
};

#define RMATCH(obj)  (R_CAST(RMatch)(obj))

VALUE rb_reg_regcomp(VALUE);
long rb_reg_search(VALUE, VALUE, long, long);
VALUE rb_reg_regsub(VALUE, VALUE, struct re_registers *, VALUE);
long rb_reg_adjust_startpos(VALUE, VALUE, long, long);
void rb_match_busy(VALUE);
VALUE rb_reg_quote(VALUE);

RUBY_EXTERN int ruby_ignorecase;

int rb_reg_mbclen2(unsigned int, VALUE);
#define mbclen2(c,re) rb_reg_mbclen2((c),(re))

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_RE_H */
