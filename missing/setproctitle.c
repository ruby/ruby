/* Based on setproctitle.c from openssh-5.6p1 */
/* Based on conf.c from UCB sendmail 8.8.8 */

/*
 * Copyright 2003 Damien Miller
 * Copyright (c) 1983, 1995-1997 Eric P. Allman
 * Copyright (c) 1988, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include "ruby.h"
#include "ruby/util.h"
#define compat_init_setproctitle ruby_init_setproctitle
RUBY_FUNC_EXPORTED void ruby_init_setproctitle(int argc, char *argv[]);

#ifndef HAVE_SETPROCTITLE

#include <stdarg.h>
#include <stdlib.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef HAVE_SYS_PSTAT_H
#include <sys/pstat.h>
#endif
#include <string.h>

#if defined(__APPLE__)
# ifdef HAVE_CRT_EXTERNS_H
#  include <crt_externs.h>
#  undef environ
#  define environ (*_NSGetEnviron())
# else
#  include "crt_externs.h"
# endif
#endif

#define SPT_NONE	0	/* don't use it at all */
#define SPT_PSTAT	1	/* use pstat(PSTAT_SETCMD, ...) */
#define SPT_REUSEARGV	2	/* cover argv with title information */

#ifndef SPT_TYPE
# define SPT_TYPE	SPT_NONE
#endif

#ifndef SPT_PADCHAR
# define SPT_PADCHAR	'\0'
#endif

#if SPT_TYPE == SPT_REUSEARGV
static char *argv_start = NULL;
static size_t argv_env_len = 0;
static size_t argv_len = 0;
static char **argv1_addr = NULL;
#endif

#endif /* HAVE_SETPROCTITLE */

#if defined(SPT_TYPE) && SPT_TYPE == SPT_REUSEARGV
# define ALLOCATE_ENVIRON 1
#else
# define ALLOCATE_ENVIRON 0
#endif

#if ALLOCATE_ENVIRON
static char **system_environ = NULL;
static char **orig_environ = NULL;
static char **alloc_environ = NULL;
#endif

void
compat_init_setproctitle(int argc, char *argv[])
{
#if ALLOCATE_ENVIRON
	extern char **environ;
	char *lastargv = NULL;
	char *lastenvp = NULL;
	char **envp = environ;
	int i;

	/*
	 * NB: This assumes that argv has already been copied out of the
	 * way. This is true for sshd, but may not be true for other
	 * programs. Beware.
	 */

	if (argc == 0 || argv[0] == NULL)
		return;

	/* Fail if we can't allocate room for the new environment */
	for (i = 0; envp[i] != NULL; i++);

	system_environ = environ;

	alloc_environ = xcalloc(i + 1, sizeof(*environ));
	orig_environ = environ = xcalloc(i + 1, sizeof(*environ));
	if (environ == NULL) {
		environ = envp;	/* put it back */
		return;
	}

	/*
	 * Find the last argv string or environment variable within
	 * our process memory area.
	 */
	for (i = 0; i < argc; i++) {
		if (lastargv == NULL || lastargv + 1 == argv[i])
			lastargv = argv[i] + strlen(argv[i]);
	}
	lastenvp = lastargv;
	for (i = 0; envp[i] != NULL; i++) {
		if (lastenvp + 1 == envp[i])
			lastenvp = envp[i] + strlen(envp[i]);
	}

	/* We keep argv[1], argv[2], etc. at this moment,
	   because the ps command of AIX refers to them. */
	argv1_addr = &argv[1];
	argv_start = argv[0];
	argv_len = lastargv - argv[0];
	argv_env_len = lastenvp - argv[0];

	for (i = 0; envp[i] != NULL; i++)
		alloc_environ[i] = environ[i] = ruby_strdup(envp[i]);
	alloc_environ[i] = environ[i] = NULL;
#endif /* SPT_REUSEARGV */
}

void
ruby_free_proctitle(void)
{
#if ALLOCATE_ENVIRON
	extern char **environ;

	if (!orig_environ) return; /* environ is allocated by OS */

	for (int i = 0; alloc_environ[i] != NULL; i++) {
		xfree(alloc_environ[i]);
	}
	xfree(alloc_environ);
	xfree(orig_environ);

	environ = system_environ;
#endif
}

#ifndef HAVE_SETPROCTITLE

void
setproctitle(const char *fmt, ...)
{
#if SPT_TYPE != SPT_NONE
	va_list ap;
	char ptitle[1024];
	size_t len;
	size_t argvlen;
#if SPT_TYPE == SPT_PSTAT
	union pstun pst;
#endif

#if SPT_TYPE == SPT_REUSEARGV
	if (argv_env_len <= 0)
		return;
#endif

	/* fmt must be non-NULL */
	va_start(ap, fmt);
	vsnprintf(ptitle, sizeof(ptitle), fmt, ap);
	va_end(ap);

#if SPT_TYPE == SPT_PSTAT
	pst.pst_command = ptitle;
	pstat(PSTAT_SETCMD, pst, strlen(ptitle), 0, 0);
#elif SPT_TYPE == SPT_REUSEARGV
	len = strlcpy(argv_start, ptitle, argv_env_len);
	argvlen = len > argv_len ? argv_env_len : argv_len;
	for(; len < argvlen; len++)
		argv_start[len] = SPT_PADCHAR;
	/* argv[1], argv[2], etc. are no longer valid. */
	*argv1_addr = NULL;
#endif

#endif /* SPT_NONE */
}

#endif /* HAVE_SETPROCTITLE */
