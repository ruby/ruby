/************************************************

  main.c -

  $Author: matz $
  $Date: 1996/12/25 09:32:03 $
  created at: Fri Aug 19 13:19:58 JST 1994

************************************************/

#ifdef DJGPP
unsigned int _stklen = 0x100000;
#endif

#ifdef __human68k__
int _stacksize = 131072;
#endif

#if (_MSC_VER  >= 1000)
__declspec(dllexport) void __stdcall ruby_init();
__declspec(dllexport) void __stdcall ruby_options(int, char *[]);
__declspec(dllexport) void __stdcall ruby_run(void);
__declspec(dllexport) void __stdcall NtInitialize(int *, char ***);
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
