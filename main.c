/************************************************

  main.c -

  $Author$
  $Date$
  created at: Fri Aug 19 13:19:58 JST 1994

************************************************/

#include "ruby.h"

#ifdef DJGPP
unsigned int _stklen = 0x180000;
#endif

#ifdef __human68k__
int _stacksize = 131072;
#endif

#if defined(__MACOS__) && defined(__MWERKS__)
#include <console.h>
#endif

int
main(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
#if defined(NT)
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
