
#ifndef _IO_WINCE_H_
#define _IO_WINCE_H_

#ifndef _TIME_T_DEFINED
typedef unsigned long time_t;
#define _TIME_T_DEFINED
#endif

#ifndef _FSIZE_T_DEFINED
typedef unsigned long _fsize_t; /* Could be 64 bits for Win32 */
#define _FSIZE_T_DEFINED
#endif

#ifndef _FINDDATA_T_DEFINED
struct _finddata_t {
        unsigned    attrib;
        time_t      time_create;    /* -1 for FAT file systems */
        time_t      time_access;    /* -1 for FAT file systems */
        time_t      time_write;
        _fsize_t    size;
        char        name[260];
};
#define _FINDDATA_T_DEFINED
#endif


#ifdef __cplusplus
extern "C" {
#endif

int _chsize(int handle, long size);
int _rename (const char *oldname, const char *newname);
int _unlink(const char *file);
int _umask(int cmask);
int _chmod(const char *path, int mode);
int dup( int handle );
//int dup2( int handle1, int handle2 );
int _isatty(int fd);
int _pipe(int *phandles, unsigned int psize, int textmode);
int _access(const char *filename, int flags);
int _open_osfhandle ( long osfhandle, int flags);
long _get_osfhandle( int filehandle );
int _open(const char *file, int mode,...);
int close(int fd);
int _read(int fd, void *buffer, int length);
int _write(int fd, const void *buffer, unsigned count);
long _lseek(int handle, long offset, int origin);
long _findfirst( char *filespec, struct _finddata_t *fileinfo );
int _findnext( long handle, struct _finddata_t *fileinfo );
int _findclose( long handle );

#ifdef __cplusplus
};
#endif

#define chmod      _chmod
#define chsize     _chsize
#define rename     _rename
#define unlink	   _unlink
#define open	   _open
//#define close	   _close
#define read	   _read
#define write	   _write
#define umask	   _umask
//#define dup        _dup
#define isatty	   _isatty
#define access	   _access
#define pipe       _pipe
#define setmode    _setmode
#define lseek      _lseek

#define _close	   close

#endif

