/************************************************

  re.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:52 $
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#ifndef RE_H
#define RE_H

#include <sys/types.h>
#include <stdio.h>

#include "regex.h"
typedef struct Regexp {
        struct re_pattern_buffer pat;
        struct re_registers regs;
} Regexp;

VALUE re_regcomp();
VALUE re_regsub();
#endif
