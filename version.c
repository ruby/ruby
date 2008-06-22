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
#if !NO_STRING_LITERAL_CONCATENATION
const char ruby_description[] = RUBY_DESCRIPTION;
const char ruby_copyright[] = RUBY_COPYRIGHT;
#else
char ruby_description[128];
char ruby_copyright[128];
#endif

void
Init_version()
{
    VALUE v = MKSTR(version);
    VALUE d = MKSTR(release_date);
    VALUE p = MKSTR(platform);
#if NO_STRING_LITERAL_CONCATENATION
    VALUE tmp;
#endif

    rb_define_global_const("RUBY_VERSION", v);
    rb_define_global_const("RUBY_RELEASE_DATE", d);
    rb_define_global_const("RUBY_PLATFORM", p);
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));
    rb_define_global_const("RUBY_REVISION", INT2FIX(RUBY_REVISION));
    rb_define_global_const("RUBY_DESCRIPTION", MKSTR(description));
    rb_define_global_const("RUBY_COPYRIGHT", MKSTR(copyright));

#if NO_STRING_LITERAL_CONCATENATION
    snprintf(ruby_description, sizeof(ruby_description), "ruby %s (%s %s %d) [%s]",
             RUBY_VERSION, RUBY_RELEASE_DATE, RUBY_RELEASE_STR,
             RUBY_RELEASE_NUM, RUBY_PLATFORM);
    tmp = rb_obj_freeze(rb_str_new2(ruby_description));
    rb_define_global_const("RUBY_DESCRIPTION", tmp);

    snprintf(ruby_copyright, sizeof(ruby_copyright), "ruby - Copyright (C) %d-%d %s",
             RUBY_BIRTH_YEAR, RUBY_RELEASE_YEAR, RUBY_AUTHOR);
    tmp = rb_obj_freeze(rb_str_new2(ruby_copyright));
    rb_define_global_const("RUBY_COPYRIGHT", tmp);
#endif

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

