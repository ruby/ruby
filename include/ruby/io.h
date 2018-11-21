/**********************************************************************

  rubyio.h -

  $Author$
  created at: Fri Nov 12 16:47:09 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_IO_H
#define RUBY_IO_H 1

#ifdef RUBY_INTERNAL_H
#error "Include this file before internal.h"
#endif

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include <stdio.h>
#include "ruby/encoding.h"

#if defined(HAVE_STDIO_EXT_H)
#include <stdio_ext.h>
#endif

#include "ruby/config.h"
#include <errno.h>
#if defined(HAVE_POLL)
#  ifdef _AIX
#    define reqevents events
#    define rtnevents revents
#  endif
#  include <poll.h>
#  ifdef _AIX
#    undef reqevents
#    undef rtnevents
#    undef events
#    undef revents
#  endif
#  define RB_WAITFD_IN  POLLIN
#  define RB_WAITFD_PRI POLLPRI
#  define RB_WAITFD_OUT POLLOUT
#else
#  define RB_WAITFD_IN  0x001
#  define RB_WAITFD_PRI 0x002
#  define RB_WAITFD_OUT 0x004
#endif

RUBY_SYMBOL_EXPORT_BEGIN

PACKED_STRUCT_UNALIGNED(struct rb_io_buffer_t {
    char *ptr;                  /* off + len <= capa */
    int off;
    int len;
    int capa;
});
typedef struct rb_io_buffer_t rb_io_buffer_t;

typedef struct rb_io_t {
    FILE *stdio_file;		/* stdio ptr for read/write if available */
    int fd;                     /* file descriptor */
    int mode;			/* mode flags: FMODE_XXXs */
    rb_pid_t pid;		/* child's pid (for pipes) */
    int lineno;			/* number of lines read */
    VALUE pathv;		/* pathname for file */
    void (*finalize)(struct rb_io_t*,int); /* finalize proc */

    rb_io_buffer_t wbuf, rbuf;

    VALUE tied_io_for_writing;

    /*
     * enc  enc2 read action                      write action
     * NULL NULL force_encoding(default_external) write the byte sequence of str
     * e1   NULL force_encoding(e1)               convert str.encoding to e1
     * e1   e2   convert from e2 to e1            convert str.encoding to e2
     */
    struct rb_io_enc_t {
        rb_encoding *enc;
        rb_encoding *enc2;
        int ecflags;
        VALUE ecopts;
    } encs;

    rb_econv_t *readconv;
    rb_io_buffer_t cbuf;

    rb_econv_t *writeconv;
    VALUE writeconv_asciicompat;
    int writeconv_initialized;
    int writeconv_pre_ecflags;
    VALUE writeconv_pre_ecopts;

    VALUE write_lock;
} rb_io_t;

#define HAVE_RB_IO_T 1

#define FMODE_READABLE              0x00000001
#define FMODE_WRITABLE              0x00000002
#define FMODE_READWRITE             (FMODE_READABLE|FMODE_WRITABLE)
#define FMODE_BINMODE               0x00000004
#define FMODE_SYNC                  0x00000008
#define FMODE_TTY                   0x00000010
#define FMODE_DUPLEX                0x00000020
#define FMODE_APPEND                0x00000040
#define FMODE_CREATE                0x00000080
/* #define FMODE_NOREVLOOKUP        0x00000100 */
#define FMODE_EXCL                  0x00000400
#define FMODE_TRUNC                 0x00000800
#define FMODE_TEXTMODE              0x00001000
/* #define FMODE_PREP               0x00010000 */
#define FMODE_SETENC_BY_BOM         0x00100000
/* #define FMODE_UNIX                  0x00200000 */
/* #define FMODE_INET                  0x00400000 */
/* #define FMODE_INET6                 0x00800000 */

#define GetOpenFile(obj,fp) rb_io_check_closed((fp) = RFILE(rb_io_taint_check(obj))->fptr)

#define MakeOpenFile(obj, fp) do {\
    (fp) = rb_io_make_open_file(obj);\
} while (0)

rb_io_t *rb_io_make_open_file(VALUE obj);

FILE *rb_io_stdio_file(rb_io_t *fptr);

FILE *rb_fdopen(int, const char*);
int rb_io_modestr_fmode(const char *modestr);
int rb_io_modestr_oflags(const char *modestr);
CONSTFUNC(int rb_io_oflags_fmode(int oflags));
void rb_io_check_writable(rb_io_t*);
void rb_io_check_readable(rb_io_t*);
void rb_io_check_char_readable(rb_io_t *fptr);
void rb_io_check_byte_readable(rb_io_t *fptr);
int rb_io_fptr_finalize(rb_io_t*);
void rb_io_synchronized(rb_io_t*);
void rb_io_check_initialized(rb_io_t*);
void rb_io_check_closed(rb_io_t*);
VALUE rb_io_get_io(VALUE io);
VALUE rb_io_check_io(VALUE io);
VALUE rb_io_get_write_io(VALUE io);
VALUE rb_io_set_write_io(VALUE io, VALUE w);
int rb_io_wait_readable(int);
int rb_io_wait_writable(int);
int rb_wait_for_single_fd(int fd, int events, struct timeval *tv);
void rb_io_set_nonblock(rb_io_t *fptr);
int rb_io_extract_encoding_option(VALUE opt, rb_encoding **enc_p, rb_encoding **enc2_p, int *fmode_p);
ssize_t rb_io_bufwrite(VALUE io, const void *buf, size_t size);

/* compatibility for ruby 1.8 and older */
#define rb_io_mode_flags(modestr) [<"rb_io_mode_flags() is obsolete; use rb_io_modestr_fmode()">]
#define rb_io_modenum_flags(oflags) [<"rb_io_modenum_flags() is obsolete; use rb_io_oflags_fmode()">]

VALUE rb_io_taint_check(VALUE);
NORETURN(void rb_eof_error(void));

void rb_io_read_check(rb_io_t*);
int rb_io_read_pending(rb_io_t*);

struct stat;
VALUE rb_stat_new(const struct stat *);

/* gc.c */

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_IO_H */
