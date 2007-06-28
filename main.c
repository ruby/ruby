/**********************************************************************

  main.c -

  $Author$
  $Date$
  created at: Fri Aug 19 13:19:58 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

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
    RUBY_EXTERN int gc_stress;
    RUBY_EXTERN int enable_coredump;
    char *str;
    str = getenv("RUBY_DEBUG");
    if (str) {
        for (str = strtok(str, ","); str; str = strtok(NULL, ",")) {
            if (strcmp(str, "gc_stress") == 0)
              gc_stress = 1;
            else if (strcmp(str, "core") == 0)
              enable_coredump = 1;
            else
              fprintf(stderr, "unexpected debug option: %s\n", str);
        }
    }
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
	ruby_options(argc, argv);
	ruby_run();
    }
    return 0;
}
