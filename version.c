/************************************************

  version.c -

  $Author: matz $
  $Revision: 1.5 $
  $Date: 1996/12/25 08:54:54 $
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "version.h"
#include <stdio.h>

void
Init_version()
{
    rb_define_global_const("VERSION", str_new2(RUBY_VERSION));
    rb_define_global_const("PLATFORM", str_new2(RUBY_PLATFORM));
}

void
show_version()
{
    fprintf(stderr, "ruby - version %s (%s)\n", RUBY_VERSION, RUBY_PLATFORM);
}

void
show_copyright()
{
    fprintf(stderr, "ruby - Copyright (C) 1993-1997 Yukihiro Matsumoto\n");
    exit(0);
}
