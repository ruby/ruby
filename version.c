/**********************************************************************

  version.c -

  $Author$
  $Date$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "version.h"
#include <stdio.h>

void
Init_version()
{
    VALUE v = rb_obj_freeze(rb_str_new2(RUBY_VERSION));
    VALUE d = rb_obj_freeze(rb_str_new2(RUBY_RELEASE_DATE));
    VALUE p = rb_obj_freeze(rb_str_new2(RUBY_PLATFORM));

    rb_define_global_const("RUBY_VERSION", v);
    rb_define_global_const("RUBY_RELEASE_DATE", d);
    rb_define_global_const("RUBY_PLATFORM", p);

    /* obsolete constants */
    rb_define_global_const("VERSION", v);
    rb_define_global_const("RELEASE_DATE", d);
    rb_define_global_const("PLATFORM", p);
}

void
ruby_show_version()
{
    printf("ruby %s (%s) [%s]\n", RUBY_VERSION, RUBY_RELEASE_DATE, RUBY_PLATFORM);
}

void
ruby_show_copyright()
{
    printf("ruby - Copyright (C) 1993-2002 Yukihiro Matsumoto\n");
    exit(0);
}
