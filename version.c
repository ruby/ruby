/************************************************

  version.c -

  $Author: matz $
  $Revision: 1.5 $
  $Date: 1995/01/12 08:54:54 $
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "version.h"
#include <stdio.h>

static VALUE rb_version;

VALUE rb_readonly_hook();

Init_version()
{
    rb_version = str_new2(RUBY_VERSION);
    rb_define_variable("$VERSION", &rb_version, Qnil, rb_readonly_hook, 0);
}

show_version()
{
    fprintf(stderr, "ruby - version %s (%s)\n", RUBY_VERSION, VERSION_DATE);
}

show_copyright()
{
    fprintf(stderr, "ruby - Copyright (C) 1994 Yukihiro Matsumoto\n");
    exit(0);
}
