/************************************************

  re.h -

  $Author$
  $Date$
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#ifndef RE_H
#define RE_H

#include <sys/types.h>
#include <stdio.h>

#include "regex.h"

typedef struct re_pattern_buffer Regexp;

struct RMatch {
    struct RBasic basic;
    VALUE str;
    struct re_registers *regs;
};

#define RMATCH(obj)  (R_CAST(RMatch)(obj))

int rb_str_cicmp _((VALUE, VALUE));
VALUE rb_reg_regcomp _((VALUE));
int rb_reg_search _((VALUE, VALUE, int, int));
VALUE rb_reg_regsub _((VALUE, VALUE, struct re_registers *));

int rb_kcode _((void));

extern int ruby_ignorecase;

int rb_mbclen2 _((unsigned int, VALUE));
#define mbclen2(c,re) rb_mbclen2((c),(re))
#endif
