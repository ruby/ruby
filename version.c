/**********************************************************************

  version.c -

  $Author$
  created at: Thu Sep 30 20:08:01 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "version.h"
#include <stdio.h>

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif

#define PRINT(type) puts(ruby_##type)
#define MKSTR(type) rb_obj_freeze(rb_usascii_str_new(ruby_##type, sizeof(ruby_##type)-1))

const int ruby_api_version[] = {
    RUBY_API_VERSION_MAJOR,
    RUBY_API_VERSION_MINOR,
    RUBY_API_VERSION_TEENY,
};
const char ruby_version[] = RUBY_VERSION;
const char ruby_release_date[] = RUBY_RELEASE_DATE;
const char ruby_platform[] = RUBY_PLATFORM;
const int ruby_patchlevel = RUBY_PATCHLEVEL;
const char ruby_description[] = RUBY_DESCRIPTION;
const char ruby_copyright[] = RUBY_COPYRIGHT;
const char ruby_engine[] = "ruby";
VALUE ruby_engine_name = Qnil;

/*! Defines platform-depended Ruby-level constants */
void
Init_version(void)
{
    /*
     * The running version of ruby
     */
    rb_define_global_const("RUBY_VERSION", MKSTR(version));
    /*
     * The date this ruby was released
     */
    rb_define_global_const("RUBY_RELEASE_DATE", MKSTR(release_date));
    /*
     * The platform for this ruby
     */
    rb_define_global_const("RUBY_PLATFORM", MKSTR(platform));
    /*
     * The patchlevel for this ruby.  If this is a development build of ruby
     * the patchlevel will be -1
     */
    rb_define_global_const("RUBY_PATCHLEVEL", INT2FIX(RUBY_PATCHLEVEL));
    /*
     * The SVN revision for this ruby.
     */
    rb_define_global_const("RUBY_REVISION", INT2FIX(RUBY_REVISION));
    /*
     * The full ruby version string, like <tt>ruby -v</tt> prints'
     */
    rb_define_global_const("RUBY_DESCRIPTION", MKSTR(description));
    /*
     * The copyright string for ruby
     */
    rb_define_global_const("RUBY_COPYRIGHT", MKSTR(copyright));
    /*
     * The engine or interpreter this ruby uses.
     */
    rb_define_global_const("RUBY_ENGINE", ruby_engine_name = MKSTR(engine));
}

/*! Prints the version information of the CRuby interpreter to stdout. */
void
ruby_show_version(void)
{
    PRINT(description);
    fflush(stdout);
}

/*! Prints the copyright notice of the CRuby interpreter to stdout and \em exits
 *  this process successfully.
 */
void
ruby_show_copyright(void)
{
    PRINT(copyright);
    exit(EXIT_SUCCESS);
}
