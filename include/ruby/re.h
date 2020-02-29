/**********************************************************************

  re.h -

  $Author$
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_RE_H
#define RUBY_RE_H 1

#include "ruby/3/config.h"
#include <sys/types.h>
#include <stdio.h>

#include "ruby/regex.h"
#include "ruby/3/core/rmatch.h"
#include "ruby/3/dllexport.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

VALUE rb_reg_regcomp(VALUE);
long rb_reg_search(VALUE, VALUE, long, int);
VALUE rb_reg_regsub(VALUE, VALUE, struct re_registers *, VALUE);
long rb_reg_adjust_startpos(VALUE, VALUE, long, int);
void rb_match_busy(VALUE);
VALUE rb_reg_quote(VALUE);
regex_t *rb_reg_prepare_re(VALUE re, VALUE str);
int rb_reg_region_copy(struct re_registers *, const struct re_registers *);

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY_RE_H */
