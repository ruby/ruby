#include "prism/extension.h"

void ruby_init_ext(const char *name, void (*init)(void));
void rb_autoload_str(VALUE mod, ID id, VALUE file);

/*
 * The prism parser is linked into the interpreter and exposed as the
 * Ruby::Prism module. It is the very parser that parsed the running
 * code, independent of any version of the prism gem that may be installed.
 *
 * `require "ruby/prism"` loads the Ruby part of the library
 * (lib/ruby/prism.rb), which in turn requires "ruby/prism/prism", the
 * statically linked extension registered here.
 */
void
Init_Prism(void)
{
#if 0 /* for RDoc; Ruby::Prism is defined by lib/ruby/prism.rb via autoload */
    VALUE rb_mRuby = rb_define_module("Ruby");
    /*
     * Document-module: Ruby::Prism
     *
     * \Ruby::Prism is the prism parser built into the interpreter, i.e., the
     * very parser that parsed the running program.
     *
     * Its API follows the version of prism bundled with this Ruby, and may
     * change incompatibly between Ruby minor versions: not only the node
     * definitions but also the other APIs, as the bundled prism may move to a
     * new major version.
     *
     * In most cases, use the prism gem instead.  Use \Ruby::Prism only when you
     * need the very parser of the running interpreter.
     */
    VALUE rb_mPrism = rb_define_module_under(rb_mRuby, "Prism");
#endif
    ruby_init_ext("ruby/prism/prism.so", Init_prism);
}

/*
 * Set up the autoload of Ruby::Prism, so that programs that do not use it
 * pay nothing. This is called after the command line options are processed,
 * and only when prism is the parser that parses the program: with
 * --parser=parse.y, Ruby::Prism is not defined.
 */
void
rb_prism_init_autoload(void)
{
    rb_autoload_str(rb_define_module("Ruby"), rb_intern("Prism"), rb_str_new_cstr("ruby/prism"));
}
