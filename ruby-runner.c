#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ruby-runner.h"

#define STRINGIZE(expr) STRINGIZE0(expr)
#define STRINGIZE0(expr) #expr

int
main(int argc, char **argv)
{
    static const char builddir[] = BUILDDIR;
    static const char rubypath[] = BUILDDIR"/"STRINGIZE(RUBY_INSTALL_NAME);
    const size_t dirsize = sizeof(builddir);
    const size_t namesize = sizeof(rubypath) - dirsize;
    const char *rubyname = rubypath + dirsize;
    char *arg0 = argv[0], *p;
    const char *libpath = getenv(LIBPATHENV);
    char c = 0;

    if (libpath) {
	while ((c = *libpath) == PATH_SEP) ++libpath;
    }
    if (c) {
	size_t n = strlen(libpath);
	char *e = malloc(dirsize+n+1);
	memcpy(e, builddir, dirsize-1);
	e[dirsize-1] = PATH_SEP;
	memcpy(e+dirsize, libpath, n+1);
	libpath = e;
    }
    else {
	libpath = builddir;
    }
    setenv(LIBPATHENV, libpath, 1);

    if (!(p = strrchr(arg0, '/'))) p = arg0; else p++;
    if (strlen(p) < namesize - 1) {
	argv[0] = malloc(p - arg0 + namesize);
	memcpy(argv[0], arg0, p - arg0);
	p = argv[0] + (p - arg0);
    }
    memcpy(p, rubyname, namesize);

    execv(rubypath, argv);
    return -1;
}
