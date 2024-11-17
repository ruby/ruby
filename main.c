/**********************************************************************

  main.c -

  $Author$
  created at: Fri Aug 19 13:19:58 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

/*!
 * \mainpage Developers' documentation for Ruby
 *
 * This documentation is produced by applying Doxygen to
 * <a href="https://github.com/ruby/ruby">Ruby's source code</a>.
 * It is still under construction (and even not well-maintained).
 * If you are familiar with Ruby's source code, please improve the doc.
 */
#undef RUBY_EXPORT
#include "ruby.h"
#include "vm_debug.h"
#ifdef HAVE_LOCALE_H
#include <locale.h>
#endif
#if defined RUBY_DEVEL && !defined RUBY_DEBUG_ENV
# define RUBY_DEBUG_ENV 1
#endif
#if defined RUBY_DEBUG_ENV && !RUBY_DEBUG_ENV
# undef RUBY_DEBUG_ENV
#endif

static int
rb_main(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

#if defined(__wasm__) && !defined(__EMSCRIPTEN__)
int rb_wasm_rt_start(int (main)(int argc, char **argv), int argc, char **argv);
#define rb_main(argc, argv) rb_wasm_rt_start(rb_main, argc, argv)
#endif

#ifdef _WIN32
#define main(argc, argv) w32_main(argc, argv)
static int main(int argc, char **argv);
int wmain(void) {return main(0, NULL);}
#endif

int
main(int argc, char **argv)
{
#ifdef RUBY_DEBUG_ENV
    ruby_set_debug_option(getenv("RUBY_DEBUG"));
#endif
#ifdef HAVE_LOCALE_H
    setlocale(LC_CTYPE, "");
#endif

    ruby_sysinit(&argc, &argv);
    return rb_main(argc, argv);
}
