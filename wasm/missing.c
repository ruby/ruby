#include <errno.h>
#include <sys/types.h>
#include "ruby/missing.h"

// Produce weak symbols for missing functions to replace them with actual ones if exists.
#define WASM_MISSING_LIBC_FUNC __attribute__((weak))

WASM_MISSING_LIBC_FUNC
int
chmod(const char *pathname, rb_mode_t mode)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
chown(const char *pathname, rb_uid_t owner, rb_gid_t group)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
dup(int oldfd)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
dup2(int oldfd, int newfd)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
execl(const char *path, const char *arg, ...)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
execle(const char *path, const char *arg, ...)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
execv(const char *path, char *const argv[])
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
execve(const char *filename, char *const argv[], char *const envp[])
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
rb_uid_t
geteuid(void)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
rb_uid_t
getuid(void)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
rb_pid_t
getppid(void)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
rb_gid_t
getegid(void)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
rb_gid_t
getgid(void)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
char *
getlogin(void)
{
    errno = ENOTSUP;
    return NULL;
}

WASM_MISSING_LIBC_FUNC
rb_mode_t
umask(rb_mode_t mask)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
int
mprotect(const void *addr, size_t len, int prot)
{
    return 0;
}

WASM_MISSING_LIBC_FUNC
int
pclose(FILE *stream)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
FILE *
popen(const char *command, const char *type)
{
    errno = ENOTSUP;
    return NULL;
}

WASM_MISSING_LIBC_FUNC
int
pipe(int pipefd[2])
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
posix_madvise(void *addr, size_t len, int advice)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
kill(rb_pid_t pid, int sig)
{
    errno = ENOTSUP;
    return -1;
}


WASM_MISSING_LIBC_FUNC
void
tzset(void)
{
    return;
}

WASM_MISSING_LIBC_FUNC
int
shutdown(int s, int how)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
int
system(const char *command)
{
    errno = ENOTSUP;
    return -1;
}

WASM_MISSING_LIBC_FUNC
pid_t
waitpid(pid_t pid, int *wstatus, int options)
{
    errno = ENOTSUP;
    return -1;
}
