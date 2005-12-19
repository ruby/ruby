/**********************************************************************

  main.c -

  $Author$
  $Date$
  created at: Fri Aug 19 13:19:58 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#undef RUBY_EXPORT
#include "ruby.h"

#if defined(__MACOS__) && defined(__MWERKS__)
#include <console.h>
#endif

/* to link startup code with ObjC support */
#if (defined(__APPLE__) || defined(__NeXT__)) && defined(__MACH__)
static void objcdummyfunction( void ) { objc_msgSend(); }
#endif

int
main(int argc, char **argv, char **envp)
{
#ifdef RUBY_GC_DEBUG
    RUBY_EXTERN int always_gc;
    always_gc = getenv("RUBY_ALWAYS_GC") != NULL;
#endif
#ifdef _WIN32
    NtInitialize(&argc, &argv);
#endif
#if defined(__MACOS__) && defined(__MWERKS__)
    argc = ccommand(&argv);
#endif

    ruby_init();
    ruby_options(argc, argv);
    ruby_run();
    return 0;
}
