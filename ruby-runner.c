#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ruby-runner.h"

#define STRINGIZE(expr) STRINGIZE0(expr)
#define STRINGIZE0(expr) #expr

static void
insert_env_path(const char *envname, const char *paths, size_t size, int prepend)
{
    const char *env = getenv(envname);
    char c = 0;
    size_t n = 0;

    if (env) {
	while ((c = *env) == PATH_SEP) ++env;
	n = strlen(env);
	while (n > 0 && env[n-1] == PATH_SEP) --n;
    }
    if (c) {
	char *e = malloc(size+n+1);
	size_t pos = 0;
	if (prepend) {
	    memcpy(e, paths, pos = size-1);
	    e[pos++] = PATH_SEP;
	}
	memcpy(e+pos, env, n);
	pos += n;
	if (!prepend) {
	    e[pos++] = PATH_SEP;
	    memcpy(e+pos, paths, size-1);
	    pos += size-1;
	}
	e[pos] = '\0';
	env = e;
    }
    else {
	env = paths;
    }
    setenv(envname, env, 1);
}

#define EXTOUT_DIR BUILDDIR"/"EXTOUT
int
main(int argc, char **argv)
{
    static const char builddir[] = BUILDDIR;
    static const char rubypath[] = BUILDDIR"/"STRINGIZE(RUBY_INSTALL_NAME);
    static const char rubylib[] =
	ABS_SRCDIR"/lib"
	PATH_SEPARATOR
	EXTOUT_DIR"/common"
	PATH_SEPARATOR
	EXTOUT_DIR"/"ARCH
	;
    const size_t dirsize = sizeof(builddir);
    const size_t namesize = sizeof(rubypath) - dirsize;
    const char *rubyname = rubypath + dirsize;
    char *arg0 = argv[0], *p;

    insert_env_path(LIBPATHENV, builddir, dirsize, 1);
    insert_env_path("RUBYLIB", rubylib, sizeof(rubylib), 0);

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
