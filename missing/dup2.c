/* 
 *    Copyright (c) 1991, Larry Wall
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 */

#include "defines.h"

#if defined(HAVE_FCNTL) && defined(F_DUPFD)
# include <fcntl.h>
#endif

int
dup2(oldfd,newfd)
int oldfd;
int newfd;
{
#if defined(HAVE_FCNTL) && defined(F_DUPFD)
    close(newfd);
    return fcntl(oldfd, F_DUPFD, newfd);
#else
    int fdtmp[256];
    int fdx = 0;
    int fd;

    if (oldfd == newfd)
	return 0;
    close(newfd);
    while ((fd = dup(oldfd)) != newfd)	/* good enough for low fd's */
	fdtmp[fdx++] = fd;
    while (fdx > 0)
	close(fdtmp[--fdx]);
    return 0;
#endif
}
