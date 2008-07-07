/**********************************************************************

  version.c -

  $Author$
  $Date$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "version.h"
#include <stdio.h>

const char ruby_version[] = RUBY_VERSION;
const char ruby_release_date[] = RUBY_RELEASE_DATE;
const char ruby_platform[] = RUBY_PLATFORM;
const int ruby_patchlevel = RUBY_PATCHLEVEL;

void
Init_version()
{
    VALUE v = rb_obj_freeze(rb_str_new2(ruby_version));
    VALUE d = rb_obj_freeze(rb_str_new2(ruby_release_date));
    VALUE p = rb_obj_freeze(rb_str_new2(ruby_platform));

    rb_define_global_const("RUBY_VERSION", v);
    rb_define_global_const("RUBY_RELEASE_DATE", d);
    rb_define_global_const("RUBY_PLATFORM", p);
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));

    /* obsolete constants */
    rb_define_global_const("VERSION", v);
    rb_define_global_const("RELEASE_DATE", d);
    rb_define_global_const("PLATFORM", p);
}

void
ruby_show_version()
{
    printf("ruby %s (%s patchlevel %d) [%s]\n", RUBY_VERSION, RUBY_RELEASE_DATE, RUBY_PATCHLEVEL, RUBY_PLATFORM);
    fflush(stdout);
}

void
ruby_show_copyright()
{
    printf("ruby - Copyright (C) 1993-%d Yukihiro Matsumoto\n", RUBY_RELEASE_YEAR);
    exit(0);
}
