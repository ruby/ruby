/************************************************

  version.c -

  $Author: matz $
  $Revision: 1.5 $
  $Date: 1995/01/12 08:54:54 $
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "version.h"
#include <stdio.h>

extern VALUE C_Kernel;

Init_version()
{
    rb_define_const(C_Kernel, "VERSION", str_new2(RUBY_VERSION));
}

show_version()
{
    fprintf(stderr, "ruby - version %s (%s)\n", RUBY_VERSION, VERSION_DATE);
}

show_copyright()
{
    fprintf(stderr, "ruby - Copyright (C) 1995 Yukihiro Matsumoto\n");
    exit(0);
}
