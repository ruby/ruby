#ifndef EXT_NT_H
#define EXT_NT_H

/*
 *  Copyright (c) 1993, Intergraph Corporation
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the perl README file.
 *
 */

//
// Definitions for NT port of Perl
//

//
// GRRRR!!!!  Windows Nonsense.
// Define the following so we don't get tons of extra stuff
// when we include windows.h 
//

#define NOGDICAPMASKS     
#define NOVIRTUALKEYCODES 
#define NOWINMESSAGES     
#define NOWINSTYLES       
#define NOSYSMETRICS      
#define NOMENUS           
#define NOICONS           
#define NOKEYSTATES       
#define NOSYSCOMMANDS     
#define NORASTEROPS       
#define NOSHOWWINDOW      
#define OEMRESOURCE       
#define NOATOM            
#define NOCLIPBOARD       
#define NOCOLOR           
#define NOCTLMGR          
#define NODRAWTEXT        
#define NOGDI             
//#define NOKERNEL        
//#define NOUSER          
#define NONLS             
#define NOMB              
#define NOMEMMGR          
#define NOMETAFILE        
#define NOMINMAX          
#define NOMSG             
#define NOOPENFILE        
#define NOSCROLL          
#define NOSERVICE         
#define NOSOUND           
#define NOTEXTMETRIC      
#define NOWH              
#define NOWINOFFSETS      
#define NOCOMM            
#define NOKANJI           
#define NOHELP            
#define NOPROFILER        
#define NODEFERWINDOWPOS  


//
// Ok now we can include the normal include files.
//

#include <stdarg.h>
#include <windows.h>
//
// We\'re not using Microsoft\'s "extensions" to C for
// Structured Exception Handling (SEH) so we can nuke these
//
#undef try
#undef except
#undef finally
#undef leave
#include <winsock.h>
#include <sys/types.h>
#include <direct.h>
#include <process.h>
#include <io.h>
#include <time.h>
#include <sys/utime.h>

//
// Grrr...
//

#define access	   _access
#define chmod	   _chmod
#define chsize	   _chsize
#define close	   _close
#define creat	   _creat
#define dup	   _dup
#define dup2	   _dup2
#define eof	   _eof
#define filelength _filelength
#define isatty	   _isatty
#define locking    _locking
#define lseek	   _lseek
#define mktemp	   _mktemp
#define open	   _open
#define read	   _read
#define setmode    _setmode
#define sopen	   _sopen
#define tell	   _tell
#define umask	   _umask
#define unlink	   _unlink
#define write	   _write
#define execl	   _execl
#define execle	   _execle
#define execlp	   _execlp
#define execlpe    _execlpe
#define execv	   _execv
#define execve	   _execve
#define execvp	   _execvp
#define execvpe    _execvpe
#define getpid	   _getpid
#define spawnl	   _spawnl
#define spawnle    _spawnle
#define spawnlp    _spawnlp
#define spawnlpe   _spawnlpe
#define spawnv	   _spawnv
#define spawnve    _spawnve
#define spawnvp    _spawnvp
#define spawnvpe   _spawnvpe
#if _MSC_VER < 800
#define fileno	   _fileno
#endif
#define utime      _utime
#define pipe       _pipe

#define popen    mypopen
#define pclose   mypclose

/* these are defined in nt.c */

extern int NtMakeCmdVector(char *, char ***, int);
extern void NtInitialize(int *, char ***);

extern char *NtGetLib(void);
extern char *NtGetBin(void);

//
// define this so we can do inplace editing
//

#define SUFFIX

//
// stubs
//
extern int       ioctl (int, unsigned int, char *);
#if 0
extern void      sleep (unsigned int);
#else
#define sleep(x) Sleep(x*1000)
#endif

extern UIDTYPE   getuid (void);
extern UIDTYPE   geteuid (void);
extern GIDTYPE   getgid (void);
extern GIDTYPE   getegid (void);
extern int       setuid (int);
extern int       setgid (int);


//
// Got the idea and some of the code from the MSDOS implementation
//

/* 
 *    (C) Copyright 1987, 1990 Diomidis Spinellis.
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 * Included in the nt header file for use by nt port
 *
 * $Log:	dir.h,v $
 * Revision 4.0.1.1  91/06/07  11:22:10  lwall
 * patch4: new copyright notice
 * 
 * Revision 4.0  91/03/20  01:34:20  lwall
 * 4.0 baseline.
 * 
 * Revision 3.0.1.1  90/03/27  16:07:08  lwall
 * patch16: MSDOS support
 * 
 * Revision 1.1  90/03/18  20:32:29  dds
 * Initial revision
 *
 *
 */
/*
 * defines the type returned by the directory(3) functions
 */

/*Directory entry size */
#ifdef DIRSIZ
#undef DIRSIZ
#endif
#define DIRSIZ(rp)	(sizeof(struct direct))

/* need this so that directory stuff will compile! */
#define DIRENT direct

/*
 * Structure of a directory entry
 */
struct direct	{
	ino_t	d_ino;			/* inode number (not used by MS-DOS) */
	int	d_namlen;		/* Name length */
	char	d_name[257];		/* file name */
};

struct _dir_struc {			/* Structure used by dir operations */
	char *start;			/* Starting position */
	char *curr;			/* Current position */
	long size;			/* Size of string table */
	long nfiles;			/* number if filenames in table */
	struct direct dirstr;		/* Directory structure to return */
};

typedef struct _dir_struc DIR;		/* Type returned by dir operations */

DIR *cdecl opendir(char *filename);
struct direct *readdir(DIR *dirp);
long telldir(DIR *dirp);
void seekdir(DIR *dirp,long loc);
void rewinddir(DIR *dirp);
void closedir(DIR *dirp);

extern int sys_nerr;
extern char *sys_errlist[];
extern char *mystrerror(int);

#define strerror(e) mystrerror(e)

#define PIPE_BUF 1024

#define HAVE_STDLIB_H 1
#define HAVE_GETLOGIN 1
#define HAVE_WAITPID 1
#define HAVE_GETCWD 1

#endif
