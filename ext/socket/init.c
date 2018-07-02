/************************************************

  init.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

VALUE rb_cBasicSocket;
VALUE rb_cIPSocket;
VALUE rb_cTCPSocket;
VALUE rb_cTCPServer;
VALUE rb_cUDPSocket;
#ifdef AF_UNIX
VALUE rb_cUNIXSocket;
VALUE rb_cUNIXServer;
#endif
VALUE rb_cSocket;
VALUE rb_cAddrinfo;

VALUE rb_eSocket;

#ifdef SOCKS
VALUE rb_cSOCKSSocket;
#endif

int rsock_do_not_reverse_lookup = 1;
static VALUE sym_wait_readable;

void
rsock_raise_socket_error(const char *reason, int error)
{
#ifdef EAI_SYSTEM
    int e;
    if (error == EAI_SYSTEM && (e = errno) != 0)
	rb_syserr_fail(e, reason);
#endif
    rb_raise(rb_eSocket, "%s: %s", reason, gai_strerror(error));
}

#ifdef _WIN32
#define is_socket(fd) rb_w32_is_socket(fd)
#else
static int
is_socket(int fd)
{
    struct stat sbuf;

    if (fstat(fd, &sbuf) < 0)
        rb_sys_fail("fstat(2)");
    return S_ISSOCK(sbuf.st_mode);
}
#endif

#if defined __APPLE__
# define do_write_retry(code) do {ret = code;} while (ret == -1 && errno == EPROTOTYPE)
#else
# define do_write_retry(code) ret = code
#endif

VALUE
rsock_init_sock(VALUE sock, int fd)
{
    rb_io_t *fp;

    if (!is_socket(fd) || rb_reserved_fd_p(fd)) {
	rb_syserr_fail(EBADF, "not a socket file descriptor");
    }

    rb_update_max_fd(fd);
    MakeOpenFile(sock, fp);
    fp->fd = fd;
    fp->mode = FMODE_READWRITE|FMODE_DUPLEX;
    rb_io_ascii8bit_binmode(sock);
    if (rsock_do_not_reverse_lookup) {
	fp->mode |= FMODE_NOREVLOOKUP;
    }
    rb_io_synchronized(fp);

    return sock;
}

VALUE
rsock_sendto_blocking(void *data)
{
    struct rsock_send_arg *arg = data;
    VALUE mesg = arg->mesg;
    ssize_t ret;
    do_write_retry(sendto(arg->fd, RSTRING_PTR(mesg), RSTRING_LEN(mesg),
			  arg->flags, arg->to, arg->tolen));
    return (VALUE)ret;
}

VALUE
rsock_send_blocking(void *data)
{
    struct rsock_send_arg *arg = data;
    VALUE mesg = arg->mesg;
    ssize_t ret;
    do_write_retry(send(arg->fd, RSTRING_PTR(mesg), RSTRING_LEN(mesg),
			arg->flags));
    return (VALUE)ret;
}

struct recvfrom_arg {
    int fd, flags;
    VALUE str;
    socklen_t alen;
    union_sockaddr buf;
};

static VALUE
recvfrom_blocking(void *data)
{
    struct recvfrom_arg *arg = data;
    socklen_t len0 = arg->alen;
    ssize_t ret;
    ret = recvfrom(arg->fd, RSTRING_PTR(arg->str), RSTRING_LEN(arg->str),
                   arg->flags, &arg->buf.addr, &arg->alen);
    if (ret != -1 && len0 < arg->alen)
        arg->alen = len0;
    return (VALUE)ret;
}

static VALUE
rsock_strbuf(VALUE str, long buflen)
{
    long len;

    if (NIL_P(str)) return rb_tainted_str_new(0, buflen);

    StringValue(str);
    len = RSTRING_LEN(str);
    if (len >= buflen) {
	rb_str_modify(str);
    } else {
	rb_str_modify_expand(str, buflen - len);
    }
    rb_str_set_len(str, buflen);
    return str;
}

static VALUE
recvfrom_locktmp(VALUE v)
{
    struct recvfrom_arg *arg = (struct recvfrom_arg *)v;

    return rb_thread_io_blocking_region(recvfrom_blocking, arg, arg->fd);
}

VALUE
rsock_s_recvfrom(VALUE sock, int argc, VALUE *argv, enum sock_recv_type from)
{
    rb_io_t *fptr;
    VALUE str;
    struct recvfrom_arg arg;
    VALUE len, flg;
    long buflen;
    long slen;

    rb_scan_args(argc, argv, "12", &len, &flg, &str);

    if (flg == Qnil) arg.flags = 0;
    else             arg.flags = NUM2INT(flg);
    buflen = NUM2INT(len);
    str = rsock_strbuf(str, buflen);

    GetOpenFile(sock, fptr);
    if (rb_io_read_pending(fptr)) {
	rb_raise(rb_eIOError, "recv for buffered IO");
    }
    arg.fd = fptr->fd;
    arg.alen = (socklen_t)sizeof(arg.buf);
    arg.str = str;

    while (rb_io_check_closed(fptr),
	   rsock_maybe_wait_fd(arg.fd),
	   (slen = (long)rb_str_locktmp_ensure(str, recvfrom_locktmp,
	                                       (VALUE)&arg)) < 0) {
        if (!rb_io_wait_readable(fptr->fd)) {
            rb_sys_fail("recvfrom(2)");
        }
    }

    if (slen != RSTRING_LEN(str)) {
	rb_str_set_len(str, slen);
    }
    rb_obj_taint(str);
    switch (from) {
      case RECV_RECV:
	return str;
      case RECV_IP:
#if 0
	if (arg.alen != sizeof(struct sockaddr_in)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
#endif
	if (arg.alen && arg.alen != sizeof(arg.buf)) /* OSX doesn't return a from result for connection-oriented sockets */
	    return rb_assoc_new(str, rsock_ipaddr(&arg.buf.addr, arg.alen, fptr->mode & FMODE_NOREVLOOKUP));
	else
	    return rb_assoc_new(str, Qnil);

#ifdef HAVE_SYS_UN_H
      case RECV_UNIX:
        return rb_assoc_new(str, rsock_unixaddr(&arg.buf.un, arg.alen));
#endif
      case RECV_SOCKET:
	return rb_assoc_new(str, rsock_io_socket_addrinfo(sock, &arg.buf.addr, arg.alen));
      default:
	rb_bug("rsock_s_recvfrom called with bad value");
    }
}

VALUE
rsock_s_recvfrom_nonblock(VALUE sock, VALUE len, VALUE flg, VALUE str,
			  VALUE ex, enum sock_recv_type from)
{
    rb_io_t *fptr;
    union_sockaddr buf;
    socklen_t alen = (socklen_t)sizeof buf;
    long buflen;
    long slen;
    int fd, flags;
    VALUE addr = Qnil;
    socklen_t len0;

    flags = NUM2INT(flg);
    buflen = NUM2INT(len);
    str = rsock_strbuf(str, buflen);

#ifdef MSG_DONTWAIT
    /* MSG_DONTWAIT avoids the race condition between fcntl and recvfrom.
       It is not portable, though. */
    flags |= MSG_DONTWAIT;
#endif

    GetOpenFile(sock, fptr);
    if (rb_io_read_pending(fptr)) {
	rb_raise(rb_eIOError, "recvfrom for buffered IO");
    }
    fd = fptr->fd;

    rb_io_check_closed(fptr);

    if (!MSG_DONTWAIT_RELIABLE)
	rb_io_set_nonblock(fptr);

    len0 = alen;
    slen = recvfrom(fd, RSTRING_PTR(str), buflen, flags, &buf.addr, &alen);
    if (slen != -1 && len0 < alen)
        alen = len0;

    if (slen < 0) {
	int e = errno;
	switch (e) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
            if (ex == Qfalse)
		return sym_wait_readable;
            rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE, e, "recvfrom(2) would block");
	}
	rb_syserr_fail(e, "recvfrom(2)");
    }
    if (slen != RSTRING_LEN(str)) {
	rb_str_set_len(str, slen);
    }
    rb_obj_taint(str);
    switch (from) {
      case RECV_RECV:
        return str;

      case RECV_IP:
        if (alen && alen != sizeof(buf)) /* connection-oriented socket may not return a from result */
            addr = rsock_ipaddr(&buf.addr, alen, fptr->mode & FMODE_NOREVLOOKUP);
        break;

      case RECV_SOCKET:
        addr = rsock_io_socket_addrinfo(sock, &buf.addr, alen);
        break;

      default:
        rb_bug("rsock_s_recvfrom_nonblock called with bad value");
    }
    return rb_assoc_new(str, addr);
}

#if MSG_DONTWAIT_RELIABLE
static VALUE sym_wait_writable;

/* copied from io.c :< */
static long
read_buffered_data(char *ptr, long len, rb_io_t *fptr)
{
    int n = fptr->rbuf.len;

    if (n <= 0) return 0;
    if (n > len) n = (int)len;
    MEMMOVE(ptr, fptr->rbuf.ptr+fptr->rbuf.off, char, n);
    fptr->rbuf.off += n;
    fptr->rbuf.len -= n;
    return n;
}

/* :nodoc: */
VALUE
rsock_read_nonblock(VALUE sock, VALUE length, VALUE buf, VALUE ex)
{
    rb_io_t *fptr;
    long n;
    long len = NUM2LONG(length);
    VALUE str = rsock_strbuf(buf, len);
    char *ptr;

    OBJ_TAINT(str);
    GetOpenFile(sock, fptr);

    if (len == 0) {
	return str;
    }

    ptr = RSTRING_PTR(str);
    n = read_buffered_data(ptr, len, fptr);
    if (n <= 0) {
	n = (long)recv(fptr->fd, ptr, len, MSG_DONTWAIT);
	if (n < 0) {
	    int e = errno;
	    if ((e == EWOULDBLOCK || e == EAGAIN)) {
		if (ex == Qfalse) return sym_wait_readable;
		rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE,
					 e, "read would block");
	    }
	    rb_syserr_fail_path(e, fptr->pathv);
	}
    }
    if (len != n) {
	rb_str_modify(str);
	rb_str_set_len(str, n);
	if (str != buf) {
	    rb_str_resize(str, n);
	}
    }
    if (n == 0) {
	if (ex == Qfalse) return Qnil;
	rb_eof_error();
    }

    return str;
}

/* :nodoc: */
VALUE
rsock_write_nonblock(VALUE sock, VALUE str, VALUE ex)
{
    rb_io_t *fptr;
    long n;

    if (!RB_TYPE_P(str, T_STRING))
	str = rb_obj_as_string(str);

    sock = rb_io_get_write_io(sock);
    GetOpenFile(sock, fptr);
    rb_io_check_writable(fptr);

    /*
     * As with IO#write_nonblock, we may block if somebody is relying on
     * buffered I/O; but nobody actually hits this because pipes and sockets
     * are not userspace-buffered in Ruby by default.
     */
    if (fptr->wbuf.len > 0) {
	rb_io_flush(sock);
    }

#ifdef __APPLE__
  again:
#endif
    n = (long)send(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str), MSG_DONTWAIT);
    if (n < 0) {
	int e = errno;

#ifdef __APPLE__
	if (e == EPROTOTYPE) {
	    goto again;
	}
#endif
	if (e == EWOULDBLOCK || e == EAGAIN) {
	    if (ex == Qfalse) return sym_wait_writable;
	    rb_readwrite_syserr_fail(RB_IO_WAIT_WRITABLE, e,
				    "write would block");
	}
	rb_syserr_fail_path(e, fptr->pathv);
    }

    return LONG2FIX(n);
}
#endif /* MSG_DONTWAIT_RELIABLE */

/* returns true if SOCK_CLOEXEC is supported */
int rsock_detect_cloexec(int fd)
{
#ifdef SOCK_CLOEXEC
    int flags = fcntl(fd, F_GETFD);

    if (flags == -1)
	rb_bug("rsock_detect_cloexec: fcntl(%d, F_GETFD) failed: %s", fd, strerror(errno));

    if (flags & FD_CLOEXEC)
	return 1;
#endif
    return 0;
}

#ifdef SOCK_CLOEXEC
static int
rsock_socket0(int domain, int type, int proto)
{
    int ret;
    static int cloexec_state = -1; /* <0: unknown, 0: ignored, >0: working */

    if (cloexec_state > 0) { /* common path, if SOCK_CLOEXEC is defined */
        ret = socket(domain, type|SOCK_CLOEXEC, proto);
        if (ret >= 0) {
            if (ret <= 2)
                goto fix_cloexec;
            goto update_max_fd;
        }
    }
    else if (cloexec_state < 0) { /* usually runs once only for detection */
        ret = socket(domain, type|SOCK_CLOEXEC, proto);
        if (ret >= 0) {
            cloexec_state = rsock_detect_cloexec(ret);
            if (cloexec_state == 0 || ret <= 2)
                goto fix_cloexec;
            goto update_max_fd;
        }
        else if (ret == -1 && errno == EINVAL) {
            /* SOCK_CLOEXEC is available since Linux 2.6.27.  Linux 2.6.18 fails with EINVAL */
            ret = socket(domain, type, proto);
            if (ret != -1) {
                cloexec_state = 0;
                /* fall through to fix_cloexec */
            }
        }
    }
    else { /* cloexec_state == 0 */
        ret = socket(domain, type, proto);
    }
    if (ret == -1)
        return -1;
fix_cloexec:
    rb_maygvl_fd_fix_cloexec(ret);
update_max_fd:
    rb_update_max_fd(ret);

    return ret;
}
#else /* !SOCK_CLOEXEC */
static int
rsock_socket0(int domain, int type, int proto)
{
    int ret = socket(domain, type, proto);

    if (ret == -1)
        return -1;
    rb_fd_fix_cloexec(ret);

    return ret;
}
#endif /* !SOCK_CLOEXEC */

int
rsock_socket(int domain, int type, int proto)
{
    int fd;

    fd = rsock_socket0(domain, type, proto);
    if (fd < 0) {
       if (rb_gc_for_fd(errno)) {
           fd = rsock_socket0(domain, type, proto);
       }
    }
    if (0 <= fd)
        rb_update_max_fd(fd);
    return fd;
}

/* emulate blocking connect behavior on EINTR or non-blocking socket */
static int
wait_connectable(int fd)
{
    int sockerr, revents;
    socklen_t sockerrlen;

    /* only to clear pending error */
    sockerrlen = (socklen_t)sizeof(sockerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&sockerr, &sockerrlen) < 0)
        return -1;

    /*
     * Stevens book says, successful finish turn on RB_WAITFD_OUT and
     * failure finish turn on both RB_WAITFD_IN and RB_WAITFD_OUT.
     * So it's enough to wait only RB_WAITFD_OUT and check the pending error
     * by getsockopt().
     *
     * Note: rb_wait_for_single_fd already retries on EINTR/ERESTART
     */
    revents = rb_wait_for_single_fd(fd, RB_WAITFD_IN|RB_WAITFD_OUT, NULL);

    if (revents < 0)
        return -1;

    sockerrlen = (socklen_t)sizeof(sockerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&sockerr, &sockerrlen) < 0)
        return -1;

    switch (sockerr) {
      case 0:
      /*
       * be defensive in case some platforms set SO_ERROR on the original,
       * interrupted connect()
       */
      case EINTR:
#ifdef ERESTART
      case ERESTART:
#endif
      case EAGAIN:
#ifdef EINPROGRESS
      case EINPROGRESS:
#endif
#ifdef EALREADY
      case EALREADY:
#endif
#ifdef EISCONN
      case EISCONN:
#endif
	return 0; /* success */
      default:
        /* likely (but not limited to): ECONNREFUSED, ETIMEDOUT, EHOSTUNREACH */
        errno = sockerr;
        return -1;
    }

    return 0;
}

struct connect_arg {
    int fd;
    socklen_t len;
    const struct sockaddr *sockaddr;
};

static VALUE
connect_blocking(void *data)
{
    struct connect_arg *arg = data;
    return (VALUE)connect(arg->fd, arg->sockaddr, arg->len);
}

#if defined(SOCKS) && !defined(SOCKS5)
static VALUE
socks_connect_blocking(void *data)
{
    struct connect_arg *arg = data;
    return (VALUE)Rconnect(arg->fd, arg->sockaddr, arg->len);
}
#endif

int
rsock_connect(int fd, const struct sockaddr *sockaddr, int len, int socks)
{
    int status;
    rb_blocking_function_t *func = connect_blocking;
    struct connect_arg arg;

    arg.fd = fd;
    arg.sockaddr = sockaddr;
    arg.len = len;
#if defined(SOCKS) && !defined(SOCKS5)
    if (socks) func = socks_connect_blocking;
#endif
    status = (int)BLOCKING_REGION_FD(func, &arg);

    if (status < 0) {
        switch (errno) {
          case EINTR:
#ifdef ERESTART
          case ERESTART:
#endif
          case EAGAIN:
#ifdef EINPROGRESS
          case EINPROGRESS:
#endif
            return wait_connectable(fd);
        }
    }
    return status;
}

static void
make_fd_nonblock(int fd)
{
    int flags;
#ifdef F_GETFL
    flags = fcntl(fd, F_GETFL);
    if (flags == -1) {
        rb_sys_fail("fnctl(2)");
    }
#else
    flags = 0;
#endif
    flags |= O_NONBLOCK;
    if (fcntl(fd, F_SETFL, flags) == -1) {
        rb_sys_fail("fnctl(2)");
    }
}

static int
cloexec_accept(int socket, struct sockaddr *address, socklen_t *address_len,
	       int nonblock)
{
    int ret;
    socklen_t len0 = 0;
#ifdef HAVE_ACCEPT4
    static int try_accept4 = 1;
#endif
    if (address_len) len0 = *address_len;
#ifdef HAVE_ACCEPT4
    if (try_accept4) {
        int flags = 0;
#ifdef SOCK_CLOEXEC
        flags |= SOCK_CLOEXEC;
#endif
#ifdef SOCK_NONBLOCK
        if (nonblock) {
            flags |= SOCK_NONBLOCK;
        }
#endif
        ret = accept4(socket, address, address_len, flags);
        /* accept4 is available since Linux 2.6.28, glibc 2.10. */
        if (ret != -1) {
            if (ret <= 2)
                rb_maygvl_fd_fix_cloexec(ret);
#ifndef SOCK_NONBLOCK
            if (nonblock) {
                make_fd_nonblock(ret);
            }
#endif
            if (address_len && len0 < *address_len) *address_len = len0;
            return ret;
        }
        if (errno != ENOSYS) {
            return -1;
        }
        try_accept4 = 0;
    }
#endif
    ret = accept(socket, address, address_len);
    if (ret == -1) return -1;
    if (address_len && len0 < *address_len) *address_len = len0;
    rb_maygvl_fd_fix_cloexec(ret);
    if (nonblock) {
        make_fd_nonblock(ret);
    }
    return ret;
}

VALUE
rsock_s_accept_nonblock(VALUE klass, VALUE ex, rb_io_t *fptr,
			struct sockaddr *sockaddr, socklen_t *len)
{
    int fd2;

    rb_io_set_nonblock(fptr);
    fd2 = cloexec_accept(fptr->fd, (struct sockaddr*)sockaddr, len, 1);
    if (fd2 < 0) {
	int e = errno;
	switch (e) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
	  case ECONNABORTED:
#if defined EPROTO
	  case EPROTO:
#endif
            if (ex == Qfalse)
		return sym_wait_readable;
            rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE, e, "accept(2) would block");
	}
        rb_syserr_fail(e, "accept(2)");
    }
    rb_update_max_fd(fd2);
    return rsock_init_sock(rb_obj_alloc(klass), fd2);
}

struct accept_arg {
    int fd;
    struct sockaddr *sockaddr;
    socklen_t *len;
};

static VALUE
accept_blocking(void *data)
{
    struct accept_arg *arg = data;
    return (VALUE)cloexec_accept(arg->fd, arg->sockaddr, arg->len, 0);
}

VALUE
rsock_s_accept(VALUE klass, int fd, struct sockaddr *sockaddr, socklen_t *len)
{
    int fd2;
    int retry = 0;
    struct accept_arg arg;

    arg.fd = fd;
    arg.sockaddr = sockaddr;
    arg.len = len;
  retry:
    rsock_maybe_wait_fd(fd);
    fd2 = (int)BLOCKING_REGION_FD(accept_blocking, &arg);
    if (fd2 < 0) {
	int e = errno;
	switch (e) {
	  case EMFILE:
	  case ENFILE:
	  case ENOMEM:
	    if (retry) break;
	    rb_gc();
	    retry = 1;
	    goto retry;
	  default:
	    if (!rb_io_wait_readable(fd)) break;
	    retry = 0;
	    goto retry;
	}
	rb_syserr_fail(e, "accept(2)");
    }
    rb_update_max_fd(fd2);
    if (!klass) return INT2NUM(fd2);
    return rsock_init_sock(rb_obj_alloc(klass), fd2);
}

int
rsock_getfamily(rb_io_t *fptr)
{
    union_sockaddr ss;
    socklen_t sslen = (socklen_t)sizeof(ss);
    int cached = fptr->mode & FMODE_SOCK;

    if (cached) {
        switch (cached) {
#ifdef AF_UNIX
	    case FMODE_UNIX: return AF_UNIX;
#endif
	    case FMODE_INET: return AF_INET;
	    case FMODE_INET6: return AF_INET6;
	}
    }

    ss.addr.sa_family = AF_UNSPEC;
    if (getsockname(fptr->fd, &ss.addr, &sslen) < 0)
        return AF_UNSPEC;

    switch (ss.addr.sa_family) {
#ifdef AF_UNIX
      case AF_UNIX: fptr->mode |= FMODE_UNIX; break;
#endif
      case AF_INET: fptr->mode |= FMODE_INET; break;
      case AF_INET6: fptr->mode |= FMODE_INET6; break;
    }

    return ss.addr.sa_family;
}

void
rsock_init_socket_init(void)
{
    /*
     * SocketError is the error class for socket.
     */
    rb_eSocket = rb_define_class("SocketError", rb_eStandardError);
    rsock_init_ipsocket();
    rsock_init_tcpsocket();
    rsock_init_tcpserver();
    rsock_init_sockssocket();
    rsock_init_udpsocket();
    rsock_init_unixsocket();
    rsock_init_unixserver();
    rsock_init_sockopt();
    rsock_init_ancdata();
    rsock_init_addrinfo();
    rsock_init_sockifaddr();
    rsock_init_socket_constants();

#undef rb_intern
    sym_wait_readable = ID2SYM(rb_intern("wait_readable"));

#if MSG_DONTWAIT_RELIABLE
    sym_wait_writable = ID2SYM(rb_intern("wait_writable"));
#endif
}
