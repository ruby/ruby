/************************************************

  io.h -

  $Author: matz $
  $Revision: 1.1.1.1 $
  $Date: 1994/06/17 14:23:50 $
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#ifndef IO_H
#define IO_H

#include <stdio.h>
#include <errno.h>

typedef struct {
    FILE *f;			/* stdio ptr for read/write */
    FILE *f2;			/* additional ptr for rw pipes */
    int mode;			/* mode flags */
    int pid;			/* child's pid (for pipes) */
    int lineno;			/* number of lines read */
    char *path;			/* pathname for file */
} OpenFile;

#define FMODE_READABLE  1
#define FMODE_WRITABLE  2
#define FMODE_READWRITE 3
#define FMODE_SYNC      4

#define GetOpenFile(obj,fp) Get_Data_Struct(obj, "fd", OpenFile, fp)

void io_free_OpenFile();

#define MakeOpenFile(obj, fp) {\
    Make_Data_Struct(obj, "fd", OpenFile, Qnil, io_free_OpenFile, fp);\
    fp->f = fp->f2 = NULL;\
    fp->mode = 0;\
    fp->pid = 0;\
    fp->lineno = 0;\
    fp->path = NULL;\
}

#endif
