/**********************************************************************

  rubyio.h -

  $Author$
  $Date$
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBYIO_H
#define RUBYIO_H

#include <stdio.h>
#include <errno.h>

#if defined(HAVE_STDIO_EXT_H)
#include <stdio_ext.h>
#endif

typedef struct rb_io_t {
    FILE *f;			/* stdio ptr for read/write */
    FILE *f2;			/* additional ptr for rw pipes */
    int mode;			/* mode flags */
    int pid;			/* child's pid (for pipes) */
    int lineno;			/* number of lines read */
    char *path;			/* pathname for file */
    void (*finalize) _((struct rb_io_t*,int)); /* finalize proc */
} rb_io_t;

#define HAVE_RB_IO_T 1
#define OpenFile rb_io_t	/* for backward compatibility */

#define FMODE_READABLE  1
#define FMODE_WRITABLE  2
#define FMODE_READWRITE 3
#define FMODE_APPEND   64
#define FMODE_CREATE  128
#define FMODE_BINMODE   4
#define FMODE_SYNC      8
#define FMODE_WBUF     16
#define FMODE_RBUF     32
#define FMODE_WSPLIT  0x200
#define FMODE_WSPLIT_INITIALIZED  0x400

#define GetOpenFile(obj,fp) rb_io_check_closed((fp) = RFILE(rb_io_taint_check(obj))->fptr)

#define MakeOpenFile(obj, fp) do {\
    if (RFILE(obj)->fptr) {\
	rb_io_close(obj);\
	free(RFILE(obj)->fptr);\
	RFILE(obj)->fptr = 0;\
    }\
    fp = 0;\
    fp = RFILE(obj)->fptr = ALLOC(rb_io_t);\
    fp->f = fp->f2 = NULL;\
    fp->mode = 0;\
    fp->pid = 0;\
    fp->lineno = 0;\
    fp->path = NULL;\
    fp->finalize = 0;\
} while (0)

#define GetReadFile(fptr) ((fptr)->f)
#define GetWriteFile(fptr) (((fptr)->f2) ? (fptr)->f2 : (fptr)->f)

FILE *rb_fopen _((const char*, const char*));
FILE *rb_fdopen _((int, const char*));
int rb_getc _((FILE*));
long rb_io_fread _((char *, long, FILE *));
long rb_io_fwrite _((const char *, long, FILE *));
int  rb_io_mode_flags _((const char*));
int  rb_io_modenum_flags _((int));
void rb_io_check_writable _((rb_io_t*));
void rb_io_check_readable _((rb_io_t*));
void rb_io_fptr_finalize _((rb_io_t*));
void rb_io_synchronized _((rb_io_t*));
void rb_io_check_initialized _((rb_io_t*));
void rb_io_check_closed _((rb_io_t*));
int rb_io_wait_readable _((int));
int rb_io_wait_writable _((int));
void rb_io_set_nonblock(rb_io_t *fptr);

VALUE rb_io_taint_check _((VALUE));
NORETURN(void rb_eof_error _((void)));

void rb_read_check _((FILE*));
int rb_read_pending _((FILE*));
#endif
