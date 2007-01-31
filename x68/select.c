/*
 * PROJECT C Library, X68000 PROGRAMMING INTERFACE DEFINITION
 * --------------------------------------------------------------------
 * This file is written by the Project C Library Group,  and completely
 * in public domain. You can freely use, copy, modify, and redistribute
 * the whole contents, without this notice.
 * --------------------------------------------------------------------
 * $Id: select.c,v 1.1.1.2 1999/01/20 04:59:39 matz Exp $
 */

#ifndef __IOCS_INLINE__
#define __IOCS_INLINE__
#define __DOS_INLINE__
#define __DOS_DOSCALL__
#endif

/* System headers */
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/dos.h>
#include <sys/iocs.h>
#include <sys/time.h>
#include <sys/types.h>
#if 0
#include <sys/select.h>
#include <sys/xsocket.h>
#endif
#include <sys/xunistd.h>

/* Macros */
#define XFD_ISSET(fd,fds) ((fds) && FD_ISSET ((fd), (fds)))
#define isreadable(mode)  ((mode) == O_RDONLY || (mode) == O_RDWR)
#define iswritable(mode)  ((mode) == O_WRONLY || (mode) == O_RDWR)
#ifndef _POSIX_FD_SETSIZE
#define _POSIX_FD_SETSIZE OPEN_MAX
#endif

/* Functions */
int
select (int fds, fd_set *rfds, fd_set *wfds, fd_set *efds, struct timeval *timeout)
{
  fd_set oread, owrite, oexcept;
  int ticks, start;
  int nfds;

  if (fds > _POSIX_FD_SETSIZE)
    {
      errno = EINVAL;
      return -1;
    }

  FD_ZERO (&oread);
  FD_ZERO (&owrite);
  FD_ZERO (&oexcept);

  nfds = 0;
  ticks = -1;

  if (timeout)
    {
      ticks = timeout->tv_sec * 100 + timeout->tv_usec / 10000;
      if (ticks < 0)
	{
	  errno = EINVAL;
	  return -1;
	}
    }

  start = _iocs_ontime ();
  for (;;)
    {
      {
	int fd;
	
	for (fd = 0; fd < fds; fd++)
	  {
	    int accmode;
	    
	    if (_fddb[fd].inuse == _FD_NOTUSED)
	      continue;
	    
	    accmode = _fddb[fd].oflag & O_ACCMODE;
	    
	    if (isatty (fd))
	      {
		if (XFD_ISSET (fd, rfds) && isreadable (accmode) && _dos_k_keysns ())
		  {
		    FD_SET (fd, &oread);
		    nfds++;
		  }
		
		if (XFD_ISSET (fd, wfds) && iswritable (accmode))
		  {
		    FD_SET (fd, &owrite);
		    nfds++;
		  }
	      }
#if 0
	    else if (_fddb[fd].sockno >= 0)
	      {
		if (XFD_ISSET (fd, rfds) && _socklen (_fddb[fd].sockno, 0))
		  {
		    FD_SET (fd, &oread);
		    nfds++;
		  }

		if (XFD_ISSET (fd, wfds) /* && _socklen (_fddb[fd].sockno, 1) == 0 */)
		  {
		    FD_SET (fd, &owrite);
		    nfds++;
		  }
	      }
#endif
	    else
	      {
		if (XFD_ISSET (fd, rfds) && isreadable (accmode) && _dos_ioctrlis (fd))
		  {
		    FD_SET (fd, &oread);
		    nfds++;
		  }
		
		if (XFD_ISSET (fd, wfds) && iswritable (accmode) && _dos_ioctrlos (fd))
		  {
		    FD_SET (fd, &owrite);
		    nfds++;
		  }
	      }
	  }
      }

      {
	int rest;
	
	if ((rest = (_iocs_ontime () - start) % 8640000) < 0)
	  rest += 8640000;
	
	if (nfds != 0)
	  {
	    if (ticks >= 0)
	      {
		int left;
		
		if ((left = ticks - rest) < 0)
		  left = 0;
		
		timeout->tv_sec = left / 100;
		timeout->tv_usec = (left % 100) * 10000;
	      }
	    
	    if (rfds)
	      *rfds = oread;
	    if (wfds)
	      *wfds = owrite;
	    if (efds)
	      *efds = oexcept;
	    
	    return nfds;
	  }
	
	if (ticks >= 0 && rest > ticks)
	  return 0;
      }

      _dos_change_pr ();
    }
}
