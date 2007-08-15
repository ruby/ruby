/*	$NetBSD: sha1hl.c,v 1.2 2001/03/10 15:55:14 tron Exp $	*/
/*	$RoughId: sha1hl.c,v 1.2 2001/07/13 19:49:10 knu Exp $	*/
/*	$Id: sha1hl.c,v 1.1 2001/07/13 20:06:14 knu Exp $	*/

/* sha1hl.c
 * ----------------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <phk@login.dkuug.dk> wrote this file.  As long as you retain this notice you
 * can do whatever you want with this stuff. If we meet some day, and you think
 * this stuff is worth it, you can buy me a beer in return.   Poul-Henning Kamp
 * ----------------------------------------------------------------------------
 */

/* #include "namespace.h" */

#include "sha1.h"
#include <fcntl.h>

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#if defined(HAVE_UNISTD_H)
# include <unistd.h>
#endif

#if defined(LIBC_SCCS) && !defined(lint)
/* __RCSID("$NetBSD: sha1hl.c,v 1.2 2001/03/10 15:55:14 tron Exp $"); */
#endif /* LIBC_SCCS and not lint */

#ifndef _DIAGASSERT
#define _DIAGASSERT(cond)	assert(cond)
#endif


/* ARGSUSED */
char *
SHA1_End(ctx, buf)
    SHA1_CTX *ctx;
    char *buf;
{
    int i;
    char *p = buf;
    uint8_t digest[20];
    static const char hex[]="0123456789abcdef";

    _DIAGASSERT(ctx != NULL);
    /* buf may be NULL */

    if (p == NULL && (p = malloc(41)) == NULL)
	return 0;

    SHA1_Final(digest,ctx);
    for (i = 0; i < 20; i++) {
	p[i + i] = hex[((uint32_t)digest[i]) >> 4];
	p[i + i + 1] = hex[digest[i] & 0x0f];
    }
    p[i + i] = '\0';
    return(p);
}

char *
SHA1_File (filename, buf)
    char *filename;
    char *buf;
{
    uint8_t buffer[BUFSIZ];
    SHA1_CTX ctx;
    int fd, num, oerrno;

    _DIAGASSERT(filename != NULL);
    /* XXX: buf may be NULL ? */

    SHA1_Init(&ctx);

    if ((fd = open(filename,O_RDONLY)) < 0)
	return(0);

    while ((num = read(fd, buffer, sizeof(buffer))) > 0)
	SHA1_Update(&ctx, buffer, (size_t)num);

    oerrno = errno;
    close(fd);
    errno = oerrno;
    return(num < 0 ? 0 : SHA1_End(&ctx, buf));
}

char *
SHA1_Data (data, len, buf)
    const uint8_t *data;
    size_t len;
    char *buf;
{
    SHA1_CTX ctx;

    _DIAGASSERT(data != NULL);
    /* XXX: buf may be NULL ? */

    SHA1_Init(&ctx);
    SHA1_Update(&ctx, data, len);
    return(SHA1_End(&ctx, buf));
}
