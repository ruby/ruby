/*
 * Written by Robert Rother, Mariah Corporation, August 1985.
 *
 * If you want it, it's yours.  All I ask in return is that if you
 * figure out how to do this in a Bourne Shell script you send me
 * a copy.
 *					sdcsvax!rmr or rmr@uscd
 *
 * Severely hacked over by John Gilmore to make a 4.2BSD compatible
 * subroutine.	11Mar86; hoptoad!gnu
 *
 * Modified by rmtodd@uokmax 6-28-87 -- when making an already existing dir,
 * subroutine didn't return EEXIST.  It does now.
 */

#include <sys/stat.h>
#include <errno.h>
/*
 * Make a directory.
 */
int
mkdir (dpath, dmode)
     char *dpath;
     int dmode;
{
  int cpid, status;
  struct stat statbuf;

  if (stat (dpath, &statbuf) == 0)
    {
      errno = EEXIST;		/* Stat worked, so it already exists */
      return -1;
    }

  /* If stat fails for a reason other than non-existence, return error */
  if (errno != ENOENT)
    return -1;

  switch (cpid = fork ())
    {

    case -1:			/* Error in fork() */
      return (-1);		/* Errno is set already */

    case 0:			/* Child process */
      /*
		 * Cheap hack to set mode of new directory.  Since this
		 * child process is going away anyway, we zap its umask.
		 * FIXME, this won't suffice to set SUID, SGID, etc. on this
		 * directory.  Does anybody care?
		 */
      status = umask (0);	/* Get current umask */
      status = umask (status | (0777 & ~dmode));	/* Set for mkdir */
      execl ("/bin/mkdir", "mkdir", dpath, (char *) 0);
      _exit (-1);		/* Can't exec /bin/mkdir */

    default:			/* Parent process */
      while (cpid != wait (&status));	/* Wait for kid to finish */
    }

  if (WIFSIGNALED (status) || WEXITSTATUS (status) != 0)
    {
      errno = EIO;		/* We don't know why, but */
      return -1;		/* /bin/mkdir failed */
    }

  return 0;
}

int
rmdir (dpath)
     char *dpath;
{
  int cpid, status;
  struct stat statbuf;

  if (stat (dpath, &statbuf) != 0)
    {
      /* Stat just set errno.  We don't have to */
      return -1;
    }

  switch (cpid = fork ())
    {

    case -1:			/* Error in fork() */
      return (-1);		/* Errno is set already */

    case 0:			/* Child process */
      execl ("/bin/rmdir", "rmdir", dpath, (char *) 0);
      _exit (-1);		/* Can't exec /bin/mkdir */

    default:			/* Parent process */
      while (cpid != wait (&status));	/* Wait for kid to finish */
    }

  if (WIFSIGNALED (status) || WEXITSTATUS (status) != 0)
    {
      errno = EIO;		/* We don't know why, but */
      return -1;		/* /bin/rmdir failed */
    }

  return 0;
}
