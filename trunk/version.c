/**********************************************************************

  version.c -

  $Author$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "version.h"
#include <stdio.h>

#define PRINT(type) puts(ruby_##type)
#define MKSTR(type) rb_obj_freeze(rb_usascii_str_new(ruby_##type, sizeof(ruby_##type)-1))

const char ruby_version[] = RUBY_VERSION;
const char ruby_release_date[] = RUBY_RELEASE_DATE;
const char ruby_platform[] = RUBY_PLATFORM;
const int ruby_patchlevel = RUBY_PATCHLEVEL;
const char ruby_description[] = RUBY_DESCRIPTION;
const char ruby_copyright[] = RUBY_COPYRIGHT;
const char ruby_engine[] = "ruby";

void
Init_version(void)
{
    rb_define_global_const("RUBY_VERSION", MKSTR(version));
    rb_define_global_const("RUBY_RELEASE_DATE", MKSTR(release_date));
    rb_define_global_const("RUBY_PLATFORM", MKSTR(platform));
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));
    rb_define_global_const("RUBY_REVISION", INT2FIX(RUBY_REVISION));
    rb_define_global_const("RUBY_DESCRIPTION", MKSTR(description));
    rb_define_global_const("RUBY_COPYRIGHT", MKSTR(copyright));
    rb_define_global_const("RUBY_ENGINE", MKSTR(engine));
}

void
ruby_show_version(void)
{
    PRINT(description);
    fflush(stdout);
}

void
ruby_show_copyright(void)
{
    PRINT(copyright);
    exit(0);
}
