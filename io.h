/************************************************

  io.h -

  $Author: matz $
  $Revision: 1.3 $
  $Date: 1994/08/12 11:06:42 $
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#ifndef IO_H
#define IO_H

#include "sig.h"
#include <stdio.h>
#include <errno.h>

typedef struct {
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
#define FMODE_SYNC      4

extern ID id_fd;

#define GetOpenFile(obj,fp) Get_Data_Struct(obj, id_fd, OpenFile, fp)

void io_fptr_finalize();

#define MakeOpenFile(obj, fp) do {\
    Make_Data_Struct(obj, id_fd, OpenFile, 0, io_fptr_finalize, fp);\
    fp->f = fp->f2 = NULL;\
    fp->mode = 0;\
    fp->pid = 0;\
    fp->lineno = 0;\
    fp->path = NULL;\
    fp->finalize = 0;\
} while (0)

#endif
