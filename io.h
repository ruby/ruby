/************************************************

  io.h -

  $Author$
  $Revision$
  $Date$
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#ifndef IO_H
#define IO_H

#include "sig.h"
#include <stdio.h>
#include <errno.h>

typedef struct OpenFile {
    FILE *f;			/* stdio ptr for read/write */
    FILE *f2;			/* additional ptr for rw pipes */
    int mode;			/* mode flags */
    int pid;			/* child's pid (for pipes) */
    int lineno;			/* number of lines read */
    char *path;			/* pathname for file */
    void (*finalize)();		/* finalize proc */
} OpenFile;

#define FMODE_READABLE  1
#define FMODE_WRITABLE  2
#define FMODE_READWRITE 3
#define FMODE_BINMODE   4
#define FMODE_SYNC      8

#define GetOpenFile(obj,fp) ((fp) = RFILE(obj)->fptr)

#define MakeOpenFile(obj, fp) do {\
    fp = RFILE(obj)->fptr = ALLOC(OpenFile);\
    fp->f = fp->f2 = NULL;\
    fp->mode = 0;\
    fp->pid = 0;\
    fp->lineno = 0;\
    fp->path = NULL;\
    fp->finalize = 0;\
} while (0)

#define GetWriteFile(fptr) (((fptr)->f2) ? (fptr)->f2 : (fptr)->f)

FILE *rb_fopen _((char *, char *));
FILE *rb_fdopen _((int, char *));
void io_writable _((OpenFile *));
void io_readable _((OpenFile *));
void io_fptr_finalize _((OpenFile *));
void io_unbuffered _((OpenFile *));
void io_check_closed _((OpenFile *));

#endif
