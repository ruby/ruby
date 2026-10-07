#include "prism/extension.h"

void ruby_init_ext(const char *name, void (*init)(void));
void rb_autoload_str(VALUE mod, ID id, VALUE file);

/*
 * The prism parser is linked into the interpreter and exposed as the
 * Ruby::Prism module. It is the very parser that compiled the running
 * code, independent of any version of the prism gem that may be installed.
 *
 * `require "ruby/prism"` loads the Ruby part of the library
 * (lib/ruby/prism.rb), which in turn requires "ruby/prism/prism", the
 * statically linked extension registered here.
 */
void
Init_Prism(void)
{
    ruby_init_ext("ruby/prism/prism.so", Init_prism);
}

/*
 * Set up the autoload of Ruby::Prism, so that programs that do not use it
 * pay nothing. This is called after the command line options are processed,
 * and only when prism is the parser that compiles the program: with
 * --parser=parse.y, Ruby::Prism is not defined.
 */
void
rb_prism_init_autoload(void)
{
    rb_autoload_str(rb_define_module("Ruby"), rb_intern("Prism"), rb_str_new_cstr("ruby/prism"));
}
