#ifndef RBIMPL_INTERN_IO_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_IO_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_cIO.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

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

typedef enum {
    RUBY_IO_READABLE = RB_WAITFD_IN,
    RUBY_IO_WRITABLE = RB_WAITFD_OUT,
    RUBY_IO_PRIORITY = RB_WAITFD_PRI,
} rb_io_event_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* io.c */
#define rb_defout rb_stdout
RUBY_EXTERN VALUE rb_fs;
RUBY_EXTERN VALUE rb_output_fs;
RUBY_EXTERN VALUE rb_rs;
RUBY_EXTERN VALUE rb_default_rs;
RUBY_EXTERN VALUE rb_output_rs;
VALUE rb_io_write(VALUE, VALUE);
VALUE rb_io_gets(VALUE);
VALUE rb_io_getbyte(VALUE);
VALUE rb_io_ungetc(VALUE, VALUE);
VALUE rb_io_ungetbyte(VALUE, VALUE);
VALUE rb_io_close(VALUE);
VALUE rb_io_flush(VALUE);
VALUE rb_io_eof(VALUE);
VALUE rb_io_binmode(VALUE);
VALUE rb_io_ascii8bit_binmode(VALUE);
VALUE rb_io_addstr(VALUE, VALUE);
VALUE rb_io_printf(int, const VALUE*, VALUE);
VALUE rb_io_print(int, const VALUE*, VALUE);
VALUE rb_io_puts(int, const VALUE*, VALUE);
VALUE rb_io_fdopen(int, int, const char*);
VALUE rb_io_get_io(VALUE);
VALUE rb_file_open(const char*, const char*);
VALUE rb_file_open_str(VALUE, const char*);
VALUE rb_gets(void);
void rb_write_error(const char*);
void rb_write_error2(const char*, long);
void rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds);
int rb_pipe(int *pipes);
int rb_reserved_fd_p(int fd);
int rb_cloexec_open(const char *pathname, int flags, mode_t mode);
int rb_cloexec_dup(int oldfd);
int rb_cloexec_dup2(int oldfd, int newfd);
int rb_cloexec_pipe(int fildes[2]);
int rb_cloexec_fcntl_dupfd(int fd, int minfd);
#define RB_RESERVED_FD_P(fd) rb_reserved_fd_p(fd)
void rb_update_max_fd(int fd);
void rb_fd_fix_cloexec(int fd);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_maybe_wait_readable"))
int rb_io_wait_readable(int fd);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_maybe_wait_writable"))
int rb_io_wait_writable(int fd);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_wait"))
int rb_wait_for_single_fd(int fd, int events, struct timeval *tv);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_IO_H */
