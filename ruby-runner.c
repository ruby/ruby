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
    const char *libpath = getenv(LIBPATHENV);
    char c = 0;

    if (libpath) {
	while ((c = *libpath) == PATH_SEP) ++libpath;
    }
    if (c) {
	size_t n = strlen(libpath);
	char *e = malloc(sizeof(builddir)+n+1);
	memcpy(e, builddir, sizeof(builddir)-1);
	e[sizeof(builddir)-1] = PATH_SEP;
	memcpy(e+sizeof(builddir), libpath, n+1);
	libpath = e;
    }
    else {
	libpath = builddir;
    }
    setenv(LIBPATHENV, libpath, 1);
    execv(BUILDDIR"/"STRINGIZE(RUBY_INSTALL_NAME), argv);
    return -1;
}
