/************************************************

  re.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:52 $
  created at: Thu Sep 30 14:18:32 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#ifndef RE_H
#define RE_H

#include <sys/types.h>
#include <stdio.h>

#include "regex.h"

typedef struct re_pattern_buffer Regexp;

struct match {
    UINT len;
    char *ptr;
    struct re_registers regs;
};

extern struct match last_match;

#define BEG(no) last_match.regs.beg[no]
#define END(no) last_match.regs.end[no]

VALUE re_regcomp();
VALUE re_regsub();
#endif
