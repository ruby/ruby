/************************************************

  version.c -

  $Author: matz $
  $Revision: 1.1.1.1 $
  $Date: 1994/06/17 14:23:51 $
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
    rb_define_variable("$VERSION", &rb_version, Qnil, rb_readonly_hook);
}

show_version()
{
    printf("ruby - version %s (%s)\n", RUBY_VERSION, VERSION_DATE);
}
