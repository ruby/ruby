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
#include "internal/sanitizers.h"
#ifdef HAVE_LOCALE_H
#include <locale.h>
#endif
#if USE_SHARED_GC
#include "internal/gc.h"
#endif

#if defined RUBY_DEVEL && !defined RUBY_DEBUG_ENV
# define RUBY_DEBUG_ENV 1
#endif
#if defined RUBY_DEBUG_ENV && !RUBY_DEBUG_ENV
# undef RUBY_DEBUG_ENV
#endif

#if USE_MMTK
#include "internal/mmtk_support.h"
#endif

void ruby_load_external_gc_from_argv(int argc, char **argv);

static int
rb_main(int argc, char **argv)
{
    RUBY_INIT_STACK;
#if USE_MMTK
    rb_mmtk_pre_process_opts(argc, argv);
#endif
#if USE_SHARED_GC
    ruby_load_external_gc_from_argv(argc, argv);
#endif
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

#if defined(__wasm__) && !defined(__EMSCRIPTEN__)
int rb_wasm_rt_start(int (main)(int argc, char **argv), int argc, char **argv);
#define rb_main(argc, argv) rb_wasm_rt_start(rb_main, argc, argv)
#endif

int
main(int argc, char **argv)
{
#if defined(RUBY_DEBUG_ENV) || USE_RUBY_DEBUG_LOG
    ruby_set_debug_option(getenv("RUBY_DEBUG"));
#endif
#ifdef HAVE_LOCALE_H
    setlocale(LC_CTYPE, "");
#endif

    ruby_sysinit(&argc, &argv);
    return rb_main(argc, argv);
}

#ifdef RUBY_ASAN_ENABLED
/* Compile in the ASAN options Ruby needs, rather than relying on environment variables, so
 * that even tests which fork ruby with a clean environment will run ASAN with the right
 * settings */
const char *
__asan_default_options(void)
{
    return "use_sigaltstack=0:detect_leaks=0";
}
#endif
