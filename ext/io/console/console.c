/* -*- c-file-style: "ruby" -*- */
/*
 * console IO module
 */
#include "ruby.h"
#ifdef HAVE_RUBY_IO_H
#include "ruby/io.h"
#else
#include "rubyio.h"
#endif

#ifndef HAVE_RB_IO_T
typedef OpenFile rb_io_t;
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#ifdef HAVE_SYS_IOCTL_H
#include <sys/ioctl.h>
#endif

#if defined HAVE_TERMIOS_H
# include <termios.h>
typedef struct termios conmode;

static int
setattr(int fd, conmode *t)
{
    while (tcsetattr(fd, TCSAFLUSH, t)) {
	if (errno != EINTR) return 0;
    }
    return 1;
}
# define getattr(fd, t) (tcgetattr(fd, t) == 0)
#elif defined HAVE_TERMIO_H
# include <termio.h>
typedef struct termio conmode;
# define setattr(fd, t) (ioctl(fd, TCSETAF, t) == 0)
# define getattr(fd, t) (ioctl(fd, TCGETA, t) == 0)
#elif defined HAVE_SGTTY_H
# include <sgtty.h>
typedef struct sgttyb conmode;
# ifdef HAVE_STTY
# define setattr(fd, t)  (stty(fd, t) == 0)
# else
# define setattr(fd, t)  (ioctl((fd), TIOCSETP, (t)) == 0)
# endif
# ifdef HAVE_GTTY
# define getattr(fd, t)  (gtty(fd, t) == 0)
# else
# define getattr(fd, t)  (ioctl((fd), TIOCGETP, (t)) == 0)
# endif
#elif defined _WIN32
#include <winioctl.h>
typedef DWORD conmode;

#ifdef HAVE_RB_W32_MAP_ERRNO
#define LAST_ERROR rb_w32_map_errno(GetLastError())
#else
#define LAST_ERROR EBADF
#endif
#define SET_LAST_ERROR (errno = LAST_ERROR, 0)

static int
setattr(int fd, conmode *t)
{
    int x = SetConsoleMode((HANDLE)rb_w32_get_osfhandle(fd), *t);
    if (!x) errno = LAST_ERROR;
    return x;
}

static int
getattr(int fd, conmode *t)
{
    int x = GetConsoleMode((HANDLE)rb_w32_get_osfhandle(fd), t);
    if (!x) errno = LAST_ERROR;
    return x;
}
#endif
#ifndef SET_LAST_ERROR
#define SET_LAST_ERROR (0)
#endif

#ifndef InitVM
#define InitVM(ext) {void InitVM_##ext(void);InitVM_##ext();}
#endif

static ID id_getc, id_console;

static void
set_rawmode(conmode *t)
{
#ifdef HAVE_CFMAKERAW
    cfmakeraw(t);
#else
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    t->c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL|IXON);
    t->c_oflag &= ~OPOST;
    t->c_lflag &= ~(ECHO|ECHONL|ICANON|ISIG|IEXTEN);
    t->c_cflag &= ~(CSIZE|PARENB);
    t->c_cflag |= CS8;
#elif defined HAVE_SGTTY_H
    t->sg_flags &= ~ECHO;
    t->sg_flags |= RAW;
#elif defined _WIN32
    *t = 0;
#endif
#endif
}

static void
set_noecho(conmode *t)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    t->c_lflag &= ~(ECHO | ECHOE | ECHOK | ECHONL);
#elif defined HAVE_SGTTY_H
    t->sg_flags &= ~ECHO;
#elif defined _WIN32
    *t &= ~ENABLE_ECHO_INPUT;
#endif
}

static void
set_echo(conmode *t)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    t->c_lflag |= (ECHO | ECHOE | ECHOK | ECHONL);
#elif defined HAVE_SGTTY_H
    t->sg_flags |= ECHO;
#elif defined _WIN32
    *t |= ENABLE_ECHO_INPUT;
#endif
}

static int
echo_p(conmode *t)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    return (t->c_lflag & (ECHO | ECHOE | ECHOK | ECHONL)) != 0;
#elif defined HAVE_SGTTY_H
    return (t->sg_flags & ECHO) != 0;
#elif defined _WIN32
    return (*t & ENABLE_ECHO_INPUT) != 0;
#endif
}

static int
set_ttymode(int fd, conmode *t, void (*setter)(conmode *))
{
    conmode r;
    if (!getattr(fd, t)) return 0;
    r = *t;
    setter(&r);
    return setattr(fd, &r);
}

#ifdef GetReadFile
#define GetReadFD(fptr) fileno(GetReadFile(fptr))
#else
#define GetReadFD(fptr) ((fptr)->fd)
#endif

#ifdef GetWriteFile
#define GetWriteFD(fptr) fileno(GetWriteFile(fptr))
#else
static inline int
get_write_fd(const rb_io_t *fptr)
{
    VALUE wio = fptr->tied_io_for_writing;
    rb_io_t *ofptr;
    if (!wio) return fptr->fd;
    GetOpenFile(wio, ofptr);
    return ofptr->fd;
}
#define GetWriteFD(fptr) get_write_fd(fptr)
#endif

#define FD_PER_IO 2

static VALUE
ttymode(VALUE io, VALUE (*func)(VALUE), void (*setter)(conmode *))
{
    rb_io_t *fptr;
    int status = -1;
    int error = 0;
    int fd[FD_PER_IO];
    conmode t[FD_PER_IO];
    VALUE result = Qnil;

    GetOpenFile(io, fptr);
    fd[0] = GetReadFD(fptr);
    if (fd[0] != -1) {
	if (set_ttymode(fd[0], t+0, setter)) {
	    status = 0;
	}
	else {
	    error = errno;
	    fd[0] = -1;
	}
    }
    fd[1] = GetWriteFD(fptr);
    if (fd[1] != -1 && fd[1] != fd[0]) {
	if (set_ttymode(fd[1], t+1, setter)) {
	    status = 0;
	}
	else {
	    error = errno;
	    fd[1] = -1;
	}
    }
    if (status == 0) {
	result = rb_protect(func, io, &status);
    }
    GetOpenFile(io, fptr);
    if (fd[0] != -1 && fd[0] == GetReadFD(fptr)) {
	if (!setattr(fd[0], t+0)) {
	    error = errno;
	    status = -1;
	}
    }
    if (fd[1] != -1 && fd[1] != fd[0] && fd[1] == GetWriteFD(fptr)) {
	if (!setattr(fd[1], t+1)) {
	    error = errno;
	    status = -1;
	}
    }
    if (status) {
	if (status == -1) {
	    errno = error;
	    rb_sys_fail(0);
	}
	rb_jump_tag(status);
    }
    return result;
}

/*
 * call-seq:
 *   io.raw {|io| }
 *
 * Yields +self+ within raw mode.
 *
 *   STDIN.raw(&:gets)
 *
 * will read and return a line with echo back and line editing.
 */
static VALUE
console_raw(VALUE io)
{
    return ttymode(io, rb_yield, set_rawmode);
}

/*
 * call-seq:
 *   io.raw!
 *
 * Enables raw mode.
 *
 * If the terminal mode needs to be back, use io.raw { ... }.
 */
static VALUE
console_set_raw(VALUE io)
{
    conmode t;
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = GetReadFD(fptr);
    if (!getattr(fd, &t)) rb_sys_fail(0);
    set_rawmode(&t);
    if (!setattr(fd, &t)) rb_sys_fail(0);
    return io;
}

static VALUE
getc_call(VALUE io)
{
    return rb_funcall2(io, id_getc, 0, 0);
}

/*
 * call-seq:
 *   io.getch       -> char
 *
 * Reads and returns a character in raw mode.
 */
static VALUE
console_getch(VALUE io)
{
    return ttymode(io, getc_call, set_rawmode);
}

/*
 * call-seq:
 *   io.noecho {|io| }
 *
 * Yields +self+ with disabling echo back.
 *
 *   STDIN.noecho(&:gets)
 *
 * will read and return a line without echo back.
 */
static VALUE
console_noecho(VALUE io)
{
    return ttymode(io, rb_yield, set_noecho);
}

/*
 * call-seq:
 *   io.echo = flag
 *
 * Enables/disables echo back.
 */
static VALUE
console_set_echo(VALUE io, VALUE f)
{
    conmode t;
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = GetReadFD(fptr);
    if (!getattr(fd, &t)) rb_sys_fail(0);
    if (RTEST(f))
	set_echo(&t);
    else
	set_noecho(&t);
    if (!setattr(fd, &t)) rb_sys_fail(0);
    return io;
}

/*
 * call-seq:
 *   io.echo?       -> true or false
 *
 * Returns +true+ if echo back is enabled.
 */
static VALUE
console_echo_p(VALUE io)
{
    conmode t;
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = GetReadFD(fptr);
    if (!getattr(fd, &t)) rb_sys_fail(0);
    return echo_p(&t) ? Qtrue : Qfalse;
}

#if defined TIOCGWINSZ
typedef struct winsize rb_console_size_t;
#define getwinsize(fd, buf) (ioctl((fd), TIOCGWINSZ, (buf)) == 0)
#define winsize_row(buf) (buf)->ws_row
#define winsize_col(buf) (buf)->ws_col
#elif defined _WIN32
typedef CONSOLE_SCREEN_BUFFER_INFO rb_console_size_t;
#define getwinsize(fd, buf) ( \
    GetConsoleScreenBufferInfo((HANDLE)rb_w32_get_osfhandle(fd), (buf)) || \
    SET_LAST_ERROR)
#define winsize_row(buf) ((buf)->srWindow.Bottom - (buf)->srWindow.Top + 1)
#define winsize_col(buf) (buf)->dwSize.X
#endif

#if defined TIOCGWINSZ || defined _WIN32
#define USE_CONSOLE_GETSIZE 1
#endif

#ifdef USE_CONSOLE_GETSIZE
/*
 * call-seq:
 *   io.winsize     -> [rows, columns]
 *
 * Returns console size.
 */
static VALUE
console_winsize(VALUE io)
{
    rb_io_t *fptr;
    int fd;
    rb_console_size_t ws;

    GetOpenFile(io, fptr);
#ifdef GetWriteFile
    fd = fileno(GetWriteFile(fptr));
#else
# if defined HAVE_RB_IO_GET_WRITE_IO
    io = fptr->tied_io_for_writing;
    if (io) {
	GetOpenFile(io, fptr);
    }
# endif
    fd = fptr->fd;
#endif
    if (!getwinsize(fd, &ws)) rb_sys_fail(0);
    return rb_assoc_new(INT2NUM(winsize_row(&ws)), INT2NUM(winsize_col(&ws)));
}
#endif

/*
 * call-seq:
 *   io.iflush
 *
 * Flushes input buffer in kernel.
 */
static VALUE
console_iflush(VALUE io)
{
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = GetReadFD(fptr);
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    if (tcflush(fd, TCIFLUSH)) rb_sys_fail(0);
#endif
    return io;
}

/*
 * call-seq:
 *   io.oflush
 *
 * Flushes output buffer in kernel.
 */
static VALUE
console_oflush(VALUE io)
{
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = GetWriteFD(fptr);
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    if (tcflush(fd, TCOFLUSH)) rb_sys_fail(0);
#endif
    return io;
}

/*
 * call-seq:
 *   io.ioflush
 *
 * Flushes input and output buffers in kernel.
 */
static VALUE
console_ioflush(VALUE io)
{
    rb_io_t *fptr;
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    int fd1, fd2;
#endif

    GetOpenFile(io, fptr);
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    fd1 = GetReadFD(fptr);
    fd2 = GetWriteFD(fptr);
    if (fd2 != -1 && fd1 != fd2) {
	if (tcflush(fd1, TCIFLUSH)) rb_sys_fail(0);
	if (tcflush(fd2, TCOFLUSH)) rb_sys_fail(0);
    }
    else {
	if (tcflush(fd1, TCIOFLUSH)) rb_sys_fail(0);
    }
#endif
    return io;
}

/*
 * call-seq:
 *   IO.console      -> #<File:/dev/tty>
 *
 * Returns an File instance opened console.
 */
static VALUE
console_dev(VALUE klass)
{
    VALUE con = 0;
    rb_io_t *fptr;

    if (klass == rb_cIO) klass = rb_cFile;
    if (rb_const_defined(klass, id_console)) {
	con = rb_const_get(klass, id_console);
	if (TYPE(con) == T_FILE) {
	    if ((fptr = RFILE(con)->fptr) && GetReadFD(fptr) != -1)
		return con;
	}
	rb_mod_remove_const(klass, ID2SYM(id_console));
    }
    {
	VALUE args[2];
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H || defined HAVE_SGTTY_H
# define CONSOLE_DEVISE "/dev/tty"
#elif defined _WIN32
# define CONSOLE_DEVISE "con$"
# define CONSOLE_DEVISE_FOR_READING "conin$"
# define CONSOLE_DEVISE_FOR_WRITING "conout$"
#endif
#ifndef CONSOLE_DEVISE_FOR_READING
# define CONSOLE_DEVISE_FOR_READING CONSOLE_DEVISE
#endif
#ifdef CONSOLE_DEVISE_FOR_WRITING
	VALUE out;
	rb_io_t *ofptr;
#endif

	args[1] = INT2FIX(O_RDWR);
#ifdef CONSOLE_DEVISE_FOR_WRITING
	args[0] = rb_str_new2(CONSOLE_DEVISE_FOR_WRITING);
	out = rb_class_new_instance(2, args, klass);
#endif
	args[0] = rb_str_new2(CONSOLE_DEVISE_FOR_READING);
	con = rb_class_new_instance(2, args, klass);
#ifdef CONSOLE_DEVISE_FOR_WRITING
	GetOpenFile(con, fptr);
	GetOpenFile(out, ofptr);
# ifdef HAVE_RB_IO_GET_WRITE_IO
#   ifdef _WIN32
	ofptr->pathv = fptr->pathv = rb_str_new2(CONSOLE_DEVISE);
#   endif
	fptr->tied_io_for_writing = out;
# else
	fptr->f2 = ofptr->f;
	ofptr->f = 0;
# endif
	fptr->mode |= FMODE_WRITABLE;
#endif
	rb_const_set(klass, id_console, con);
    }
    return con;
}

/*
 * IO console methods
 */
void
Init_console(void)
{
    id_getc = rb_intern("getc");
    id_console = rb_intern("console");
    InitVM(console);
}

void
InitVM_console(void)
{
    rb_define_method(rb_cIO, "raw", console_raw, 0);
    rb_define_method(rb_cIO, "raw!", console_set_raw, 0);
    rb_define_method(rb_cIO, "getch", console_getch, 0);
    rb_define_method(rb_cIO, "echo=", console_set_echo, 1);
    rb_define_method(rb_cIO, "echo?", console_echo_p, 0);
    rb_define_method(rb_cIO, "noecho", console_noecho, 0);
    rb_define_method(rb_cIO, "winsize", console_winsize, 0);
    rb_define_method(rb_cIO, "iflush", console_iflush, 0);
    rb_define_method(rb_cIO, "oflush", console_oflush, 0);
    rb_define_method(rb_cIO, "ioflush", console_ioflush, 0);
    rb_define_singleton_method(rb_cIO, "console", console_dev, 0);
}
