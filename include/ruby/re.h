#ifndef RUBY_RE_H                                    /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RE_H 1
/**
 * @file
 * @author     $Author$
 * @date       Thu Sep 30 14:18:32 JST 1993
 * @copyright  Copyright (C) 1993-2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/config.h"
#include <sys/types.h>
#include <stdio.h>

#include "ruby/regex.h"
#include "ruby/internal/core/rmatch.h"
#include "ruby/internal/dllexport.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

VALUE rb_reg_regcomp(VALUE);
long rb_reg_search(VALUE, VALUE, long, int);
VALUE rb_reg_regsub(VALUE, VALUE, struct re_registers *, VALUE);
long rb_reg_adjust_startpos(VALUE, VALUE, long, int);
void rb_match_busy(VALUE);
VALUE rb_reg_quote(VALUE);
regex_t *rb_reg_prepare_re(VALUE re, VALUE str);
int rb_reg_region_copy(struct re_registers *, const struct re_registers *);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_RE_H */
