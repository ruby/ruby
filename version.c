/**********************************************************************

  version.c -

  $Author$
  $Date$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#define RUBY_VERSION_C 1
#include "version.h"
#include <stdio.h>

#define PRINT(type) puts(TOKEN_PASTE(ruby_,type))
#ifndef rb_str_new_cstr
#define rb_str_new_cstr(str) rb_str_new(str, strlen(str))
#endif
#define MKSTR(type) rb_obj_freeze(rb_str_new(TOKEN_PASTE(ruby_,type), sizeof(TOKEN_PASTE(ruby_,type))-1))
#ifndef UNALIGNED
#ifdef __GNUC__
#define UNALIGNED __attribute__((aligned(1)))
#else
#define UNALIGNED
#endif
#endif

const int ruby_patchlevel = RUBY_PATCHLEVEL;
const char ruby_version[] = RUBY_VERSION;
const char ruby_release_date[] = RUBY_RELEASE_DATE;
const char ruby_platform[] = RUBY_PLATFORM;
#ifdef RUBY_DESCRIPTION
const char ruby_description[] = RUBY_DESCRIPTION;
#else
const struct {
    char ruby[sizeof("ruby ")-1];
    char version[sizeof(RUBY_VERSION)-1];
    char patchlevel[sizeof(RUBY_PATCHLEVEL_STR)-1];
    char pad1[2];
    char release_date[sizeof(RUBY_RELEASE_DATE)-1];
#if RUBY_REVISION
    char revision[sizeof(RUBY_REVISION_STR)-1];
#endif
    char pad2[3];
    char platform[sizeof(RUBY_PLATFORM)-1];
    char pad3[2];
} ruby_description[1] UNALIGNED = {
    {
	"ruby ", RUBY_VERSION, RUBY_PATCHLEVEL_STR,
	" (", RUBY_RELEASE_DATE,
#if RUBY_REVISION
	RUBY_REVISION_STR,
#endif
	") [",
	RUBY_PLATFORM, "]"
    }
};
#define ruby_description (*(const char (*)[sizeof(ruby_description)])ruby_description)
#endif

#ifdef RUBY_COPYRIGHT
const char ruby_copyright[] = RUBY_COPYRIGHT;
#else
const struct {
    char ruby[21];
    char birth[4];
    char pad1[1];
    char release[sizeof(STRINGIZE(RUBY_RELEASE_YEAR))-1];
    char pad2[1];
    char author[sizeof(RUBY_AUTHOR)];
} ruby_copyright[1] UNALIGNED = {
    {
	"ruby - Copyright (C) ",
	STRINGIZE(RUBY_BIRTH_YEAR), "-", STRINGIZE(RUBY_RELEASE_YEAR),
	" ", RUBY_AUTHOR
    }
};
#define ruby_copyright (*(const char (*)[sizeof(ruby_copyright[0])])ruby_copyright)
#endif

const struct ruby_initial_loadpath {
#ifdef RUBY_SEARCH_PATH
    char search_path[sizeof(RUBY_SEARCH_PATH)];
#endif
    char site_lib2[sizeof(RUBY_SITE_LIB2)];
#ifdef RUBY_SITE_THIN_ARCHLIB
    char site_thin_archlib[sizeof(RUBY_SITE_THIN_ARCHLIB)];
#endif
    char site_archlib[sizeof(RUBY_SITE_ARCHLIB)];
    char site_lib[sizeof(RUBY_SITE_LIB)];

    char vendor_lib2[sizeof(RUBY_VENDOR_LIB2)];
#ifdef RUBY_VENDOR_THIN_ARCHLIB
    char vendor_thin_archlib[sizeof(RUBY_VENDOR_THIN_ARCHLIB)];
#endif
    char vendor_archlib[sizeof(RUBY_VENDOR_ARCHLIB)];
    char vendor_lib[sizeof(RUBY_VENDOR_LIB)];

    char lib[sizeof(RUBY_LIB)];
#ifdef RUBY_THIN_ARCHLIB
    char thin_archlib[sizeof(RUBY_THIN_ARCHLIB)];
#endif
    char archlib[sizeof(RUBY_ARCHLIB)];
    char terminator[1];
} ruby_initial_load_paths UNALIGNED = {
#ifdef RUBY_SEARCH_PATH
    RUBY_SEARCH_PATH,
#endif
    RUBY_SITE_LIB2,
#ifdef RUBY_SITE_THIN_ARCHLIB
    RUBY_SITE_THIN_ARCHLIB,
#endif
    RUBY_SITE_ARCHLIB,
    RUBY_SITE_LIB,

    RUBY_VENDOR_LIB2,
#ifdef RUBY_VENDOR_THIN_ARCHLIB
    RUBY_VENDOR_THIN_ARCHLIB,
#endif
    RUBY_VENDOR_ARCHLIB,
    RUBY_VENDOR_LIB,

    RUBY_LIB,
#ifdef RUBY_THIN_ARCHLIB
    RUBY_THIN_ARCHLIB,
#endif
    RUBY_ARCHLIB,
    ""
};

void
Init_version()
{
    VALUE v = MKSTR(version);
    VALUE d = MKSTR(release_date);
    VALUE p = MKSTR(platform);

    rb_define_global_const("RUBY_VERSION", v);
    rb_define_global_const("RUBY_RELEASE_DATE", d);
    rb_define_global_const("RUBY_PLATFORM", p);
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));
    rb_define_global_const("RUBY_REVISION", INT2FIX(RUBY_REVISION));
    rb_define_global_const("RUBY_DESCRIPTION", MKSTR(description));
    rb_define_global_const("RUBY_COPYRIGHT", MKSTR(copyright));

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
