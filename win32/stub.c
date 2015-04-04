#include <ruby.h>
static void stub_sysinit(int *argc, char ***argv);
#define ruby_sysinit stub_sysinit
#include <main.c>
#undef ruby_sysinit

void
stub_sysinit(int *argc, char ***argv)
{
    WCHAR exename[4096];
    size_t wlenexe, len0, lenall;
    int lenexe;
    int i, ac;
    char **av, *p;

    wlenexe = (size_t)GetModuleFileNameW(NULL, exename, sizeof(exename) / sizeof(*exename));
    lenexe = WideCharToMultiByte(CP_UTF8, 0, exename, wlenexe, NULL, 0, NULL, NULL);
    ruby_sysinit(argc, argv);
    ac = *argc;
    av = *argv;
    len0 = strlen(av[0]) + 1;
    lenall = 0;
    for (i = 1; i < ac; ++i) {
	lenall += strlen(av[i]) + 1;
    }
    av = realloc(av, lenall + len0 + (lenexe + 1) + sizeof(char *) * (i + 2));
    if (!av) {
	perror("realloc command line");
	exit(-1);
    }
    *argv = av;
    *argc = ++ac;
    p = (char *)(av + i + 2);
    memmove(p + len0 + lenexe + 1, (char *)(av + ac) + len0, lenall);
    memmove(p, (char *)(av + ac), len0);
    *av++ = p;
    p += len0;
    WideCharToMultiByte(CP_UTF8, 0, exename, wlenexe, p, lenexe, NULL, NULL);
    p[lenexe] = '\0';
    *av++ = p;
    p += lenexe + 1;
    while (--i) {
	*av++ = p;
	p += strlen(p) + 1;
    }
    *av = NULL;
}

