/**********************************************************************

  rubyio.h -

  $Author$
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_IO_H
#define RUBY_IO_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include <stdio.h>
#include <errno.h>
#include "ruby/encoding.h"

#if defined(HAVE_STDIO_EXT_H)
#include <stdio_ext.h>
#endif

typedef struct rb_io_t {
    int fd;                     /* file descriptor */
    FILE *stdio_file;		/* stdio ptr for read/write if available */
    int mode;			/* mode flags */
    rb_pid_t pid;		/* child's pid (for pipes) */
    int lineno;			/* number of lines read */
    char *path;			/* pathname for file */
    void (*finalize)(struct rb_io_t*,int); /* finalize proc */
    long refcnt;

    char *wbuf;                 /* wbuf_off + wbuf_len <= wbuf_capa */
    int wbuf_off;
    int wbuf_len;
    int wbuf_capa;

    char *rbuf;                 /* rbuf_off + rbuf_len <= rbuf_capa */
    int rbuf_off;
    int rbuf_len;
    int rbuf_capa;

    VALUE tied_io_for_writing;

    /*
     * enc  enc2 read action                      write action
     * NULL NULL force_encoding(default_external) write the byte sequence of str
     * e1   NULL force_encoding(e1)               convert str.encoding to e1
     * e1   e2   convert from e2 to e1            convert from e1 to e2
     */
    rb_encoding *enc;
    rb_encoding *enc2;

    rb_econv_t *readconv;
    char *crbuf;                /* crbuf_off + crbuf_len <= crbuf_capa */
    int crbuf_off;
    int crbuf_len;
    int crbuf_capa;

    rb_econv_t *writeconv;
    VALUE writeconv_stateless;
    int writeconv_initialized;

} rb_io_t;

#define HAVE_RB_IO_T 1

#define FMODE_READABLE  1
#define FMODE_WRITABLE  2
#define FMODE_READWRITE 3
#define FMODE_APPEND   64
#define FMODE_CREATE  128
#define FMODE_BINMODE   4
#define FMODE_SYNC      8
#define FMODE_TTY      16
#define FMODE_DUPLEX   32
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
    fp->fd = -1;\
    fp->stdio_file = NULL;\
    fp->mode = 0;\
    fp->pid = 0;\
    fp->lineno = 0;\
    fp->path = NULL;\
    fp->finalize = 0;\
    fp->refcnt = 1;\
    fp->wbuf = NULL;\
    fp->wbuf_off = 0;\
    fp->wbuf_len = 0;\
    fp->wbuf_capa = 0;\
    fp->rbuf = NULL;\
    fp->rbuf_off = 0;\
    fp->rbuf_len = 0;\
    fp->rbuf_capa = 0;\
    fp->readconv = NULL;\
    fp->crbuf = NULL;\
    fp->crbuf_off = 0;\
    fp->crbuf_len = 0;\
    fp->crbuf_capa = 0;\
    fp->writeconv = NULL;\
    fp->writeconv_stateless = Qnil;\
    fp->writeconv_initialized = 0;\
    fp->tied_io_for_writing = 0;\
    fp->enc = 0;\
    fp->enc2 = 0;\
} while (0)

FILE *rb_io_stdio_file(rb_io_t *fptr);

FILE *rb_fopen(const char*, const char*);
FILE *rb_fdopen(int, const char*);
int  rb_io_mode_flags(const char*);
int  rb_io_modenum_flags(int);
void rb_io_check_writable(rb_io_t*);
void rb_io_check_readable(rb_io_t*);
int rb_io_fptr_finalize(rb_io_t*);
void rb_io_synchronized(rb_io_t*);
void rb_io_check_initialized(rb_io_t*);
void rb_io_check_closed(rb_io_t*);
int rb_io_wait_readable(int);
int rb_io_wait_writable(int);
void rb_io_set_nonblock(rb_io_t *fptr);

VALUE rb_io_taint_check(VALUE);
NORETURN(void rb_eof_error(void));

void rb_io_read_check(rb_io_t*);
int rb_io_read_pending(rb_io_t*);
void rb_read_check(FILE*);

DEPRECATED(int rb_getc(FILE*));
DEPRECATED(long rb_io_fread(char *, long, FILE *));
DEPRECATED(long rb_io_fwrite(const char *, long, FILE *));
DEPRECATED(int rb_read_pending(FILE*));

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_IO_H */
