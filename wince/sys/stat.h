#ifndef SYS_STAT_H
#define SYS_STAT_H 1

#include <sys/types.h>

#define _S_IFMT         0170000         /* file type mask */
#define _S_IFDIR        0040000         /* directory */
#define _S_IFCHR        0020000         /* character special */
#define _S_IFIFO        0010000         /* pipe */
#define _S_IFREG        0100000         /* regular */
#define _S_IREAD        0000400         /* read permission, owner */
#define _S_IWRITE       0000200         /* write permission, owner */
#define _S_IEXEC        0000100         /* execute/search permission, owner */

#define S_IFMT   _S_IFMT
#define S_IFREG  _S_IFREG
#define S_IFCHR  _S_IFCHR
#define S_IFDIR  _S_IFDIR
#define S_IREAD  _S_IREAD
#define S_IWRITE _S_IWRITE
#define S_IEXEC  _S_IEXEC

#ifndef S_ISDIR
#define S_ISDIR(X) (((X) & S_IFMT) == S_IFDIR)
#endif
#ifndef S_ISREG
#define S_ISREG(X) (((X) & S_IFMT) == S_IFREG)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// in sys/types.h
//typedef unsigned int _dev_t;
//typedef long _off_t;
//typedef unsigned short _ino_t;

#ifndef _STAT_DEFINED
struct stat 
{
  dev_t st_dev;
  ino_t st_ino;
  unsigned short st_mode;
  short st_nlink;
  short st_uid;
  short st_gid;
  dev_t st_rdev;
  off_t st_size;
  time_t st_atime;
  time_t st_mtime;
  time_t st_ctime;
};
#define _STAT_DEFINED
#endif /* _STAT_DEFINED */

#define _stat stat

int _stat(const char *filename, struct _stat *stat);
int fstat(int file, struct stat *sbuf);


#ifdef __cplusplus
};
#endif


#endif
