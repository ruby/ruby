/************************************************

  re.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:52 $
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#ifndef RE_H
#define RE_H

#include <sys/types.h>
#include <stdio.h>

#include "regex.h"

typedef struct re_pattern_buffer Regexp;

struct RMatch {
    struct RBasic basic;
    UINT len;
    char *ptr;
    struct re_registers *regs;
};

#define RMATCH(obj)  (R_CAST(RMatch)(obj))

VALUE re_regcomp();
VALUE re_regsub();
#endif
