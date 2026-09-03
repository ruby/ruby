/* -*- c-file-style: "ruby"; indent-tabs-mode: t -*- */
/*
 * console IO module
 */

static const char *const
IO_CONSOLE_VERSION = "0.9.2";

#include "ruby.h"
#include "ruby/io.h"
#include "ruby/thread.h"

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
    while (tcsetattr(fd, TCSANOW, t)) {
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
#include <conio.h>
typedef DWORD conmode;

#ifndef ENABLE_WRAP_AT_EOL_OUTPUT
# define ENABLE_WRAP_AT_EOL_OUTPUT 0x0002
#endif
#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
# define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif

#define LAST_ERROR rb_w32_map_errno(GetLastError())
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

#define CSI "\x1b\x5b"

static ID id_getc, id_close, id_timeout;
static ID id_gets, id_flush, id_chomp_bang;

#ifndef HAVE_RB_INTERNED_STR_CSTR
# define rb_str_to_interned_str(str) rb_str_freeze(str)
# define rb_interned_str_cstr(str) rb_str_freeze(rb_usascii_str_new_cstr(str))
#endif

#if !defined(HAVE_RB_CATEGORY_WARN) || !defined(HAVE_CONST_RB_WARN_CATEGORY_DEPRECATED)
# define rb_category_warn(category, ...) rb_warn(__VA_ARGS__)
#endif

#if defined HAVE_RUBY_FIBER_SCHEDULER_H
# include "ruby/fiber/scheduler.h"
#elif defined HAVE_RB_SCHEDULER_TIMEOUT
extern VALUE rb_scheduler_timeout(struct timeval *timeout);
# define rb_fiber_scheduler_make_timeout rb_scheduler_timeout
#endif

#ifndef HAVE_RB_IO_DESCRIPTOR
static int
io_descriptor_fallback(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return fptr->fd;
}
#define rb_io_descriptor io_descriptor_fallback
#endif

#ifndef HAVE_RB_IO_PATH
static VALUE
io_path_fallback(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return fptr->pathv;
}
#define rb_io_path io_path_fallback
#endif

#define sys_fail(io) do { \
    int err = errno; \
    rb_syserr_fail_str(err, rb_io_path(io)); \
} while (0)

#ifndef HAVE_RB_F_SEND
#ifndef RB_PASS_CALLED_KEYWORDS
# define rb_funcallv_kw(recv, mid, arg, argv, kw_splat) rb_funcallv(recv, mid, arg, argv)
#endif

static ID id___send__;

static VALUE
rb_f_send(int argc, VALUE *argv, VALUE recv)
{
    VALUE sym = argv[0];
    ID vid = rb_check_id(&sym);
    if (vid) {
	--argc;
	++argv;
    }
    else {
	vid = id___send__;
    }
    return rb_funcallv_kw(recv, vid, argc, argv, RB_PASS_CALLED_KEYWORDS);
}
#endif

enum rawmode_opt_ids {
    kwd_min,
    kwd_time,
    kwd_intr,
    rawmode_opt_id_count
};
static ID rawmode_opt_ids[rawmode_opt_id_count];

typedef struct {
    int vmin;
    int vtime;
    int intr;
} rawmode_arg_t;

#ifndef UNDEF_P
# define UNDEF_P(obj) ((obj) == Qundef)
#endif
#ifndef NIL_OR_UNDEF_P
# define NIL_OR_UNDEF_P(obj) (NIL_P(obj) || UNDEF_P(obj))
#endif

static rawmode_arg_t *
rawmode_opt(int *argcp, VALUE *argv, int min_argc, int max_argc, rawmode_arg_t *opts)
{
    int argc = *argcp;
    rawmode_arg_t *optp = NULL;
    VALUE vopts = Qnil;
    VALUE optvals[rawmode_opt_id_count];
#ifdef RB_SCAN_ARGS_PASS_CALLED_KEYWORDS
    argc = rb_scan_args(argc, argv, "*:", NULL, &vopts);
#else
    if (argc > min_argc)  {
	vopts = rb_check_hash_type(argv[argc-1]);
	if (!NIL_P(vopts)) {
	    argv[argc-1] = vopts;
	    vopts = rb_extract_keywords(&argv[argc-1]);
	    if (!argv[argc-1]) *argcp = --argc;
	    if (!vopts) vopts = Qnil;
	}
    }
#endif
    rb_check_arity(argc, min_argc, max_argc);
    if (rb_get_kwargs(vopts, rawmode_opt_ids,
		      0, rawmode_opt_id_count, optvals)) {
	VALUE vmin = optvals[kwd_min];
	VALUE vtime = optvals[kwd_time];
	VALUE intr = optvals[kwd_intr];
	/* default values by `stty raw` */
	opts->vmin = 1;
	opts->vtime = 0;
	opts->intr = 0;
	if (!NIL_OR_UNDEF_P(vmin)) {
	    opts->vmin = NUM2INT(vmin);
	    optp = opts;
	}
	if (!NIL_OR_UNDEF_P(vtime)) {
	    VALUE v10 = INT2FIX(10);
	    vtime = rb_funcall3(vtime, '*', 1, &v10);
	    opts->vtime = NUM2INT(vtime);
	    optp = opts;
	}
	switch (intr) {
	  case Qtrue:
	    opts->intr = 1;
	    optp = opts;
	    break;
	  case Qfalse:
	    opts->intr = 0;
	    optp = opts;
	    break;
	  case Qundef:
	  case Qnil:
	    break;
	  default:
	    rb_raise(rb_eArgError, "true or false expected as intr: %"PRIsVALUE,
		     intr);
	}
    }
    return optp;
}

static void
set_rawmode(conmode *t, void *arg)
{
#ifdef HAVE_CFMAKERAW
    cfmakeraw(t);
    t->c_lflag &= ~(ECHOE|ECHOK);
#elif defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    t->c_iflag &= ~(IGNBRK|BRKINT|IGNPAR|PARMRK|INPCK|ISTRIP|INLCR|IGNCR|ICRNL|IXON|IXOFF|IXANY|IMAXBEL);
    t->c_oflag &= ~OPOST;
    t->c_lflag &= ~(ECHO|ECHOE|ECHOK|ECHONL|ICANON|ISIG|IEXTEN|XCASE);
    t->c_cflag &= ~(CSIZE|PARENB);
    t->c_cflag |= CS8;
    t->c_cc[VMIN] = 1;
    t->c_cc[VTIME] = 0;
#elif defined HAVE_SGTTY_H
    t->sg_flags &= ~ECHO;
    t->sg_flags |= RAW;
#elif defined _WIN32
    *t = 0;
#endif
    if (arg) {
	const rawmode_arg_t *r = arg;
#ifdef VMIN
	if (r->vmin >= 0) t->c_cc[VMIN] = r->vmin;
#endif
#ifdef VTIME
	if (r->vtime >= 0) t->c_cc[VTIME] = r->vtime;
#endif
#ifdef ISIG
	if (r->intr) {
	    t->c_iflag |= BRKINT;
	    t->c_lflag |= ISIG;
	    t->c_oflag |= OPOST;
	}
#endif
	(void)r;
    }
}

static void
set_cookedmode(conmode *t, void *arg)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    t->c_iflag |= (BRKINT|ISTRIP|ICRNL|IXON);
    t->c_oflag |= OPOST;
    t->c_lflag |= (ECHO|ECHOE|ECHOK|ECHONL|ICANON|ISIG|IEXTEN);
#elif defined HAVE_SGTTY_H
    t->sg_flags |= ECHO;
    t->sg_flags &= ~RAW;
#elif defined _WIN32
    *t |= ENABLE_ECHO_INPUT|ENABLE_LINE_INPUT|ENABLE_PROCESSED_INPUT;
#endif
}

static void
set_noecho(conmode *t, void *arg)
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
set_echo(conmode *t, void *arg)
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
    return (t->c_lflag & (ECHO | ECHONL)) != 0;
#elif defined HAVE_SGTTY_H
    return (t->sg_flags & ECHO) != 0;
#elif defined _WIN32
    return (*t & ENABLE_ECHO_INPUT) != 0;
#endif
}

static int
set_ttymode(int fd, conmode *t, void (*setter)(conmode *, void *), void *arg)
{
    conmode r;
    if (!getattr(fd, t)) return 0;
    r = *t;
    setter(&r, arg);
    return setattr(fd, &r);
}

#define GetReadFD(io) rb_io_descriptor(io)
#define GetWriteFD(io) rb_io_descriptor(rb_io_get_write_io(io))

#define FD_PER_IO 2

static VALUE
ttymode(VALUE io, VALUE (*func)(VALUE), VALUE farg, void (*setter)(conmode *, void *), void *arg)
{
    int status = -1;
    int error = 0;
    int fd[FD_PER_IO];
    conmode t[FD_PER_IO];
    VALUE result = Qnil;

    fd[0] = GetReadFD(io);
    if (fd[0] != -1) {
	if (set_ttymode(fd[0], t+0, setter, arg)) {
	    status = 0;
	}
	else {
	    error = errno;
	    fd[0] = -1;
	}
    }
    fd[1] = GetWriteFD(io);
    if (fd[1] != -1 && fd[1] != fd[0]) {
	if (set_ttymode(fd[1], t+1, setter, arg)) {
	    status = 0;
	}
	else {
	    error = errno;
	    fd[1] = -1;
	}
    }
    if (status == 0) {
	result = rb_protect(func, farg, &status);
    }
    if (fd[0] != -1 && fd[0] == GetReadFD(io)) {
	if (!setattr(fd[0], t+0)) {
	    error = errno;
	    status = -1;
	}
    }
    if (fd[1] != -1 && fd[1] != fd[0] && fd[1] == GetWriteFD(io)) {
	if (!setattr(fd[1], t+1)) {
	    error = errno;
	    status = -1;
	}
    }
    if (status) {
	if (status == -1) {
	    rb_syserr_fail(error, 0);
	}
	rb_jump_tag(status);
    }
    return result;
}

#if !defined _WIN32
struct ttymode_callback_args {
    VALUE (*func)(VALUE, VALUE);
    VALUE io;
    VALUE farg;
};

static VALUE
ttymode_callback(VALUE args)
{
    struct ttymode_callback_args *argp = (struct ttymode_callback_args *)args;
    return argp->func(argp->io, argp->farg);
}

static VALUE
ttymode_with_io(VALUE io, VALUE (*func)(VALUE, VALUE), VALUE farg, void (*setter)(conmode *, void *), void *arg)
{
    struct ttymode_callback_args cargs;
    cargs.func = func;
    cargs.io = io;
    cargs.farg = farg;
    return ttymode(io, ttymode_callback, (VALUE)&cargs, setter, arg);
}
#endif

/*
 * call-seq:
 *   io.raw(min: nil, time: nil, intr: nil) {|io| }
 *
 * Yields +self+ within raw mode, and returns the result of the block.
 *
 *   STDIN.raw(&:gets)
 *
 * will read and return a line without echo back and line editing.
 *
 * The parameter +min+ specifies the minimum number of bytes that
 * should be received when a read operation is performed. (default: 1)
 *
 * The parameter +time+ specifies the timeout in _seconds_ with a
 * precision of 1/10 of a second. (default: 0)
 *
 * If the parameter +intr+ is +true+, enables break, interrupt, quit,
 * and suspend special characters.
 *
 * Refer to the manual page of termios for further details.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_raw(int argc, VALUE *argv, VALUE io)
{
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 0, &opts);
    return ttymode(io, rb_yield, io, set_rawmode, optp);
}

/*
 * call-seq:
 *   io.raw!(min: nil, time: nil, intr: nil) -> io
 *
 * Enables raw mode, and returns +io+.
 *
 * If the terminal mode needs to be back, use <code>io.raw { ... }</code>.
 *
 * See IO#raw for details on the parameters.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_set_raw(int argc, VALUE *argv, VALUE io)
{
    conmode t;
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 0, &opts);
    int fd = GetReadFD(io);
    if (!getattr(fd, &t)) sys_fail(io);
    set_rawmode(&t, optp);
    if (!setattr(fd, &t)) sys_fail(io);
    return io;
}

/*
 * call-seq:
 *   io.cooked {|io| }
 *
 * Yields +self+ within cooked mode.
 *
 *   STDIN.cooked(&:gets)
 *
 * will read and return a line with echo back and line editing.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cooked(VALUE io)
{
    return ttymode(io, rb_yield, io, set_cookedmode, NULL);
}

/*
 * call-seq:
 *   io.cooked!
 *
 * Enables cooked mode.
 *
 * If the terminal mode needs to be back, use io.cooked { ... }.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_set_cooked(VALUE io)
{
    conmode t;
    int fd = GetReadFD(io);
    if (!getattr(fd, &t)) sys_fail(io);
    set_cookedmode(&t, NULL);
    if (!setattr(fd, &t)) sys_fail(io);
    return io;
}

#ifndef _WIN32
static VALUE
getc_call(VALUE io)
{
    return rb_funcallv(io, id_getc, 0, 0);
}
#else
static void *
nogvl_getch(void *p)
{
    int len = 0;
    wint_t *buf = p, c = _getwch();

    switch (c) {
      case WEOF:
	break;
      case 0x00:
      case 0xe0:
	buf[len++] = c;
	c = _getwch();
	/* fall through */
      default:
	buf[len++] = c;
	break;
    }
    return (void *)(VALUE)len;
}
#endif

/*
 * call-seq:
 *   io.getch(min: nil, time: nil, intr: nil) -> char or nil
 *
 * Reads and returns a character in raw mode.
 *
 * See IO#raw for details on the parameters.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_getch(int argc, VALUE *argv, VALUE io)
{
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 0, &opts);
#ifndef _WIN32
    return ttymode(io, getc_call, io, set_rawmode, optp);
#else
    rb_io_t *fptr;
    VALUE str;
    wint_t c;
    int len;
    char buf[8];
    wint_t wbuf[2];
# ifndef HAVE_RB_IO_WAIT
    struct timeval *to = NULL, tv;
# else
    VALUE timeout = Qnil;
# endif

    GetOpenFile(io, fptr);
    if (optp) {
	if (optp->vtime) {
# ifndef HAVE_RB_IO_WAIT
	    to = &tv;
# else
	    struct timeval tv;
# endif
	    tv.tv_sec = optp->vtime / 10;
	    tv.tv_usec = (optp->vtime % 10) * 100000;
# ifdef HAVE_RB_IO_WAIT
	    timeout = rb_fiber_scheduler_make_timeout(&tv);
# endif
	}
	switch (optp->vmin) {
	  case 1: /* default */
	    break;
	  case 0: /* return nil when timed out */
	    if (optp->vtime) break;
	    /* fallthru */
	  default:
	    rb_warning("min option larger than 1 ignored");
	}
	if (optp->intr) {
# ifndef HAVE_RB_IO_WAIT
	    int w = rb_wait_for_single_fd(fptr->fd, RB_WAITFD_IN, to);
	    if (w < 0) rb_eof_error();
	    if (!(w & RB_WAITFD_IN)) return Qnil;
# else
	    VALUE result = rb_io_wait(io, RB_INT2NUM(RUBY_IO_READABLE), timeout);
	    if (!RTEST(result)) return Qnil;
# endif
	}
	else if (optp->vtime) {
	    rb_warning("Non-zero vtime option ignored if intr flag is unset");
	}
    }
    len = (int)(VALUE)rb_thread_call_without_gvl(nogvl_getch, wbuf, RUBY_UBF_IO, 0);
    switch (len) {
      case 0:
	return Qnil;
      case 2:
	buf[0] = (char)wbuf[0];
	c = wbuf[1];
	len = 1;
	do {
	    buf[len++] = (unsigned char)c;
	} while ((c >>= CHAR_BIT) && len < (int)sizeof(buf));
	return rb_str_new(buf, len);
      default:
	c = wbuf[0];
	len = rb_uv_to_utf8(buf, c);
	str = rb_utf8_str_new(buf, len);
	return rb_str_conv_enc(str, NULL, rb_default_external_encoding());
    }
#endif
}

/*
 * call-seq:
 *   io.input_pending?          -> true or false
 *
 * Returns whether input can be read without blocking.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_input_pending_p(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (rb_io_read_pending(fptr)) return Qtrue;
#ifdef _WIN32
    {
	DWORD mode;
	HANDLE h = (HANDLE)rb_w32_get_osfhandle(GetReadFD(io));

	if (GetConsoleMode(h, &mode)) return _kbhit() ? Qtrue : Qfalse;
    }
#endif
#if defined HAVE_RB_IO_WAIT
    return RTEST(rb_io_wait(io, RB_INT2NUM(RUBY_IO_READABLE), INT2FIX(0))) ? Qtrue : Qfalse;
#else
    {
	struct timeval timeout = {0, 0};
	int result;

	result = rb_wait_for_single_fd(fptr->fd, RB_WAITFD_IN, &timeout);
	if (result < 0) sys_fail(io);
	return (result & RB_WAITFD_IN) ? Qtrue : Qfalse;
    }
#endif
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
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_noecho(VALUE io)
{
    return ttymode(io, rb_yield, io, set_noecho, NULL);
}

/*
 * call-seq:
 *   io.echo = flag
 *
 * Enables/disables echo back.
 * On some platforms, all combinations of this flags and raw/cooked
 * mode may not be valid.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_set_echo(VALUE io, VALUE f)
{
    conmode t;
    int fd = GetReadFD(io);

    if (!getattr(fd, &t)) sys_fail(io);

    if (RTEST(f))
        set_echo(&t, NULL);
    else
        set_noecho(&t, NULL);

    if (!setattr(fd, &t)) sys_fail(io);

    return io;
}

/*
 * call-seq:
 *   io.echo?       -> true or false
 *
 * Returns +true+ if echo back is enabled.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_echo_p(VALUE io)
{
    conmode t;
    int fd = GetReadFD(io);

    if (!getattr(fd, &t)) sys_fail(io);
    return echo_p(&t) ? Qtrue : Qfalse;
}

static const rb_data_type_t conmode_type = {
    "console-mode",
    {0, RUBY_TYPED_DEFAULT_FREE,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};
static VALUE cConmode;

static VALUE
conmode_alloc(VALUE klass)
{
    return rb_data_typed_object_zalloc(klass, sizeof(conmode), &conmode_type);
}

static VALUE
conmode_new(VALUE klass, const conmode *t)
{
    VALUE obj = conmode_alloc(klass);
    *(conmode *)DATA_PTR(obj) = *t;
    return obj;
}

static VALUE
conmode_init_copy(VALUE obj, VALUE obj2)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    conmode *t2 = rb_check_typeddata(obj2, &conmode_type);
    *t = *t2;
    return obj;
}

static VALUE
conmode_set_echo(VALUE obj, VALUE f)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    if (RTEST(f))
	set_echo(t, NULL);
    else
	set_noecho(t, NULL);
    return obj;
}

static VALUE
conmode_set_raw(int argc, VALUE *argv, VALUE obj)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 0, &opts);

    set_rawmode(t, optp);
    return obj;
}

static VALUE
conmode_raw_new(int argc, VALUE *argv, VALUE obj)
{
    conmode *r = rb_check_typeddata(obj, &conmode_type);
    conmode t = *r;
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 0, &opts);

    set_rawmode(&t, optp);
    return conmode_new(rb_obj_class(obj), &t);
}

#ifdef _WIN32
/*
 * call-seq:
 *   mode.virtual_terminal_processing? -> true or false
 *
 * Returns whether virtual terminal sequences are processed on output.
 */
static VALUE
conmode_virtual_terminal_processing_p(VALUE obj)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    return (*t & ENABLE_VIRTUAL_TERMINAL_PROCESSING) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   mode.virtual_terminal_processing = enabled
 *
 * Enables or disables virtual terminal sequence processing in +mode+.
 * Assign +mode+ to IO#console_mode= to apply the change.
 */
static VALUE
conmode_set_virtual_terminal_processing(VALUE obj, VALUE enabled)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    if (RTEST(enabled))
	*t |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    else
	*t &= ~ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    return obj;
}

/*
 * call-seq:
 *   mode.wrap_at_eol_output? -> true or false
 *
 * Returns whether output wraps at the end of a line.
 */
static VALUE
conmode_wrap_at_eol_output_p(VALUE obj)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    return (*t & ENABLE_WRAP_AT_EOL_OUTPUT) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   mode.wrap_at_eol_output = enabled
 *
 * Enables or disables wrapping at the end of a line in +mode+.
 * Assign +mode+ to IO#console_mode= to apply the change.
 */
static VALUE
conmode_set_wrap_at_eol_output(VALUE obj, VALUE enabled)
{
    conmode *t = rb_check_typeddata(obj, &conmode_type);
    if (RTEST(enabled))
	*t |= ENABLE_WRAP_AT_EOL_OUTPUT;
    else
	*t &= ~ENABLE_WRAP_AT_EOL_OUTPUT;
    return obj;
}
#endif

/*
 * call-seq:
 *   io.console_mode       -> mode
 *
 * Returns a data represents the current console mode.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_conmode_get(VALUE io)
{
    conmode t;
    int fd = GetReadFD(io);

    if (!getattr(fd, &t)) sys_fail(io);

    return conmode_new(cConmode, &t);
}

/*
 * call-seq:
 *   io.console_mode = mode
 *
 * Sets the console mode to +mode+.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_conmode_set(VALUE io, VALUE mode)
{
    conmode *t, r;
    int fd = GetReadFD(io);

    TypedData_Get_Struct(mode, conmode, &conmode_type, t);
    r = *t;

    if (!setattr(fd, &r)) sys_fail(io);

    return mode;
}

#if defined TIOCGWINSZ
typedef struct winsize rb_console_size_t;
#define getwinsize(fd, buf) (ioctl((fd), TIOCGWINSZ, (buf)) == 0)
#define setwinsize(fd, buf) (ioctl((fd), TIOCSWINSZ, (buf)) == 0)
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
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_winsize(VALUE io)
{
    rb_console_size_t ws;
    int fd = GetWriteFD(io);
    if (!getwinsize(fd, &ws)) sys_fail(io);
    return rb_assoc_new(INT2NUM(winsize_row(&ws)), INT2NUM(winsize_col(&ws)));
}

static VALUE console_scroll(VALUE io, int line);
static VALUE console_goto(VALUE io, VALUE y, VALUE x);

/*
 * call-seq:
 *   io.winsize = [rows, columns]
 *
 * Tries to set console size.  The effect depends on the platform and
 * the running environment.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_set_winsize(VALUE io, VALUE size)
{
    rb_console_size_t ws;
#if defined _WIN32
    HANDLE wh;
    int newrow, newcol;
    COORD oldsize;
    SMALL_RECT oldwindow;
#endif
    VALUE row, col, xpixel, ypixel;
    const VALUE *sz;
    long sizelen;
    int fd;

    size = rb_Array(size);
    if ((sizelen = RARRAY_LEN(size)) != 2 && sizelen != 4) {
        rb_raise(rb_eArgError, "wrong number of arguments (given %ld, expected 2 or 4)", sizelen);
    }
    sz = RARRAY_CONST_PTR(size);
    row = sz[0], col = sz[1], xpixel = ypixel = Qnil;
    if (sizelen == 4) xpixel = sz[2], ypixel = sz[3];
    fd = GetWriteFD(io);
#if defined TIOCSWINSZ
    ws.ws_row = ws.ws_col = ws.ws_xpixel = ws.ws_ypixel = 0;
#define SET(m) ws.ws_##m = NIL_P(m) ? 0 : (unsigned short)NUM2UINT(m)
    SET(row);
    SET(col);
    SET(xpixel);
    SET(ypixel);
#undef SET
    if (!setwinsize(fd, &ws)) sys_fail(io);
#elif defined _WIN32
    wh = (HANDLE)rb_w32_get_osfhandle(fd);
#define SET(m) new##m = NIL_P(m) ? 0 : (unsigned short)NUM2UINT(m)
    SET(row);
    SET(col);
#undef SET
    if (!NIL_P(xpixel)) (void)NUM2UINT(xpixel);
    if (!NIL_P(ypixel)) (void)NUM2UINT(ypixel);
    if (!GetConsoleScreenBufferInfo(wh, &ws)) {
	rb_syserr_fail(LAST_ERROR, "GetConsoleScreenBufferInfo");
    }
    oldsize = ws.dwSize;
    oldwindow = ws.srWindow;
    if (ws.srWindow.Right + 1 < newcol) {
        ws.dwSize.X = newcol;
    }
    if (ws.dwSize.Y < newrow) {
        ws.dwSize.Y = newrow;
    }
    /* expand screen buffer first if needed */
    if (!SetConsoleScreenBufferSize(wh, ws.dwSize)) {
        rb_syserr_fail(LAST_ERROR, "SetConsoleScreenBufferInfo");
    }
    /* refresh ws for new dwMaximumWindowSize */
    if (!GetConsoleScreenBufferInfo(wh, &ws)) {
        rb_syserr_fail(LAST_ERROR, "GetConsoleScreenBufferInfo");
    }
    /* check new size before modifying buffer content */
    if (newrow <= 0 || newcol <= 0 ||
        newrow > ws.dwMaximumWindowSize.Y ||
        newcol > ws.dwMaximumWindowSize.X) {
        SetConsoleScreenBufferSize(wh, oldsize);
        /* remove scrollbar if possible */
        SetConsoleWindowInfo(wh, TRUE, &oldwindow);
        rb_raise(rb_eArgError, "out of range winsize: [%d, %d]", newrow, newcol);
    }
    /* shrink screen buffer width */
    ws.dwSize.X = newcol;
    /* shrink screen buffer height if window height were the same */
    if (oldsize.Y == ws.srWindow.Bottom - ws.srWindow.Top + 1) {
        ws.dwSize.Y = newrow;
    }
    ws.srWindow.Left = 0;
    ws.srWindow.Right = newcol - 1;
    ws.srWindow.Bottom = ws.srWindow.Top + newrow -1;
    if (ws.dwCursorPosition.Y > ws.srWindow.Bottom) {
        console_scroll(io, ws.dwCursorPosition.Y - ws.srWindow.Bottom);
        ws.dwCursorPosition.Y = ws.srWindow.Bottom;
        console_goto(io, INT2FIX(ws.dwCursorPosition.Y), INT2FIX(ws.dwCursorPosition.X));
    }
    if (ws.srWindow.Bottom > ws.dwSize.Y - 1) {
        console_scroll(io, ws.srWindow.Bottom - (ws.dwSize.Y - 1));
        ws.dwCursorPosition.Y -= ws.srWindow.Bottom - (ws.dwSize.Y - 1);
        console_goto(io, INT2FIX(ws.dwCursorPosition.Y), INT2FIX(ws.dwCursorPosition.X));
	ws.srWindow.Bottom = ws.dwSize.Y - 1;
    }
    ws.srWindow.Top = ws.srWindow.Bottom - (newrow - 1);
    /* perform changes to winsize */
    if (!SetConsoleWindowInfo(wh, TRUE, &ws.srWindow)) {
        int last_error = LAST_ERROR;
        SetConsoleScreenBufferSize(wh, oldsize);
	rb_syserr_fail(last_error, "SetConsoleWindowInfo");
    }
    /* perform screen buffer shrinking if necessary */
    if ((ws.dwSize.Y < oldsize.Y || ws.dwSize.X < oldsize.X) &&
        !SetConsoleScreenBufferSize(wh, ws.dwSize)) {
        rb_syserr_fail(LAST_ERROR, "SetConsoleScreenBufferInfo");
    }
    /* remove scrollbar if possible */
    if (!SetConsoleWindowInfo(wh, TRUE, &ws.srWindow)) {
	rb_syserr_fail(LAST_ERROR, "SetConsoleWindowInfo");
    }
#endif
    return io;
}
#endif

#ifdef _WIN32
enum console_input_handle_index {
    console_input_handle,
    console_input_wakeup,
    console_input_handle_count
};

typedef struct {
    HANDLE handles[console_input_handle_count];
    INPUT_RECORD *records;
    DWORD length;
    DWORD count;
    DWORD timeout;
    DWORD wait_result;
    DWORD error;
    BOOL result;
} read_console_input_args_t;

static void *
nogvl_read_console_input(void *ptr)
{
    read_console_input_args_t *args = ptr;

    args->wait_result = WaitForMultipleObjects(console_input_handle_count,
					       args->handles, FALSE, args->timeout);
    if (args->wait_result == WAIT_OBJECT_0 + console_input_handle) {
	args->result = ReadConsoleInputW(args->handles[console_input_handle],
					 args->records, args->length, &args->count);
	if (!args->result) args->error = GetLastError();
    }
    else if (args->wait_result == WAIT_FAILED) {
	args->error = GetLastError();
    }
    return 0;
}

static void
ubf_console_input(void *ptr)
{
    read_console_input_args_t *args = ptr;
    SetEvent(args->handles[console_input_wakeup]);
}

static void
console_input_event_set(VALUE event, const char *name, VALUE value)
{
    rb_hash_aset(event, ID2SYM(rb_intern(name)), value);
}

static VALUE
console_input_event(const INPUT_RECORD *record)
{
    VALUE event = rb_hash_new();

    switch (record->EventType) {
      case KEY_EVENT:
	console_input_event_set(event, "type", ID2SYM(rb_intern("key")));
	console_input_event_set(event, "key_down", record->Event.KeyEvent.bKeyDown ? Qtrue : Qfalse);
	console_input_event_set(event, "repeat_count", UINT2NUM(record->Event.KeyEvent.wRepeatCount));
	console_input_event_set(event, "virtual_key_code", UINT2NUM(record->Event.KeyEvent.wVirtualKeyCode));
	console_input_event_set(event, "virtual_scan_code", UINT2NUM(record->Event.KeyEvent.wVirtualScanCode));
	console_input_event_set(event, "unicode_char", UINT2NUM(record->Event.KeyEvent.uChar.UnicodeChar));
	console_input_event_set(event, "control_key_state", UINT2NUM(record->Event.KeyEvent.dwControlKeyState));
	break;
      case MOUSE_EVENT:
	console_input_event_set(event, "type", ID2SYM(rb_intern("mouse")));
	console_input_event_set(event, "position", rb_assoc_new(
	    INT2NUM(record->Event.MouseEvent.dwMousePosition.Y),
	    INT2NUM(record->Event.MouseEvent.dwMousePosition.X)));
	console_input_event_set(event, "button_state", UINT2NUM(record->Event.MouseEvent.dwButtonState));
	console_input_event_set(event, "control_key_state", UINT2NUM(record->Event.MouseEvent.dwControlKeyState));
	console_input_event_set(event, "event_flags", UINT2NUM(record->Event.MouseEvent.dwEventFlags));
	break;
      case WINDOW_BUFFER_SIZE_EVENT:
	console_input_event_set(event, "type", ID2SYM(rb_intern("window_buffer_size")));
	console_input_event_set(event, "size", rb_assoc_new(
	    INT2NUM(record->Event.WindowBufferSizeEvent.dwSize.Y),
	    INT2NUM(record->Event.WindowBufferSizeEvent.dwSize.X)));
	break;
      case MENU_EVENT:
	console_input_event_set(event, "type", ID2SYM(rb_intern("menu")));
	console_input_event_set(event, "command_id", UINT2NUM(record->Event.MenuEvent.dwCommandId));
	break;
      case FOCUS_EVENT:
	console_input_event_set(event, "type", ID2SYM(rb_intern("focus")));
	console_input_event_set(event, "set_focus", record->Event.FocusEvent.bSetFocus ? Qtrue : Qfalse);
	break;
      default:
	console_input_event_set(event, "type", UINT2NUM(record->EventType));
	break;
    }

    return event;
}

static VALUE
console_input_events_read(VALUE vargs)
{
    read_console_input_args_t *args = (read_console_input_args_t *)vargs;
    VALUE events;
    DWORD i;

    rb_thread_call_without_gvl(nogvl_read_console_input, args,
			       ubf_console_input, args);
    if (args->wait_result == WAIT_TIMEOUT) return rb_ary_new();
    if (args->wait_result != WAIT_OBJECT_0 + console_input_handle ||
	!args->result) {
	rb_syserr_fail(rb_w32_map_errno(args->error), 0);
    }

    events = rb_ary_new_capa(args->count);
    for (i = 0; i < args->count; ++i) {
	rb_ary_push(events, console_input_event(&args->records[i]));
    }
    return events;
}

static VALUE
console_input_events_ensure(VALUE vargs)
{
    read_console_input_args_t *args = (read_console_input_args_t *)vargs;

    CloseHandle(args->handles[console_input_wakeup]);
    xfree(args->records);
    return Qnil;
}

/*
 * call-seq:
 *   io.console_input_events([max_events], timeout: nil)   -> array
 *
 * Reads up to +max_events+ console input events, preserving their order.
 * The default is one event.  Blocks until at least one event is available,
 * or for +timeout+ seconds if specified.  Returns an empty Array on timeout.
 *
 * Each event is returned as a Hash.  The +:type+ and remaining keys are:
 *
 * - +:key+ : +:key_down+, +:repeat_count+, +:virtual_key_code+,
 *   +:virtual_scan_code+, +:unicode_char+, and +:control_key_state+.
 * - +:mouse+ : +:position+ ([row, column]), +:button_state+,
 *   +:control_key_state+, and +:event_flags+.
 * - +:window_buffer_size+ : +:size+ ([rows, columns]).
 * - +:menu+ : +:command_id+.
 * - +:focus+ : +:set_focus+.
 *
 * This method is Windows only.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_input_events(int argc, VALUE *argv, VALUE io)
{
    VALUE vmax = Qnil, vopts = Qnil, vtimeout = Qundef;
    VALUE values[1];
    ID keywords[1] = {id_timeout};
    DWORD max_events = 1;
    read_console_input_args_t args;

    rb_scan_args(argc, argv, "01:", &vmax, &vopts);
    if (rb_get_kwargs(vopts, keywords, 0, 1, values)) {
	vtimeout = values[0];
    }
    if (!NIL_P(vmax)) {
	max_events = NUM2UINT(vmax);
	if (max_events == 0) rb_raise(rb_eArgError, "max_events must be positive");
    }

    args.timeout = INFINITE;
    if (!NIL_OR_UNDEF_P(vtimeout)) {
	struct timeval timeout = rb_time_interval(vtimeout);
	uint64_t milliseconds = (uint64_t)timeout.tv_sec * 1000;
	milliseconds += ((uint64_t)timeout.tv_usec + 999) / 1000;
	args.timeout = milliseconds < INFINITE ? (DWORD)milliseconds : INFINITE - 1;
    }

    args.handles[console_input_handle] =
	(HANDLE)rb_w32_get_osfhandle(GetReadFD(io));
    args.records = ALLOC_N(INPUT_RECORD, max_events);
    args.handles[console_input_wakeup] = CreateEvent(NULL, FALSE, FALSE, NULL);
    if (!args.handles[console_input_wakeup]) {
	int error = LAST_ERROR;
	xfree(args.records);
	rb_syserr_fail(error, 0);
    }
    args.length = max_events;
    args.count = 0;
    args.wait_result = WAIT_FAILED;
    args.error = ERROR_SUCCESS;
    args.result = FALSE;
    return rb_ensure(console_input_events_read, (VALUE)&args,
		     console_input_events_ensure, (VALUE)&args);
}

/*
 * call-seq:
 *   io.check_winsize_changed { ... }   -> io
 *
 * Yields while console input events are queued.
 *
 * Deprecated because it discards queued input events other than window buffer
 * size changes.  Use IO#console_input_events instead to preserve all events.
 *
 * This method is Windows only.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_check_winsize_changed(VALUE io)
{
    HANDLE h;
    DWORD num;

    rb_category_warn(RB_WARN_CATEGORY_DEPRECATED,
		     "IO#check_winsize_changed is deprecated; "
		     "use IO#console_input_events instead");
    h = (HANDLE)rb_w32_get_osfhandle(GetReadFD(io));
    while (GetNumberOfConsoleInputEvents(h, &num) && num > 0) {
	INPUT_RECORD rec;
	if (ReadConsoleInput(h, &rec, 1, &num)) {
	    if (rec.EventType == WINDOW_BUFFER_SIZE_EVENT) {
		rb_yield(Qnil);
	    }
	}
    }
    return io;
}
#else
#define console_input_events rb_f_notimplement
#define console_check_winsize_changed rb_f_notimplement
#endif

/*
 * call-seq:
 *   io.iflush
 *
 * Flushes input buffer in kernel.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_iflush(VALUE io)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    int fd = GetReadFD(io);
    if (tcflush(fd, TCIFLUSH)) sys_fail(io);
#endif

    return io;
}

/*
 * call-seq:
 *   io.oflush
 *
 * Flushes output buffer in kernel.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_oflush(VALUE io)
{
    int fd = GetWriteFD(io);
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    if (tcflush(fd, TCOFLUSH)) sys_fail(io);
#endif
    (void)fd;
    return io;
}

/*
 * call-seq:
 *   io.ioflush
 *
 * Flushes input and output buffers in kernel.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_ioflush(VALUE io)
{
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H
    int fd1 = GetReadFD(io);
    int fd2 = GetWriteFD(io);

    if (fd2 != -1 && fd1 != fd2) {
        if (tcflush(fd1, TCIFLUSH)) sys_fail(io);
        if (tcflush(fd2, TCOFLUSH)) sys_fail(io);
    }
    else {
        if (tcflush(fd1, TCIOFLUSH)) sys_fail(io);
    }
#endif

    return io;
}

/*
 * call-seq:
 *   io.beep
 *
 * Beeps on the output console.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_beep(VALUE io)
{
#ifdef _WIN32
    MessageBeep(0);
#else
    int fd = GetWriteFD(io);
    if (write(fd, "\a", 1) < 0) sys_fail(io);
#endif
    return io;
}

static int
mode_in_range(VALUE val, int high, const char *modename)
{
    int mode;
    if (NIL_P(val)) return 0;
    if (!RB_INTEGER_TYPE_P(val)) {
      wrong_value:
	rb_raise(rb_eArgError, "wrong %s mode: %"PRIsVALUE, modename, val);
    }
    if ((mode = NUM2INT(val)) < 0 || mode > high) {
	goto wrong_value;
    }
    return mode;
}

#if defined _WIN32
static void
constat_clear(HANDLE handle, WORD attr, DWORD len, COORD pos)
{
    DWORD written;

    FillConsoleOutputAttribute(handle, attr, len, pos, &written);
    FillConsoleOutputCharacterW(handle, L' ', len, pos, &written);
}

static VALUE
console_scroll(VALUE io, int line)
{
    HANDLE h;
    rb_console_size_t ws;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    if (line) {
	SMALL_RECT scroll;
	COORD destination;
	CHAR_INFO fill;
	scroll.Left = 0;
	scroll.Top = line > 0 ? line : 0;
	scroll.Right = winsize_col(&ws) - 1;
	scroll.Bottom = winsize_row(&ws) - 1 + (line < 0 ? line : 0);
	destination.X = 0;
	destination.Y = line < 0 ? -line : 0;
	fill.Char.UnicodeChar = L' ';
	fill.Attributes = ws.wAttributes;

	ScrollConsoleScreenBuffer(h, &scroll, NULL, destination, &fill);
    }
    return io;
}

#define GPERF_DOWNCASE 1
#define GPERF_CASE_STRCMP 1
#define gperf_case_strcmp STRCASECMP
#include "win32_vk.inc"

/*
 * call-seq:
 *   io.pressed?(key)   -> bool
 *
 * Returns +true+ if +key+ is pressed.  +key+ may be a virtual key
 * code or its name (String or Symbol) with out "VK_" prefix.
 *
 * This method is Windows only.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_key_pressed_p(VALUE io, VALUE k)
{
    int vk = -1;

    if (FIXNUM_P(k)) {
	vk = NUM2UINT(k);
    }
    else {
	const struct vktable *t;
	const char *kn;
	if (SYMBOL_P(k)) {
	    k = rb_sym2str(k);
	    kn = RSTRING_PTR(k);
	}
	else {
	    kn = StringValuePtr(k);
	}
	t = console_win32_vk(kn, RSTRING_LEN(k));
	if (!t || (vk = (short)t->vk) == -1) {
	    rb_raise(rb_eArgError, "unknown virtual key code: % "PRIsVALUE, k);
	}
    }
    return GetKeyState(vk) & 0x80 ? Qtrue : Qfalse;
}
#else
struct query_args {
    char qstr[6];
    unsigned char opt;
};

static int
direct_query(VALUE io, const struct query_args *query)
{
    if (RB_TYPE_P(io, T_FILE)) {
        VALUE wio = rb_io_get_write_io(io);
        VALUE s = rb_str_new_cstr(query->qstr);
        rb_io_write(wio, s);
        rb_io_flush(wio);
        return 1;
    }
    return 0;
}

static VALUE
read_vt_response(VALUE io, VALUE query)
{
    struct query_args *qargs = (struct query_args *)query;
    VALUE result, b;
    int opt = 0;
    int num = 0;
    if (qargs) {
	opt = qargs->opt;
	if (!direct_query(io, qargs)) return Qnil;
    }
    if (rb_io_getbyte(io) != INT2FIX(0x1b)) return Qnil;
    if (rb_io_getbyte(io) != INT2FIX('[')) return Qnil;
    result = rb_ary_new();
    while (!NIL_P(b = rb_io_getbyte(io))) {
	int c = NUM2UINT(b);
	if (c == ';') {
	    rb_ary_push(result, INT2NUM(num));
	    num = 0;
	}
	else if (ISDIGIT(c)) {
	    num = num * 10 + c - '0';
	}
	else if (opt && c == opt) {
	    opt = 0;
	}
	else {
	    char last = (char)c;
	    rb_ary_push(result, INT2NUM(num));
	    b = rb_str_new(&last, 1);
	    break;
	}
    }
    return rb_ary_push(result, b);
}

static VALUE
console_vt_response(int argc, VALUE *argv, VALUE io, const struct query_args *qargs)
{
    rawmode_arg_t opts, *optp = rawmode_opt(&argc, argv, 0, 1, &opts);
    VALUE query = (VALUE)qargs;
    VALUE ret = ttymode_with_io(io, read_vt_response, query, set_rawmode, optp);
    return ret;
}

static VALUE
console_scroll(VALUE io, int line)
{
    if (line) {
	VALUE s = rb_sprintf(CSI "%d%c", line < 0 ? -line : line,
			     line < 0 ? 'T' : 'S');
	rb_io_write(io, s);
    }
    return io;
}

# define console_key_pressed_p rb_f_notimplement
#endif

/*
 * call-seq:
 *   io.cursor -> [row, column]
 *
 * Returns the current cursor position as a two-element array of integers (row, column)
 *
 *   io.cursor # => [3, 5]
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_pos(VALUE io)
{
#ifdef _WIN32
    rb_console_size_t ws;
    int fd = GetWriteFD(io);
    if (!GetConsoleScreenBufferInfo((HANDLE)rb_w32_get_osfhandle(fd), &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    return rb_assoc_new(UINT2NUM(ws.dwCursorPosition.Y - ws.srWindow.Top), UINT2NUM(ws.dwCursorPosition.X));
#else
    static const struct query_args query = {"\033[6n", 0};
    VALUE resp = console_vt_response(0, 0, io, &query);
    VALUE row, column, term;
    unsigned int r, c;
    if (!RB_TYPE_P(resp, T_ARRAY) || RARRAY_LEN(resp) != 3) return Qnil;
    term = RARRAY_AREF(resp, 2);
    if (!RB_TYPE_P(term, T_STRING) || RSTRING_LEN(term) != 1) return Qnil;
    if (RSTRING_PTR(term)[0] != 'R') return Qnil;
    row = RARRAY_AREF(resp, 0);
    column = RARRAY_AREF(resp, 1);
    rb_ary_resize(resp, 2);
    r = NUM2UINT(row) - 1;
    c = NUM2UINT(column) - 1;
    RARRAY_ASET(resp, 0, INT2NUM(r));
    RARRAY_ASET(resp, 1, INT2NUM(c));
    return resp;
#endif
}

static VALUE
console_cursor_visibility(VALUE io, int visible)
{
#ifdef _WIN32
    HANDLE h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    CONSOLE_CURSOR_INFO info;

    if (!GetConsoleCursorInfo(h, &info)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    info.bVisible = visible;
    if (!SetConsoleCursorInfo(h, &info)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
#else
    rb_io_write(io, rb_str_new_cstr(visible ? CSI "?25h" : CSI "?25l"));
#endif
    return io;
}

/*
 * call-seq:
 *   io.hide_cursor             -> io
 *
 * Hides the cursor.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_hide_cursor(VALUE io)
{
    return console_cursor_visibility(io, 0);
}

/*
 * call-seq:
 *   io.show_cursor             -> io
 *
 * Shows the cursor.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_show_cursor(VALUE io)
{
    return console_cursor_visibility(io, 1);
}

/*
 * call-seq:
 *   io.goto(line, column)      -> io
 *
 * Set the cursor position at +line+ and +column+.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_goto(VALUE io, VALUE y, VALUE x)
{
#ifdef _WIN32
    HANDLE h;
    rb_console_size_t ws;
    COORD *pos = &ws.dwCursorPosition;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    pos->X = NUM2UINT(x);
    pos->Y = ws.srWindow.Top + NUM2UINT(y);
    if (!SetConsoleCursorPosition(h, *pos)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
#else
    rb_io_write(io, rb_sprintf(CSI "%d;%dH", NUM2UINT(y)+1, NUM2UINT(x)+1));
#endif
    return io;
}

static VALUE
console_move(VALUE io, int y, int x)
{
#ifdef _WIN32
    HANDLE h;
    rb_console_size_t ws;
    COORD *pos = &ws.dwCursorPosition;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    pos->X += x;
    pos->Y += y;
    if (!SetConsoleCursorPosition(h, *pos)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
#else
    if (x || y) {
	VALUE s = rb_str_new_cstr("");
	if (y) rb_str_catf(s, CSI "%d%c", y < 0 ? -y : y, y < 0 ? 'A' : 'B');
	if (x) rb_str_catf(s, CSI "%d%c", x < 0 ? -x : x, x < 0 ? 'D' : 'C');
	rb_io_write(io, s);
	rb_io_flush(io);
    }
#endif
    return io;
}

/*
 * call-seq:
 *   io.goto_column(column)     -> io
 *
 * Set the cursor position at +column+ in the same line of the current
 * position.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_goto_column(VALUE io, VALUE val)
{
#ifdef _WIN32
    HANDLE h;
    rb_console_size_t ws;
    COORD *pos = &ws.dwCursorPosition;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    pos->X = NUM2INT(val);
    if (!SetConsoleCursorPosition(h, *pos)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
#else
    rb_io_write(io, rb_sprintf(CSI "%dG", NUM2UINT(val)+1));
#endif
    return io;
}

/*
 * call-seq:
 *   io.erase_line(mode)        -> io
 *
 * Erases the line at the cursor corresponding to +mode+.
 * +mode+ may be either:
 * 0: after cursor
 * 1: before and cursor
 * 2: entire line
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_erase_line(VALUE io, VALUE val)
{
    int mode = mode_in_range(val, 2, "line erase");
#ifdef _WIN32
    HANDLE h;
    rb_console_size_t ws;
    COORD *pos = &ws.dwCursorPosition;
    DWORD w;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    w = winsize_col(&ws);
    switch (mode) {
      case 0:			/* after cursor */
	w -= pos->X;
	break;
      case 1:			/* before *and* cursor */
	w = pos->X + 1;
	pos->X = 0;
	break;
      case 2:			/* entire line */
	pos->X = 0;
	break;
    }
    constat_clear(h, ws.wAttributes, w, *pos);
    return io;
#else
    rb_io_write(io, rb_sprintf(CSI "%dK", mode));
#endif
    return io;
}

/*
 * call-seq:
 *   io.erase_screen(mode)      -> io
 *
 * Erases the screen at the cursor corresponding to +mode+.
 * +mode+ may be either:
 * 0: after cursor
 * 1: before and cursor
 * 2: entire screen
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_erase_screen(VALUE io, VALUE val)
{
    int mode = mode_in_range(val, 3, "screen erase");
#ifdef _WIN32
    HANDLE h;
    rb_console_size_t ws;
    COORD *pos = &ws.dwCursorPosition;
    DWORD w;

    h = (HANDLE)rb_w32_get_osfhandle(GetWriteFD(io));
    if (!GetConsoleScreenBufferInfo(h, &ws)) {
	rb_syserr_fail(LAST_ERROR, 0);
    }
    w = winsize_col(&ws);
    switch (mode) {
      case 0:	/* erase after cursor */
	w = (w * (ws.srWindow.Bottom - pos->Y + 1) - pos->X);
	break;
      case 1:	/* erase before *and* cursor */
	w = (w * (pos->Y - ws.srWindow.Top) + pos->X + 1);
	pos->X = 0;
	pos->Y = ws.srWindow.Top;
	break;
      case 2:	/* erase entire screen */
	w = (w * winsize_row(&ws));
	pos->X = 0;
	pos->Y = ws.srWindow.Top;
	break;
      case 3:	/* erase entire screen */
	w = (w * ws.dwSize.Y);
	pos->X = 0;
	pos->Y = 0;
	break;
    }
    constat_clear(h, ws.wAttributes, w, *pos);
#else
    rb_io_write(io, rb_sprintf(CSI "%dJ", mode));
#endif
    return io;
}

/*
 * call-seq:
 *   io.cursor = [line, column]         -> io
 *
 * Same as <tt>io.goto(line, column)</tt>
 *
 * See IO#goto.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_set(VALUE io, VALUE cpos)
{
    cpos = rb_convert_type(cpos, T_ARRAY, "Array", "to_ary");
    if (RARRAY_LEN(cpos) != 2) rb_raise(rb_eArgError, "expected 2D coordinate");
    return console_goto(io, RARRAY_AREF(cpos, 0), RARRAY_AREF(cpos, 1));
}

/*
 * call-seq:
 *   io.cursor_up(n)            -> io
 *
 * Moves the cursor up +n+ lines.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_up(VALUE io, VALUE val)
{
    return console_move(io, -NUM2INT(val), 0);
}

/*
 * call-seq:
 *   io.cursor_down(n)          -> io
 *
 * Moves the cursor down +n+ lines.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_down(VALUE io, VALUE val)
{
    return console_move(io, +NUM2INT(val), 0);
}

/*
 * call-seq:
 *   io.cursor_left(n)          -> io
 *
 * Moves the cursor left +n+ columns.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_left(VALUE io, VALUE val)
{
    return console_move(io, 0, -NUM2INT(val));
}

/*
 * call-seq:
 *   io.cursor_right(n)         -> io
 *
 * Moves the cursor right +n+ columns.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_cursor_right(VALUE io, VALUE val)
{
    return console_move(io, 0, +NUM2INT(val));
}

/*
 * call-seq:
 *   io.scroll_forward(n)       -> io
 *
 * Scrolls the entire scrolls forward +n+ lines.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_scroll_forward(VALUE io, VALUE val)
{
    return console_scroll(io, +NUM2INT(val));
}

/*
 * call-seq:
 *   io.scroll_backward(n)      -> io
 *
 * Scrolls the entire scrolls backward +n+ lines.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_scroll_backward(VALUE io, VALUE val)
{
    return console_scroll(io, -NUM2INT(val));
}

/*
 * call-seq:
 *   io.clear_screen            -> io
 *
 * Clears the entire screen and moves the cursor top-left corner.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_clear_screen(VALUE io)
{
    console_erase_screen(io, INT2FIX(2));
    console_goto(io, INT2FIX(0), INT2FIX(0));
    return io;
}

#ifndef HAVE_RB_IO_OPEN_DESCRIPTOR
static VALUE
io_open_descriptor_fallback(VALUE klass, int descriptor, int mode, VALUE path, VALUE timeout, void *encoding)
{
    VALUE arguments[2] = {
        (rb_update_max_fd(descriptor), INT2NUM(descriptor)),
        INT2FIX(mode),
    };

    VALUE self = rb_class_new_instance(2, arguments, klass);

    rb_io_t *fptr;
    GetOpenFile(self, fptr);
    fptr->pathv = path;
    fptr->mode |= mode;

    return self;
}
#define rb_io_open_descriptor io_open_descriptor_fallback
#endif

#ifndef HAVE_RB_IO_CLOSED_P
static VALUE
rb_io_closed_p(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;
    return fptr->fd == -1 ? Qtrue : Qfalse;
}
#endif

#if defined(RB_EXT_RACTOR_SAFE) && defined(HAVE_RB_RACTOR_LOCAL_STORAGE_VALUE_NEWKEY)
# define USE_RACTOR_STORAGE 1
#else
# define USE_RACTOR_STORAGE 0
#endif

#if USE_RACTOR_STORAGE
#include "ruby/ractor.h"
static rb_ractor_local_key_t key_console_dev;

static bool
console_dev_get(VALUE klass, VALUE *dev)
{
    return rb_ractor_local_storage_value_lookup(key_console_dev, dev);
}

static void
console_dev_set(VALUE klass, VALUE value)
{
    rb_ractor_local_storage_value_set(key_console_dev, value);
}

static void
console_dev_remove(VALUE klass)
{
    console_dev_set(klass, Qnil);
}

#else

static ID id_console;

static int
console_dev_get(VALUE klass, VALUE *dev)
{
    if (rb_const_defined(klass, id_console)) {
	*dev = rb_const_get(klass, id_console);
	return 1;
    }
    return 0;
}

static void
console_dev_set(VALUE klass, VALUE value)
{
    rb_const_set(klass, id_console, value);
}

static void
console_dev_remove(VALUE klass)
{
    rb_const_remove(klass, id_console);
}

#endif

/*
 * call-seq:
 *   IO.console      -> #<File:/dev/tty>
 *   IO.console(sym, *args)
 *
 * Returns an File instance opened console.
 *
 * If +sym+ is given, it will be sent to the opened console with
 * +args+ and the result will be returned instead of the console IO
 * itself.
 *
 * You must require 'io/console' to use this method.
 */
static VALUE
console_dev(int argc, VALUE *argv, VALUE klass)
{
    VALUE con = 0;
    VALUE sym = 0;

    if (argc) {
        Check_Type(sym = argv[0], T_SYMBOL);
    }

    /* Force the class to be File. */
    if (klass == rb_cIO) klass = rb_cFile;

    if (console_dev_get(klass, &con)) {
        if (!RB_TYPE_P(con, T_FILE) || RTEST(rb_io_closed_p(con))) {
	    console_dev_remove(klass);
            con = 0;
        }
    }

    if (sym) {
        if (sym == ID2SYM(id_close) && argc == 1) {
            if (con) {
                rb_io_close(con);
                console_dev_remove(klass);
                con = 0;
            }
            return Qnil;
        }
    }

    if (!con) {
#if defined HAVE_TERMIOS_H || defined HAVE_TERMIO_H || defined HAVE_SGTTY_H
# define CONSOLE_DEVICE "/dev/tty"
#elif defined _WIN32
# define CONSOLE_DEVICE "con$"
# define CONSOLE_DEVICE_FOR_READING "conin$"
# define CONSOLE_DEVICE_FOR_WRITING "conout$"
#endif
#ifndef CONSOLE_DEVICE_FOR_READING
# define CONSOLE_DEVICE_FOR_READING CONSOLE_DEVICE
#endif
#ifdef CONSOLE_DEVICE_FOR_WRITING
        VALUE out;
#endif
        int fd;
        VALUE path = rb_obj_freeze(rb_str_new2(CONSOLE_DEVICE));

#ifdef CONSOLE_DEVICE_FOR_WRITING
        fd = rb_cloexec_open(CONSOLE_DEVICE_FOR_WRITING, O_RDWR, 0);
        if (fd < 0) return Qnil;
        out = rb_io_open_descriptor(klass, fd, FMODE_WRITABLE | FMODE_SYNC, path, Qnil, NULL);
#endif
        fd = rb_cloexec_open(CONSOLE_DEVICE_FOR_READING, O_RDWR, 0);
        if (fd < 0) {
#ifdef CONSOLE_DEVICE_FOR_WRITING
            rb_io_close(out);
#endif
            return Qnil;
        }

        con = rb_io_open_descriptor(klass, fd, FMODE_READWRITE | FMODE_SYNC, path, Qnil, NULL);
#ifdef CONSOLE_DEVICE_FOR_WRITING
        rb_io_set_write_io(con, out);
#endif
        console_dev_set(klass, con);
    }

    if (sym) {
        return rb_f_send(argc, argv, con);
    }

    return con;
}

/*
 * call-seq:
 *   io.getch(min: nil, time: nil, intr: nil) -> char or nil
 *
 * See IO#getch.
 */
static VALUE
io_getch(int argc, VALUE *argv, VALUE io)
{
    return rb_funcallv(io, id_getc, argc, argv);
}

static VALUE
puts_call(VALUE io)
{
    return rb_io_write(io, rb_default_rs);
}

static VALUE
funcall_with_rs(VALUE obj, ID mid)
{
    const VALUE rs = rb_default_rs; /* rvalue in TruffleRuby */
    return rb_funcallv(obj, mid, 1, &rs);
}

static VALUE
gets_call(VALUE io)
{
    return funcall_with_rs(io, id_gets);
}

static VALUE
getpass_call(VALUE io)
{
    return ttymode(io, rb_io_gets, io, set_noecho, NULL);
}

static void
prompt(int argc, VALUE *argv, VALUE io)
{
    if (argc > 0 && !NIL_P(argv[0])) {
	VALUE str = argv[0];
	StringValueCStr(str);
	rb_io_write(io, str);
    }
}

static VALUE
str_chomp(VALUE str)
{
    if (!NIL_P(str)) {
	funcall_with_rs(str, id_chomp_bang);
    }
    return str;
}

/*
 * call-seq:
 *   io.getpass(prompt=nil)       -> string
 *
 * Reads and returns a line without echo back.
 * Prints +prompt+ unless it is +nil+.
 *
 * The newline character that terminates the
 * read line is removed from the returned string,
 * see String#chomp!.
 *
 * You must require 'io/console' to use this method.
 *
 *    require 'io/console'
 *    IO::console.getpass("Enter password:")
 *    Enter password:
 *    # => "mypassword"
 *
 */
static VALUE
console_getpass(int argc, VALUE *argv, VALUE io)
{
    VALUE str, wio;

    rb_check_arity(argc, 0, 1);
    wio = rb_io_get_write_io(io);
    if (wio == io && io == rb_stdin) wio = rb_stderr;
    prompt(argc, argv, wio);
    rb_io_flush(wio);
    str = rb_ensure(getpass_call, io, puts_call, wio);
    return str_chomp(str);
}

/*
 * call-seq:
 *   io.getpass(prompt=nil)       -> string
 *
 * See IO#getpass.
 */
static VALUE
io_getpass(int argc, VALUE *argv, VALUE io)
{
    VALUE str;

    rb_check_arity(argc, 0, 1);
    prompt(argc, argv, io);
    rb_check_funcall(io, id_flush, 0, 0);
    str = rb_ensure(gets_call, io, puts_call, io);
    return str_chomp(str);
}

#if defined(_WIN32) || defined(HAVE_TTYNAME_R) || defined(HAVE_TTYNAME)
/*
 * call-seq:
 *   io.ttyname       -> string or nil
 *
 * Returns name of associated terminal (tty) if +io+ is a tty.
 * Returns +nil+ otherwise.
 */
static VALUE
console_ttyname(VALUE io)
{
    int fd = rb_io_descriptor(io);
    if (!isatty(fd)) return Qnil;
# if defined _WIN32
    return rb_usascii_str_new_lit("con");
# elif defined HAVE_TTYNAME_R
    {
	char termname[1024], *tn = termname;
	size_t size = sizeof(termname);
	int e;
	if ((e = ttyname_r(fd, tn, size)) == 0)
	    return rb_interned_str_cstr(tn);
	if (e == ERANGE) {
	    VALUE s = rb_str_new(0, size);
	    while (1) {
		tn = RSTRING_PTR(s);
		size = rb_str_capacity(s);
		if ((e = ttyname_r(fd, tn, size)) == 0) {
		    return rb_str_to_interned_str(rb_str_resize(s, strlen(tn)));
		}
		if (e != ERANGE) break;
		if ((size *= 2) >= INT_MAX/2) break;
		rb_str_resize(s, size);
	    }
	}
	rb_syserr_fail_str(e, rb_sprintf("ttyname_r(%d)", fd));
	UNREACHABLE_RETURN(Qnil);
    }
# elif defined HAVE_TTYNAME
    {
	const char *tn = ttyname(fd);
	if (!tn) {
	    int e = errno;
	    rb_syserr_fail_str(e, rb_sprintf("ttyname(%d)", fd));
	}
	return rb_interned_str_cstr(tn);
    }
# else
#   error No ttyname function
# endif
}
#else
# define console_ttyname rb_f_notimplement
#endif

typedef enum {
    platform_default,
#if defined _WIN32
    platform_cygwin,
    platform_msys,
#endif
    platform_any,

    platform_default_bit = 1U << platform_default,
#if defined _WIN32
    platform_cygwin_bit = 1U << platform_cygwin,
    platform_msys_bit = 1U << platform_msys,
#endif
    platform_any_bit = (1U << platform_any) - 1 /* all bits */
} console_platform_t;

/*
 * call-seq:
 *   io.tty?([mode, ...])	-> true or false
 *
 * Returns +true+ if the stream is associated with a terminal device (tty),
 * +false+ otherwise.
 *
 * If one or more +type+s are given, returns +true+ if the stream is
 * associated with any of the specified tty types.
 *
 * - +nil+ : Returns the result of the default tty check, as if no type were
 *   given.  It can be combined with other types.
 * - +:any+ : Returns +true+ for any known kind of tty, including the
 *   default tty.
 * - +:cygwin+ : Returns +true+ for cygwin tty, on Windows.
 * - +:msys+ : Returns +true+ for msys2 tty, on Windows.
 */
static VALUE
console_platform_tty_p(int argc, VALUE *argv, VALUE io)
{
    VALUE ret = Qfalse;
    int mode = 0;

    if (argc > 0) {
	int i;
	for (i = 0; i < argc; ++i) {
	    VALUE m = argv[i];
	    if (NIL_P(m)) {
		mode |= platform_default_bit;
		continue;
	    }
	    Check_Type(m, T_SYMBOL);
	    if (m == ID2SYM(rb_intern("any"))) {
		mode |= platform_any_bit;
	    }
#if defined _WIN32
	    else if (m == ID2SYM(rb_intern("cygwin"))) {
		mode |= platform_cygwin_bit;
	    }
	    else if (m == ID2SYM(rb_intern("msys"))) {
		mode |= platform_msys_bit;
	    }
#endif
	    else {
		rb_raise(rb_eArgError, "unknown tty type: %+" PRIsVALUE, m);
	    }
	}
    }
    if ((mode & platform_default_bit) || (mode == 0)) {
	ret = rb_call_super(0, 0);
    }
    if ((mode & ~platform_default_bit) && !RTEST(ret)) {
#if defined _WIN32
	if (mode & (platform_cygwin_bit | platform_msys_bit)) {
	    struct {
		FILE_NAME_INFO info;
		WCHAR rest[MAX_PATH];
	    } buffer;

	    HANDLE h = (HANDLE)rb_w32_get_osfhandle(GetReadFD(io));
	    if ((GetFileType(h) == FILE_TYPE_PIPE) &&
		GetFileInformationByHandleEx(h, FileNameInfo, &buffer, sizeof(buffer))) {
		WCHAR *const name = buffer.info.FileName;
		DWORD len = buffer.info.FileNameLength / sizeof(WCHAR);
		name[len] = L'\0';
# define tty_pipe_p(type) \
		(memcmp(name, L"\\" #type "-", sizeof(L"\\" #type)) == 0 && \
		 wcsstr(&name[rb_strlen_lit("\\" #type "-")], L"-pty") != NULL)
		if (!ret && (mode & platform_cygwin_bit)) {
		    ret = tty_pipe_p(cygwin);
		}
		if (!ret && (mode & platform_msys_bit)) {
		    ret = tty_pipe_p(msys);
		}
	    }
	}
#endif
    }
    return ret;
}

/*
 * IO console methods
 */
void
Init_console(void)
{
#if USE_RACTOR_STORAGE
    RB_EXT_RACTOR_SAFE(true);
#endif

#undef rb_intern
#if USE_RACTOR_STORAGE
    key_console_dev = rb_ractor_local_storage_value_newkey();
#else
    id_console = rb_intern("console");
#endif
    id_getc = rb_intern("getc");
    id_gets = rb_intern("gets");
    id_flush = rb_intern("flush");
    id_chomp_bang = rb_intern("chomp!");
    id_close = rb_intern("close");
    id_timeout = rb_intern("timeout");
#define init_rawmode_opt_id(name) \
    rawmode_opt_ids[kwd_##name] = rb_intern(#name)
    init_rawmode_opt_id(min);
    init_rawmode_opt_id(time);
    init_rawmode_opt_id(intr);
#ifndef HAVE_RB_F_SEND
    id___send__ = rb_intern("__send__");
#endif
    InitVM(console);
}

void
InitVM_console(void)
{
    /* :nodoc: */
    VALUE mConsole = rb_define_module_under(rb_cIO, "Console");
#ifdef _WIN32
    /* :nodoc: */
    VALUE mWindows = rb_define_module_under(mConsole, "Windows");
#define define_win32_const(name) rb_define_const(mWindows, #name, UINT2NUM(name))
    EACH_VK(define_win32_const,;);
    define_win32_const(RIGHT_ALT_PRESSED);
    define_win32_const(LEFT_ALT_PRESSED);
    define_win32_const(RIGHT_CTRL_PRESSED);
    define_win32_const(LEFT_CTRL_PRESSED);
    define_win32_const(SHIFT_PRESSED);
    define_win32_const(NUMLOCK_ON);
    define_win32_const(SCROLLLOCK_ON);
    define_win32_const(CAPSLOCK_ON);
    define_win32_const(ENHANCED_KEY);
#undef define_win32_const
#endif

    rb_define_method(rb_cIO, "raw", console_raw, -1);
    rb_define_method(rb_cIO, "raw!", console_set_raw, -1);
    rb_define_method(rb_cIO, "cooked", console_cooked, 0);
    rb_define_method(rb_cIO, "cooked!", console_set_cooked, 0);
    rb_define_method(rb_cIO, "getch", console_getch, -1);
    rb_define_method(rb_cIO, "input_pending?", console_input_pending_p, 0);
    rb_define_method(rb_cIO, "echo=", console_set_echo, 1);
    rb_define_method(rb_cIO, "echo?", console_echo_p, 0);
    rb_define_method(rb_cIO, "console_mode", console_conmode_get, 0);
    rb_define_method(rb_cIO, "console_mode=", console_conmode_set, 1);
    rb_define_method(rb_cIO, "noecho", console_noecho, 0);
    rb_define_method(rb_cIO, "winsize", console_winsize, 0);
    rb_define_method(rb_cIO, "winsize=", console_set_winsize, 1);
    rb_define_method(rb_cIO, "iflush", console_iflush, 0);
    rb_define_method(rb_cIO, "oflush", console_oflush, 0);
    rb_define_method(rb_cIO, "ioflush", console_ioflush, 0);
    rb_define_method(rb_cIO, "beep", console_beep, 0);
    rb_define_method(rb_cIO, "goto", console_goto, 2);
    rb_define_method(rb_cIO, "cursor", console_cursor_pos, 0);
    rb_define_method(rb_cIO, "cursor=", console_cursor_set, 1);
    rb_define_method(rb_cIO, "hide_cursor", console_hide_cursor, 0);
    rb_define_method(rb_cIO, "show_cursor", console_show_cursor, 0);
    rb_define_method(rb_cIO, "cursor_up", console_cursor_up, 1);
    rb_define_method(rb_cIO, "cursor_down", console_cursor_down, 1);
    rb_define_method(rb_cIO, "cursor_left", console_cursor_left, 1);
    rb_define_method(rb_cIO, "cursor_right", console_cursor_right, 1);
    rb_define_method(rb_cIO, "goto_column", console_goto_column, 1);
    rb_define_method(rb_cIO, "erase_line", console_erase_line, 1);
    rb_define_method(rb_cIO, "erase_screen", console_erase_screen, 1);
    rb_define_method(rb_cIO, "scroll_forward", console_scroll_forward, 1);
    rb_define_method(rb_cIO, "scroll_backward", console_scroll_backward, 1);
    rb_define_method(rb_cIO, "clear_screen", console_clear_screen, 0);
    rb_define_method(rb_cIO, "pressed?", console_key_pressed_p, 1);
    rb_define_method(rb_cIO, "console_input_events", console_input_events, -1);
    rb_define_method(rb_cIO, "check_winsize_changed", console_check_winsize_changed, 0);
    rb_define_method(rb_cIO, "getpass", console_getpass, -1);
    rb_define_method(rb_cIO, "ttyname", console_ttyname, 0);
    {
	/* :nodoc: */
	VALUE platform = rb_define_module_under(rb_cIO, "platform_tty");
	{
	    VALUE rb_cIO = platform;
	    rb_define_method(rb_cIO, "tty?", console_platform_tty_p, -1);
	    rb_define_method(rb_cIO, "isatty", console_platform_tty_p, -1);
	}
#ifdef HAVE_RB_PREPEND_MODULE
	rb_prepend_module(rb_cIO, platform);
#else
	rb_funcall(rb_cIO, rb_intern_const("prepend"), 1, platform);
#endif
    }
    rb_define_singleton_method(rb_cIO, "console", console_dev, -1);
    {
	/* :nodoc: */
	VALUE mReadable = rb_define_module_under(rb_cIO, "generic_readable");
	rb_define_method(mReadable, "getch", io_getch, -1);
	rb_define_method(mReadable, "getpass", io_getpass, -1);
    }
    {
	/* :nodoc: */
	VALUE version = rb_obj_freeze(rb_str_new_cstr(IO_CONSOLE_VERSION));
	ID cid, deprecate_constant = rb_intern_const("deprecate_constant");
	rb_define_const(mConsole, "VERSION", version);
	/* :nodoc: */
	cConmode = rb_define_class_under(mConsole, "Mode", rb_cObject);

	/* old internal names; do not use */
	cid = rb_intern_const("ConsoleMode");
	rb_const_set(rb_cIO, cid, cConmode);
	rb_funcall(rb_cIO, deprecate_constant, 1, ID2SYM(cid));
	cid = rb_intern_const("VERSION");
	rb_const_set(cConmode, cid, version);
	rb_funcall(cConmode, deprecate_constant, 1, ID2SYM(cid));

        rb_define_alloc_func(cConmode, conmode_alloc);
        rb_undef_method(cConmode, "initialize");
        rb_define_method(cConmode, "initialize_copy", conmode_init_copy, 1);
        rb_define_method(cConmode, "echo=", conmode_set_echo, 1);
        rb_define_method(cConmode, "raw!", conmode_set_raw, -1);
        rb_define_method(cConmode, "raw", conmode_raw_new, -1);
#ifdef _WIN32
        rb_define_method(cConmode, "virtual_terminal_processing?", conmode_virtual_terminal_processing_p, 0);
        rb_define_method(cConmode, "virtual_terminal_processing=", conmode_set_virtual_terminal_processing, 1);
        rb_define_method(cConmode, "wrap_at_eol_output?", conmode_wrap_at_eol_output_p, 0);
        rb_define_method(cConmode, "wrap_at_eol_output=", conmode_set_wrap_at_eol_output, 1);
#endif
    }
}
