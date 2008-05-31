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

#define PRINT(type) puts(ruby_##type)
#define MKSTR(type) rb_obj_freeze(rb_str_new(ruby_##type, sizeof(ruby_##type)-1))

const char ruby_version[] = RUBY_VERSION;
const char ruby_release_date[] = RUBY_RELEASE_DATE;
const char ruby_platform[] = RUBY_PLATFORM;
const int ruby_patchlevel = RUBY_PATCHLEVEL;
const char *ruby_description;
const char *ruby_copyright;

void
Init_version()
{
    static char description[128];
    static char copyright[128];
    VALUE v = MKSTR(version);
    VALUE d = MKSTR(release_date);
    VALUE p = MKSTR(platform);
    VALUE tmp;

    rb_define_global_const("RUBY_VERSION", v);
    rb_define_global_const("RUBY_RELEASE_DATE", d);
    rb_define_global_const("RUBY_PLATFORM", p);
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));

    snprintf(description, sizeof(description), "ruby %s (%s %s %d) [%s]",
             RUBY_VERSION, RUBY_RELEASE_DATE, RUBY_RELEASE_STR,
             RUBY_RELEASE_NUM, RUBY_PLATFORM);
    ruby_description = description;
    tmp = rb_obj_freeze(rb_str_new2(description));
    rb_define_global_const("RUBY_DESCRIPTION", tmp);

    snprintf(copyright, sizeof(copyright), "ruby - Copyright (C) %d-%d %s",
             RUBY_BIRTH_YEAR, RUBY_RELEASE_YEAR, RUBY_AUTHOR);
    ruby_copyright = copyright;
    tmp = rb_obj_freeze(rb_str_new2(copyright));
    rb_define_global_const("RUBY_COPYRIGHT", tmp);

    /* obsolete constants */
    rb_define_global_const("VERSION", v);
    rb_define_global_const("RELEASE_DATE", d);
    rb_define_global_const("PLATFORM", p);
}

void
ruby_show_version()
{
    PRINT(description);
    fflush(stdout);
}

void
ruby_show_copyright()
{
    PRINT(copyright);
    exit(0);
}
