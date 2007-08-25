/**********************************************************************

  main.c -

  $Author$
  $Date$
  created at: Fri Aug 19 13:19:58 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#undef RUBY_EXPORT
#include "ruby/ruby.h"

#if defined(__MACOS__) && defined(__MWERKS__)
#include <console.h>
#endif

/* to link startup code with ObjC support */
#if (defined(__APPLE__) || defined(__NeXT__)) && defined(__MACH__)
static void
objcdummyfunction(void)
{
    objc_msgSend();
}
#endif

int
main(int argc, char **argv, char **envp)
{
#ifdef RUBY_DEBUG_ENV
    extern void ruby_set_debug_option(const char *);
    ruby_set_debug_option(getenv("RUBY_DEBUG"));
#endif
#ifdef _WIN32
    NtInitialize(&argc, &argv);
#endif
#if defined(__MACOS__) && defined(__MWERKS__)
    argc = ccommand(&argv);
#endif

    {
	RUBY_INIT_STACK;
	ruby_init();
	return ruby_run_node(ruby_options(argc, argv));
    }
}
