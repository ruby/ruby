/************************************************

  main.c -

  $Author: matz $
  $Date: 1994/08/19 09:32:03 $
  created at: Fri Aug 19 13:19:58 JST 1994

************************************************/

#ifdef DJGPP
unsigned int _stklen = 0x100000;
#endif

void
main(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
    ruby_init(argc, argv, envp);
    ruby_run();
}
