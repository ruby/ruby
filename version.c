/************************************************

  version.c -

  $Author$
  $Revision$
  $Date$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

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
    fprintf(stderr, "ruby %s(%s) [%s]\n", RUBY_VERSION, VERSION_DATE, RUBY_PLATFORM);
}

void
show_copyright()
{
    fprintf(stderr, "ruby - Copyright (C) 1993-1998 Yukihiro Matsumoto\n");
    exit(0);
}
