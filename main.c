/************************************************

  main.c -

  $Author: matz $
  $Date: 1996/12/25 09:32:03 $
  created at: Fri Aug 19 13:19:58 JST 1994

************************************************/

#include "ruby.h"

#ifdef DJGPP
unsigned int _stklen = 0x100000;
#endif

#ifdef __human68k__
int _stacksize = 131072;
#endif

int
main(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
#if defined(NT)
    NtInitialize(&argc, &argv);
#endif

    ruby_init();
    ruby_options(argc, argv);
    ruby_run();
}
