/************************************************

  socket.c -

  $Author$
  $Date$
  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2001 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include "util.h"
#include <stdio.h>
#include <sys/types.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYS_UIO_H
#include <sys/uio.h>
#endif

#ifndef _WIN32
#if defined(__BEOS__)
# include <net/socket.h>
#else
# include <sys/socket.h>
#endif
#include <netinet/in.h>
#ifdef HAVE_NETINET_IN_SYSTM_H
# include <netinet/in_systm.h>
#endif
#ifdef HAVE_NETINET_TCP_H
# include <netinet/tcp.h>
#endif
#ifdef HAVE_NETINET_UDP_H
# include <netinet/udp.h>
#endif
#include <netdb.h>
#endif
#include <errno.h>
#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#endif

#if defined(HAVE_FCNTL)
#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif
#include <sys/types.h>
#include <sys/time.h>
#include <fcntl.h>
#endif
#ifndef EWOULDBLOCK
#define EWOULDBLOCK EAGAIN
#endif
#ifndef HAVE_GETADDRINFO
# include "addrinfo.h"
#endif
#include "sockport.h"

static int do_not_reverse_lookup = 0;
#define FMODE_NOREVLOOKUP 0x100

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

static VALUE rb_eSocket;

#ifdef SOCKS
VALUE rb_cSOCKSSocket;
#ifdef SOCKS5
#include <socks.h>
#else
void SOCKSinit();
int Rconnect();
#endif
#endif

#define INET_CLIENT 0
#define INET_SERVER 1
#define INET_SOCKS  2

#ifndef HAVE_SOCKADDR_STORAGE
/*
 * RFC 2553: protocol-independent placeholder for socket addresses
 */
#define _SS_MAXSIZE	128
#define _SS_ALIGNSIZE	(sizeof(double))
#define _SS_PAD1SIZE	(_SS_ALIGNSIZE - sizeof(unsigned char) * 2)
#define _SS_PAD2SIZE	(_SS_MAXSIZE - sizeof(unsigned char) * 2 - \
				_SS_PAD1SIZE - _SS_ALIGNSIZE)

struct sockaddr_storage {
#ifdef HAVE_SA_LEN
	unsigned char ss_len;		/* address length */
	unsigned char ss_family;	/* address family */
#else
	unsigned short ss_family;
#endif
	char	__ss_pad1[_SS_PAD1SIZE];
	double	__ss_align;	/* force desired structure storage alignment */
	char	__ss_pad2[_SS_PAD2SIZE];
};
#endif

#if defined(INET6) && (defined(LOOKUP_ORDER_HACK_INET) || defined(LOOKUP_ORDER_HACK_INET6))
#define LOOKUP_ORDERS		3
static int lookup_order_table[LOOKUP_ORDERS] = {
#if defined(LOOKUP_ORDER_HACK_INET)
    PF_INET, PF_INET6, PF_UNSPEC,
#elif defined(LOOKUP_ORDER_HACK_INET6)
    PF_INET6, PF_INET, PF_UNSPEC,
#else
    /* should not happen */
#endif
};

static int
ruby_getaddrinfo(nodename, servname, hints, res)
     char *nodename;
     char *servname;
     struct addrinfo *hints;
     struct addrinfo **res;
{
    struct addrinfo tmp_hints;
    int i, af, error;

    if (hints->ai_family != PF_UNSPEC) {
	return getaddrinfo(nodename, servname, hints, res);
    }

    for (i = 0; i < LOOKUP_ORDERS; i++) {
	af = lookup_order_table[i];
	MEMCPY(&tmp_hints, hints, struct addrinfo, 1);
	tmp_hints.ai_family = af;
	error = getaddrinfo(nodename, servname, &tmp_hints, res);
	if (error) {
	    if (tmp_hints.ai_family == PF_UNSPEC) {
		break;
	    }
	}
	else {
	    break;
	}
    }

    return error;
}
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo((node),(serv),(hints),(res))
#endif

#ifdef HAVE_CLOSESOCKET
#undef close
#define close closesocket
#endif

static VALUE
init_sock(sock, fd)
    VALUE sock;
    int fd;
{
    OpenFile *fp;

    MakeOpenFile(sock, fp);
    fp->f = rb_fdopen(fd, "r");
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE;
    if (do_not_reverse_lookup) {
	fp->mode |= FMODE_NOREVLOOKUP;
    }
    rb_io_synchronized(fp);

    return sock;
}

static VALUE
bsock_s_for_fd(klass, fd)
    VALUE klass, fd;
{
    OpenFile *fptr;
    VALUE sock = init_sock(rb_obj_alloc(klass), NUM2INT(fd));

    GetOpenFile(sock, fptr);

    return sock;
}

static VALUE
bsock_shutdown(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE howto;
    int how;
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(sock)) {
	rb_raise(rb_eSecurityError, "Insecure: can't shutdown socket");
    }
    rb_scan_args(argc, argv, "01", &howto);
    if (howto == Qnil)
	how = 2;
    else {
	how = NUM2INT(howto);
	if (how < 0 || 2 < how) {
	    rb_raise(rb_eArgError, "`how' should be either 0, 1, 2");
	}
    }
    GetOpenFile(sock, fptr);
    if (shutdown(fileno(fptr->f), how) == -1)
	rb_sys_fail(0);

    return INT2FIX(0);
}

static VALUE
bsock_close_read(sock)
    VALUE sock;
{
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(sock)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close socket");
    }
    GetOpenFile(sock, fptr);
    shutdown(fileno(fptr->f), 0);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	return rb_io_close(sock);
    }
    fptr->mode &= ~FMODE_READABLE;

    return Qnil;
}

static VALUE
bsock_close_write(sock)
    VALUE sock;
{
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(sock)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close socket");
    }
    GetOpenFile(sock, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	return rb_io_close(sock);
    }
    shutdown(fileno(fptr->f2), 1);
    fptr->mode &= ~FMODE_WRITABLE;

    return Qnil;
}

static VALUE
bsock_setsockopt(sock, lev, optname, val)
    VALUE sock, lev, optname, val;
{
    int level, option;
    OpenFile *fptr;
    int i;
    char *v;
    int vlen;

    rb_secure(2);
    level = NUM2INT(lev);
    option = NUM2INT(optname);
    switch (TYPE(val)) {
      case T_FIXNUM:
	i = FIX2INT(val);
	goto numval;
      case T_FALSE:
	i = 0;
	goto numval;
      case T_TRUE:
	i = 1;
      numval:
	v = (char*)&i; vlen = sizeof(i);
	break;
      default:
	StringValue(val);
	v = RSTRING(val)->ptr;
	vlen = RSTRING(val)->len;
	break;
    }

    GetOpenFile(sock, fptr);
    if (setsockopt(fileno(fptr->f), level, option, v, vlen) < 0)
	rb_sys_fail(fptr->path);

    return INT2FIX(0);
}

static VALUE
bsock_getsockopt(sock, lev, optname)
    VALUE sock, lev, optname;
{
#if !defined(__BEOS__)
    int level, option;
    socklen_t len;
    char *buf;
    OpenFile *fptr;

    level = NUM2INT(lev);
    option = NUM2INT(optname);
    len = 256;
    buf = ALLOCA_N(char,len);

    GetOpenFile(sock, fptr);
    if (getsockopt(fileno(fptr->f), level, option, buf, &len) < 0)
	rb_sys_fail(fptr->path);

    return rb_str_new(buf, len);
#else
    rb_notimplement();
#endif
}

static VALUE
bsock_getsockname(sock)
    VALUE sock;
{
    char buf[1024];
    socklen_t len = sizeof buf;
    OpenFile *fptr;

    GetOpenFile(sock, fptr);
    if (getsockname(fileno(fptr->f), (struct sockaddr*)buf, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return rb_str_new(buf, len);
}

static VALUE
bsock_getpeername(sock)
    VALUE sock;
{
    char buf[1024];
    socklen_t len = sizeof buf;
    OpenFile *fptr;

    GetOpenFile(sock, fptr);
    if (getpeername(fileno(fptr->f), (struct sockaddr*)buf, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return rb_str_new(buf, len);
}

static VALUE
bsock_send(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE mesg, to;
    VALUE flags;
    OpenFile *fptr;
    FILE *f;
    int fd, n;

    rb_secure(4);
    rb_scan_args(argc, argv, "21", &mesg, &flags, &to);

    GetOpenFile(sock, fptr);
    f = GetWriteFile(fptr);
    fd = fileno(f);
    rb_thread_fd_writable(fd);
    StringValue(mesg);
  retry:
    if (!NIL_P(to)) {
	StringValue(to);
	n = sendto(fd, RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags),
		   (struct sockaddr*)RSTRING(to)->ptr, RSTRING(to)->len);
    }
    else {
	n = send(fd, RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags));
    }
    if (n < 0) {
	if (rb_io_wait_writable(fd)) {
	    goto retry;
	}
	rb_sys_fail("send(2)");
    }
    return INT2FIX(n);
}

static VALUE
bsock_do_not_reverse_lookup(sock)
    VALUE sock;
{
    OpenFile *fptr;

    GetOpenFile(sock, fptr);
    return (fptr->mode & FMODE_NOREVLOOKUP) ? Qtrue : Qfalse;
}

static VALUE
bsock_do_not_reverse_lookup_set(sock, state)
    VALUE sock;
    VALUE state;
{
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(sock, fptr);
    if (RTEST(state)) {
	fptr->mode |= FMODE_NOREVLOOKUP;
    }
    else {
	fptr->mode &= ~FMODE_NOREVLOOKUP;
    }
    return sock;
}

static VALUE ipaddr _((struct sockaddr*, int));
#ifdef HAVE_SYS_UN_H
static VALUE unixaddr _((struct sockaddr_un*));
#endif

enum sock_recv_type {
    RECV_RECV,			/* BasicSocket#recv(no from) */
    RECV_IP,			/* IPSocket#recvfrom */
    RECV_UNIX,			/* UNIXSocket#recvfrom */
    RECV_SOCKET			/* Socket#recvfrom */
};

static VALUE
s_recvfrom(sock, argc, argv, from)
    VALUE sock;
    int argc;
    VALUE *argv;
    enum sock_recv_type from;
{
    OpenFile *fptr;
    VALUE str;
    char buf[1024];
    socklen_t alen = sizeof buf;
    VALUE len, flg;
    long buflen;
    long slen;
    int fd, flags;

    rb_scan_args(argc, argv, "11", &len, &flg);

    if (flg == Qnil) flags = 0;
    else             flags = NUM2INT(flg);

    GetOpenFile(sock, fptr);
    if (rb_read_pending(fptr->f)) {
	rb_raise(rb_eIOError, "recv for buffered IO");
    }
    fd = fileno(fptr->f);

    buflen = NUM2INT(len);
    str = rb_tainted_str_new(0, buflen);

  retry:
    rb_thread_wait_fd(fd);
    TRAP_BEG;
    slen = recvfrom(fd, RSTRING(str)->ptr, buflen, flags, (struct sockaddr*)buf, &alen);
    TRAP_END;

    if (slen < 0) {
	if (rb_io_wait_readable(fd)) {
	    goto retry;
	}
	rb_sys_fail("recvfrom(2)");
    }
    if (slen < RSTRING(str)->len) {
	RSTRING(str)->len = slen;
	RSTRING(str)->ptr[slen] = '\0';
    }
    rb_obj_taint(str);
    switch (from) {
      case RECV_RECV:
	return (VALUE)str;
      case RECV_IP:
#if 0
	if (alen != sizeof(struct sockaddr_in)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
#endif
	return rb_assoc_new(str, ipaddr((struct sockaddr*)buf, fptr->mode & FMODE_NOREVLOOKUP));
#ifdef HAVE_SYS_UN_H
      case RECV_UNIX:
	return rb_assoc_new(str, unixaddr((struct sockaddr_un*)buf));
#endif
      case RECV_SOCKET:
	return rb_assoc_new(str, rb_str_new(buf, alen));
      default:
	rb_bug("s_recvfrom called with bad value");
    }
}

static VALUE
bsock_recv(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_RECV);
}

static VALUE
bsock_do_not_rev_lookup()
{
    return do_not_reverse_lookup?Qtrue:Qfalse;
}

static VALUE
bsock_do_not_rev_lookup_set(self, val)
    VALUE self, val;
{
    rb_secure(4);
    do_not_reverse_lookup = RTEST(val);
    return val;
}

NORETURN(static void raise_socket_error _((char *, int)));
static void
raise_socket_error(reason, error)
    char *reason;
    int error;
{
#ifdef EAI_SYSTEM
    if (error == EAI_SYSTEM) rb_sys_fail(reason);
#endif
    rb_raise(rb_eSocket, "%s: %s", reason, gai_strerror(error));
}

static void
make_ipaddr0(addr, buf, len)
    struct sockaddr *addr;
    char *buf;
    size_t len;
{
    int error;

    error = getnameinfo(addr, SA_LEN(addr), buf, len, NULL, 0, NI_NUMERICHOST);
    if (error) {
	raise_socket_error("getnameinfo", error);
    }
}

static VALUE
make_ipaddr(addr)
    struct sockaddr *addr;
{
    char buf[1024];

    make_ipaddr0(addr, buf, sizeof(buf));
    return rb_str_new2(buf);
}

static void
make_inetaddr(host, buf, len)
    long host;
    char *buf;
    size_t len;
{
    struct sockaddr_in sin;

    MEMZERO(&sin, struct sockaddr_in, 1);
    sin.sin_family = AF_INET;
    SET_SIN_LEN(&sin, sizeof(sin));
    sin.sin_addr.s_addr = host;
    make_ipaddr0((struct sockaddr*)&sin, buf, len);
}

static int
str_isnumber(p)
        const char *p;
{
    char *ep;

    if (!p || *p == '\0')
       return 0;
    ep = NULL;
    (void)strtoul(p, &ep, 10);
    if (ep && *ep == '\0')
       return 1;
    else
       return 0;
}

static char *
host_str(host, hbuf, len)
    VALUE host;
    char *hbuf;
    size_t len;
{
    if (NIL_P(host)) {
	return NULL;
    }
    else if (rb_obj_is_kind_of(host, rb_cInteger)) {
	long i = NUM2LONG(host);

	make_inetaddr(htonl(i), hbuf, len);
	return hbuf;
    }
    else {
	char *name;

	SafeStringValue(host);
	name = RSTRING(host)->ptr;
	if (!name || *name == 0 || (name[0] == '<' && strcmp(name, "<any>") == 0)) {
	    make_inetaddr(INADDR_ANY, hbuf, len);
	}
	else if (name[0] == '<' && strcmp(name, "<broadcast>") == 0) {
	    make_inetaddr(INADDR_BROADCAST, hbuf, len);
	}
	else if (strlen(name) >= len) {
	    rb_raise(rb_eArgError, "hostname too long (%d)", strlen(name));
	}
	else {
	    strcpy(hbuf, name);
	}
	return hbuf;
    }
}

static char *
port_str(port, pbuf, len)
    VALUE port;
    char *pbuf;
    size_t len;
{
    if (NIL_P(port)) {
	return 0;
    }
    else if (FIXNUM_P(port)) {
	snprintf(pbuf, len, "%ld", FIX2LONG(port));
	return pbuf;
    }
    else {
	char *serv;

	SafeStringValue(port);
	serv = RSTRING(port)->ptr;
	if (strlen(serv) >= len) {
	    rb_raise(rb_eArgError, "service name too long (%d)", strlen(serv));
	}
	strcpy(pbuf, serv);
	return pbuf;
    }
}

#ifndef NI_MAXHOST
# define 1025
#endif
#ifndef NI_MAXSERV
# define 32
#endif

static struct addrinfo*
sock_addrinfo(host, port, socktype, flags)
    VALUE host, port;
    int socktype, flags;
{
    struct addrinfo hints;
    struct addrinfo* res = NULL;
    char *hostp, *portp;
    int error;
    char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];

    hostp = host_str(host, hbuf, sizeof(hbuf));
    portp = port_str(port, pbuf, sizeof(pbuf));

    if (socktype == 0 && flags == 0 && str_isnumber(portp)) {
       socktype = SOCK_DGRAM;
    }

    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = socktype;
    hints.ai_flags = flags;
    error = getaddrinfo(hostp, portp, &hints, &res);
    if (error) {
	if (hostp && hostp[strlen(hostp)-1] == '\n') {
	    rb_raise(rb_eSocket, "newline at the end of hostname");
	}
	raise_socket_error("getaddrinfo", error);
    }

#if defined(__APPLE__) && defined(__MACH__)
    {
        struct addrinfo *r;
       r = res;
       while (r) {
            if (! r->ai_socktype) r->ai_socktype = hints.ai_socktype;
            if (! r->ai_protocol) {
                if (r->ai_socktype == SOCK_DGRAM) {
                    r->ai_protocol = IPPROTO_UDP;
                } else if (r->ai_socktype == SOCK_STREAM) {
                    r->ai_protocol = IPPROTO_TCP;
                }
            }
            r = r->ai_next;
        }
    }
#endif
    return res;
}

static VALUE
ipaddr(sockaddr, norevlookup)
    struct sockaddr *sockaddr;
    int norevlookup;
{
    VALUE family, port, addr1, addr2;
    VALUE ary;
    int error;
    char hbuf[1024], pbuf[1024];

    switch (sockaddr->sa_family) {
    case AF_UNSPEC:
	family = rb_str_new2("AF_UNSPEC");
	break;
    case AF_INET:
	family = rb_str_new2("AF_INET");
	break;
#ifdef INET6
    case AF_INET6:
	family = rb_str_new2("AF_INET6");
	break;
#endif
#ifdef AF_LOCAL
    case AF_LOCAL:
	family = rb_str_new2("AF_LOCAL");
	break;
#elif  AF_UNIX
    case AF_UNIX:
	family = rb_str_new2("AF_UNIX");
	break;
#endif
    default:
        sprintf(pbuf, "unknown:%d", sockaddr->sa_family);
	family = rb_str_new2(pbuf);
	break;
    }

    addr1 = Qnil;
    if (!norevlookup) {
	error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			    NULL, 0, 0);
	if (! error) {
	    addr1 = rb_str_new2(hbuf);
	}
    }
    error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV);
    if (error) {
	raise_socket_error("getnameinfo", error);
    }
    addr2 = rb_str_new2(hbuf);
    if (addr1 == Qnil) {
	addr1 = addr2;
    }
    port = INT2FIX(atoi(pbuf));
    ary = rb_ary_new3(4, family, port, addr1, addr2);

    return ary;
}

static int
ruby_socket(domain, type, proto)
    int domain, type, proto;
{
    int fd;

    fd = socket(domain, type, proto);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    fd = socket(domain, type, proto);
	}
    }
    return fd;
}

static void
thread_write_select(fd)
    int fd;
{
    fd_set fds;

    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    rb_thread_select(fd+1, 0, &fds, 0, 0);
}

#ifdef __CYGWIN__
#define WAIT_IN_PROGRESS 10
#endif
#ifdef __APPLE__
#define WAIT_IN_PROGRESS 10
#endif
#ifdef __linux__
/* returns correct error */
#define WAIT_IN_PROGRESS 0
#endif
#ifndef WAIT_IN_PROGRESS
/* BSD origin code apparently has a problem */
#define WAIT_IN_PROGRESS 1
#endif

static int
ruby_connect(fd, sockaddr, len, socks)
    int fd;
    struct sockaddr *sockaddr;
    int len;
    int socks;
{
    int status;
    int mode;
#if WAIT_IN_PROGRESS > 0
    int wait_in_progress = -1;
    int sockerr, sockerrlen;
#endif

#if defined(HAVE_FCNTL)
    mode = fcntl(fd, F_GETFL, 0);

#ifdef O_NDELAY
# define NONBLOCKING O_NDELAY
#else
#ifdef O_NBIO
# define NONBLOCKING O_NBIO
#else
# define NONBLOCKING O_NONBLOCK
#endif
#endif
#ifdef SOCKS5
    if (!socks)
#endif
    fcntl(fd, F_SETFL, mode|NONBLOCKING);
#endif /* HAVE_FCNTL */

    for (;;) {
#if defined(SOCKS) && !defined(SOCKS5)
	if (socks) {
	    status = Rconnect(fd, sockaddr, len);
	}
	else
#endif
	{
	    status = connect(fd, sockaddr, len);
	}
	if (status < 0) {
	    switch (errno) {
	      case EAGAIN:
#ifdef EINPROGRESS
	      case EINPROGRESS:
#endif
#if WAIT_IN_PROGRESS > 0
		sockerrlen = sizeof(sockerr);
		status = getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&sockerr, &sockerrlen);
		if (status) break;
		if (sockerr) {
		    status = -1;
		    errno = sockerr;
		    break;
		}
#endif
#ifdef EALREADY
	      case EALREADY:
#endif
#if WAIT_IN_PROGRESS > 0
		wait_in_progress = WAIT_IN_PROGRESS;
#endif
		thread_write_select(fd);
		continue;

#if WAIT_IN_PROGRESS > 0
	      case EINVAL:
		if (wait_in_progress-- > 0) {
		    /*
		     * connect() after EINPROGRESS returns EINVAL on
		     * some platforms, need to check true error
		     * status.
		     */
		    sockerrlen = sizeof(sockerr);
		    status = getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&sockerr, &sockerrlen);
		    if (!status && !sockerr) {
			struct timeval tv = {0, 100000};
			rb_thread_wait_for(tv);
			continue;
		    }
		    status = -1;
		    errno = sockerr;
		}
		break;
#endif

#ifdef EISCONN
	      case EISCONN:
		status = 0;
		errno = 0;
		break;
#endif
	      default:
		break;
	    }
	}
#ifdef HAVE_FCNTL
	fcntl(fd, F_SETFL, mode);
#endif
	return status;
    }
}

struct inetsock_arg
{
    VALUE sock;
    struct {
	VALUE host, serv;
	struct addrinfo *res;
    } remote, local;
    int type;
    int fd;
};

static VALUE
inetsock_cleanup(arg)
    struct inetsock_arg *arg;
{
    if (arg->remote.res) {
	freeaddrinfo(arg->remote.res);
	arg->remote.res = 0;
    }
    if (arg->local.res) {
	freeaddrinfo(arg->local.res);
	arg->local.res = 0;
    }
    if (arg->fd >= 0) {
	close(arg->fd);
    }
    return Qnil;
}

static VALUE
init_inetsock_internal(arg)
    struct inetsock_arg *arg;
{
    int type = arg->type;
    struct addrinfo *res;
    int fd, status = 0;
    char *syscall;

    arg->remote.res = sock_addrinfo(arg->remote.host, arg->remote.serv, SOCK_STREAM,
				    (type == INET_SERVER) ? AI_PASSIVE : 0);
    /*
     * Maybe also accept a local address
     */

    if (type != INET_SERVER && (!NIL_P(arg->local.host) || !NIL_P(arg->local.serv))) {
	arg->local.res = sock_addrinfo(arg->local.host, arg->local.serv, SOCK_STREAM, 0);
    }

    arg->fd = fd = -1;
    for (res = arg->remote.res; res; res = res->ai_next) {
	status = ruby_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
	syscall = "socket(2)";
	fd = status;
	if (fd < 0) {
	    continue;
	}
	arg->fd = fd;
	if (type == INET_SERVER) {
#ifndef _WIN32
	    status = 1;
	    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
		       (char*)&status, sizeof(status));
#endif
	    status = bind(fd, res->ai_addr, res->ai_addrlen);
	    syscall = "bind(2)";
	}
	else {
	    if (arg->local.res) {
		status = bind(fd, arg->local.res->ai_addr, arg->local.res->ai_addrlen);
		syscall = "bind(2)";
	    }

	    if (status >= 0) {
		status = ruby_connect(fd, res->ai_addr, res->ai_addrlen,
				      (type == INET_SOCKS));
		syscall = "connect(2)";
	    }
	}

	if (status < 0) {
	    close(fd);
	    arg->fd = fd = -1;
	    continue;
	} else
	    break;
    }
    if (status < 0) {
	rb_sys_fail(syscall);
    }

    arg->fd = -1;

    if (type == INET_SERVER)
	listen(fd, 5);

    /* create new instance */
    return init_sock(arg->sock, fd);
}

static VALUE
init_inetsock(sock, remote_host, remote_serv, local_host, local_serv, type)
    VALUE sock, remote_host, remote_serv, local_host, local_serv;
    int type;
{
    struct inetsock_arg arg;
    arg.sock = sock;
    arg.remote.host = remote_host;
    arg.remote.serv = remote_serv;
    arg.remote.res = 0;
    arg.local.host = local_host;
    arg.local.serv = local_serv;
    arg.local.res = 0;
    arg.type = type;
    arg.fd = -1;
    return rb_ensure(init_inetsock_internal, (VALUE)&arg,
		     inetsock_cleanup, (VALUE)&arg);
}

static VALUE
tcp_init(argc, argv, sock)
     int argc;
     VALUE *argv;
     VALUE sock;
{
    VALUE remote_host, remote_serv;
    VALUE local_host, local_serv;

    rb_scan_args(argc, argv, "22", &remote_host, &remote_serv,
			&local_host, &local_serv);

    return init_inetsock(sock, remote_host, remote_serv,
			local_host, local_serv, INET_CLIENT);
}

#ifdef SOCKS
static VALUE
socks_init(sock, host, serv)
    VALUE sock, host, serv;
{
    static init = 0;

    if (init == 0) {
	SOCKSinit("ruby");
	init = 1;
    }

    return init_inetsock(sock, host, serv, Qnil, Qnil, INET_SOCKS);
}

#ifdef SOCKS5
static VALUE
socks_s_close(sock)
    VALUE sock;
{
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(sock)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close socket");
    }
    GetOpenFile(sock, fptr);
    shutdown(fileno(fptr->f), 2);
    shutdown(fileno(fptr->f2), 2);
    return rb_io_close(sock);
}
#endif
#endif

struct hostent_arg {
    VALUE host;
    struct addrinfo* addr;
    VALUE (*ipaddr)_((struct sockaddr*, size_t));
};

static VALUE
make_hostent_internal(arg)
    struct hostent_arg *arg;
{
    VALUE host = arg->host;
    struct addrinfo* addr = arg->addr;
    VALUE (*ipaddr)_((struct sockaddr*, size_t)) = arg->ipaddr;

    struct addrinfo *ai;
    struct hostent *h;
    VALUE ary, names;
    char **pch;
    const char* hostp;
    char hbuf[NI_MAXHOST];

    ary = rb_ary_new();
    if (addr->ai_canonname) {
	hostp = addr->ai_canonname;
    }
    else {
	hostp = host_str(host, hbuf, sizeof(hbuf));
    }
    rb_ary_push(ary, rb_str_new2(hostp));

    if (addr->ai_canonname && (h = gethostbyname(addr->ai_canonname))) {
	names = rb_ary_new();
	if (h->h_aliases != NULL) {
	    for (pch = h->h_aliases; *pch; pch++) {
		rb_ary_push(names, rb_str_new2(*pch));
	    }
	}
    }
    else {
	names = rb_ary_new2(0);
    }
    rb_ary_push(ary, names);
    rb_ary_push(ary, INT2NUM(addr->ai_family));
    for (ai = addr; ai; ai = ai->ai_next) {
	rb_ary_push(ary, (*ipaddr)(ai->ai_addr, ai->ai_addrlen));
    }

    return ary;
}

static VALUE
make_hostent(host, addr, ipaddr)
    VALUE host;
    struct addrinfo* addr;
    VALUE (*ipaddr)_((struct sockaddr*, size_t));
{
    struct hostent_arg arg;

    arg.host = host;
    arg.addr = addr;
    arg.ipaddr = ipaddr;
    return rb_ensure(make_hostent_internal, (VALUE)&arg,
		     RUBY_METHOD_FUNC(freeaddrinfo), (VALUE)addr);
}

VALUE
tcp_sockaddr(addr, len)
    struct sockaddr *addr;
    size_t len;
{
    return make_ipaddr(addr);
}

static VALUE
tcp_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    rb_secure(3);
    return make_hostent(host, sock_addrinfo(host, Qnil, SOCK_STREAM, AI_CANONNAME), tcp_sockaddr);
}

static VALUE
tcp_svr_init(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2)
	return init_inetsock(sock, arg1, arg2, Qnil, Qnil, INET_SERVER);
    else
	return init_inetsock(sock, Qnil, arg1, Qnil, Qnil, INET_SERVER);
}

static VALUE
s_accept(klass, fd, sockaddr, len)
    VALUE klass;
    int fd;
    struct sockaddr *sockaddr;
    socklen_t *len;
{
    int fd2;
    int retry = 0;

    rb_secure(3);
  retry:
    rb_thread_wait_fd(fd);
#if defined(_nec_ews)
    fd2 = accept(fd, sockaddr, len);
#else
    TRAP_BEG;
    fd2 = accept(fd, sockaddr, len);
    TRAP_END;
#endif
    if (fd2 < 0) {
	switch (errno) {
	  case EMFILE:
	  case ENFILE:
	    if (retry) break;
	    rb_gc();
	    retry = 1;
	    goto retry;
	  default:
	    if (!rb_io_wait_readable(fd)) break;
	    retry = 0;
	    goto retry;
	}
	rb_sys_fail(0);
    }
    if (!klass) return INT2NUM(fd2);
    return init_sock(rb_obj_alloc(klass), fd2);
}

static VALUE
tcp_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_storage from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(from);
    return s_accept(rb_cTCPSocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

static VALUE
tcp_sysaccept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_storage from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(from);
    return s_accept(0, fileno(fptr->f), (struct sockaddr*)&from, &fromlen);
}

#ifdef HAVE_SYS_UN_H
struct unixsock_arg {
    struct sockaddr_un *sockaddr;
    int fd;
};

static VALUE
unixsock_connect_internal(arg)
    struct unixsock_arg *arg;
{
    return (VALUE)ruby_connect(arg->fd, arg->sockaddr, sizeof(*arg->sockaddr),
			       0);
}

static VALUE
init_unixsock(sock, path, server)
    VALUE sock;
    VALUE path;
    int server;
{
    struct sockaddr_un sockaddr;
    int fd, status;
    OpenFile *fptr;

    SafeStringValue(path);
    fd = ruby_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
	rb_sys_fail("socket(2)");
    }

    MEMZERO(&sockaddr, struct sockaddr_un, 1);
    sockaddr.sun_family = AF_UNIX;
    strncpy(sockaddr.sun_path, RSTRING(path)->ptr, sizeof(sockaddr.sun_path)-1);
    sockaddr.sun_path[sizeof(sockaddr.sun_path)-1] = '\0';

    if (server) {
        status = bind(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
    }
    else {
	int prot;
	struct unixsock_arg arg;
	arg.sockaddr = &sockaddr;
	arg.fd = fd;
        status = rb_protect(unixsock_connect_internal, (VALUE)&arg, &prot);
	if (prot) {
	    close(fd);
	    rb_jump_tag(prot);
	}
    }

    if (status < 0) {
	close(fd);
	rb_sys_fail(sockaddr.sun_path);
    }

    if (server) listen(fd, 5);

    init_sock(sock, fd);
    GetOpenFile(sock, fptr);
    fptr->path = strdup(RSTRING(path)->ptr);

    return sock;
}
#endif

static VALUE
ip_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return ipaddr((struct sockaddr*)&addr, fptr->mode & FMODE_NOREVLOOKUP);
}

static VALUE
ip_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return ipaddr((struct sockaddr*)&addr, fptr->mode & FMODE_NOREVLOOKUP);
}

static VALUE
ip_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_IP);
}

static VALUE
ip_s_getaddress(obj, host)
    VALUE obj, host;
{
    struct sockaddr_storage addr;
    struct addrinfo *res = sock_addrinfo(host, Qnil, SOCK_STREAM, 0);

    /* just take the first one */
    memcpy(&addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    return make_ipaddr((struct sockaddr*)&addr);
}

static VALUE
udp_init(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE arg;
    int socktype = AF_INET;
    int fd;

    rb_secure(3);
    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
	socktype = NUM2INT(arg);
    }
    fd = ruby_socket(socktype, SOCK_DGRAM, 0);
    if (fd < 0) {
	rb_sys_fail("socket(2) - udp");
    }

    return init_sock(sock, fd);
}

struct udp_arg
{
    struct addrinfo *res;
    int fd;
};

static VALUE
udp_connect_internal(arg)
    struct udp_arg *arg;
{
    int fd = arg->fd;
    struct addrinfo *res;

    for (res = arg->res; res; res = res->ai_next) {
	if (ruby_connect(fd, res->ai_addr, res->ai_addrlen, 0) >= 0) {
	    return Qtrue;
	}
    }
    return Qfalse;
}

static VALUE
udp_connect(sock, host, port)
    VALUE sock, host, port;
{
    OpenFile *fptr;
    struct udp_arg arg;
    VALUE ret;

    rb_secure(3);
    GetOpenFile(sock, fptr);
    arg.res = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    arg.fd = fileno(fptr->f);
    ret = rb_ensure(udp_connect_internal, (VALUE)&arg,
		    RUBY_METHOD_FUNC(freeaddrinfo), (VALUE)arg.res);
    if (!ret) rb_sys_fail("connect(2)");
    return INT2FIX(0);
}

static VALUE
udp_bind(sock, host, port)
    VALUE sock, host, port;
{
    OpenFile *fptr;
    struct addrinfo *res0, *res;

    rb_secure(3);
    GetOpenFile(sock, fptr);
    res0 = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    for (res = res0; res; res = res->ai_next) {
	if (bind(fileno(fptr->f), res->ai_addr, res->ai_addrlen) < 0) {
	    continue;
	}
	freeaddrinfo(res0);
	return INT2FIX(0);
    }
    freeaddrinfo(res0);
    rb_sys_fail("bind(2)");
    return INT2FIX(0);
}

static VALUE
udp_send(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE mesg, flags, host, port;
    OpenFile *fptr;
    FILE *f;
    int n;
    struct addrinfo *res0, *res;

    if (argc == 2 || argc == 3) {
	return bsock_send(argc, argv, sock);
    }
    rb_secure(4);
    rb_scan_args(argc, argv, "4", &mesg, &flags, &host, &port);

    GetOpenFile(sock, fptr);
    res0 = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    f = GetWriteFile(fptr);
    StringValue(mesg);
    for (res = res0; res; res = res->ai_next) {
      retry:
	n = sendto(fileno(f), RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags),
		   res->ai_addr, res->ai_addrlen);
	if (n >= 0) {
	    freeaddrinfo(res0);
	    return INT2FIX(n);
	}
	if (rb_io_wait_writable(fileno(f))) {
	    goto retry;
	}
    }
    freeaddrinfo(res0);
    rb_sys_fail("sendto(2)");
    return INT2FIX(n);
}

#ifdef HAVE_SYS_UN_H
static VALUE
unix_init(sock, path)
    VALUE sock, path;
{
    return init_unixsock(sock, path, 0);
}

static VALUE
unix_path(sock)
    VALUE sock;
{
    OpenFile *fptr;

    GetOpenFile(sock, fptr);
    if (fptr->path == 0) {
	struct sockaddr_un addr;
	socklen_t len = sizeof(addr);
	if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	    rb_sys_fail(0);
	fptr->path = strdup(addr.sun_path);
    }
    return rb_str_new2(fptr->path);
}

static VALUE
unix_svr_init(sock, path)
    VALUE sock, path;
{
    return init_unixsock(sock, path, 1);
}

static VALUE
unix_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_UNIX);
}

static VALUE
unix_send_io(sock, val)
    VALUE sock, val;
{
#if defined(HAVE_SENDMSG) && (defined(HAVE_ST_MSG_CONTROL) || defined(HAVE_ST_MSG_ACCRIGHTS))
    int fd;
    OpenFile *fptr;
    struct msghdr msg;
    struct iovec vec[1];
    char buf[1];

#if defined(HAVE_ST_MSG_CONTROL)
    struct {
	struct cmsghdr hdr;
	int fd;
    } cmsg;
#endif

    if (rb_obj_is_kind_of(val, rb_cIO)) {
        OpenFile *valfptr;
	GetOpenFile(val, valfptr);
	fd = fileno(valfptr->f);
    }
    else if (FIXNUM_P(val)) {
        fd = FIX2INT(val);
    }
    else {
	rb_raise(rb_eTypeError, "IO nor file descriptor");
    }

    GetOpenFile(sock, fptr);

    msg.msg_name = NULL;
    msg.msg_namelen = 0;

    /* Linux and Solaris doesn't work if msg_iov is NULL. */
    buf[0] = '\0';
    vec[0].iov_base = buf;
    vec[0].iov_len = 1;
    msg.msg_iov = vec;
    msg.msg_iovlen = 1;

#if defined(HAVE_ST_MSG_CONTROL)
    msg.msg_control = (caddr_t)&cmsg;
    msg.msg_controllen = sizeof(struct cmsghdr) + sizeof(int);
    msg.msg_flags = 0;
    cmsg.hdr.cmsg_len = sizeof(struct cmsghdr) + sizeof(int);
    cmsg.hdr.cmsg_level = SOL_SOCKET;
    cmsg.hdr.cmsg_type = SCM_RIGHTS;
    cmsg.fd = fd;
#else
    msg.msg_accrights = (caddr_t)&fd;
    msg.msg_accrightslen = sizeof(fd);
#endif

    if (sendmsg(fileno(fptr->f), &msg, 0) == -1)
	rb_sys_fail("sendmsg(2)");

    return Qnil;
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

#if defined(HAVE_RECVMSG) && (defined(HAVE_ST_MSG_CONTROL) || defined(HAVE_ST_MSG_ACCRIGHTS))
static void
thread_read_select(fd)
    int fd;
{
    fd_set fds;

    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    rb_thread_select(fd+1, &fds, 0, 0, 0);
}
#endif

static VALUE
unix_recv_io(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
#if defined(HAVE_RECVMSG) && (defined(HAVE_ST_MSG_CONTROL) || defined(HAVE_ST_MSG_ACCRIGHTS))
    VALUE klass, mode;
    OpenFile *fptr;
    struct msghdr msg;
    struct iovec vec[2];
    char buf[1];

    int fd;
#if defined(HAVE_ST_MSG_CONTROL)
    struct {
	struct cmsghdr hdr;
	int fd;
    } cmsg;
#endif

    rb_scan_args(argc, argv, "02", &klass, &mode);
    if (argc == 0)
	klass = rb_cIO;
    if (argc <= 1)
	mode = Qnil;

    GetOpenFile(sock, fptr);

    thread_read_select(fileno(fptr->f));

    msg.msg_name = NULL;
    msg.msg_namelen = 0;

    vec[0].iov_base = buf;
    vec[0].iov_len = sizeof(buf);
    msg.msg_iov = vec;
    msg.msg_iovlen = 1;

#if defined(HAVE_ST_MSG_CONTROL)
    msg.msg_control = (caddr_t)&cmsg;
    msg.msg_controllen = sizeof(struct cmsghdr) + sizeof(int);
    msg.msg_flags = 0;
    cmsg.hdr.cmsg_len = sizeof(struct cmsghdr) + sizeof(int);
    cmsg.hdr.cmsg_level = SOL_SOCKET;
    cmsg.hdr.cmsg_type = SCM_RIGHTS;
    cmsg.fd = -1;
#else
    msg.msg_accrights = (caddr_t)&fd;
    msg.msg_accrightslen = sizeof(fd);
    fd = -1;
#endif

    if (recvmsg(fileno(fptr->f), &msg, 0) == -1)
	rb_sys_fail("recvmsg(2)");

    if (
#if defined(HAVE_ST_MSG_CONTROL)
	msg.msg_controllen != sizeof(struct cmsghdr) + sizeof(int) ||
        cmsg.hdr.cmsg_len != sizeof(struct cmsghdr) + sizeof(int) ||
	cmsg.hdr.cmsg_level != SOL_SOCKET ||
	cmsg.hdr.cmsg_type != SCM_RIGHTS
#else
        msg.msg_accrightslen != sizeof(fd)
#endif
	) {
	rb_raise(rb_eSocket, "File descriptor was not passed");
    }

#if defined(HAVE_ST_MSG_CONTROL)
    fd = cmsg.fd;
#endif

    if (klass == Qnil)
	return INT2FIX(fd);
    else {
	static ID for_fd = 0;
	int ff_argc;
	VALUE ff_argv[2];
	if (!for_fd)
	    for_fd = rb_intern("for_fd");
	ff_argc = mode == Qnil ? 1 : 2;
	ff_argv[0] = INT2FIX(fd);
	ff_argv[1] = mode;
        return rb_funcall2(klass, for_fd, ff_argc, ff_argv);
    }
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
unix_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return s_accept(rb_cUNIXSocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

static VALUE
unix_sysaccept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return s_accept(0, fileno(fptr->f), (struct sockaddr*)&from, &fromlen);
}

#ifdef HAVE_SYS_UN_H
static VALUE
unixaddr(sockaddr)
    struct sockaddr_un *sockaddr;
{
    return rb_assoc_new(rb_str_new2("AF_UNIX"),
			rb_str_new2(sockaddr->sun_path));
}
#endif

static VALUE
unix_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    if (len == 0)
        addr.sun_path[0] = '\0';
    return unixaddr(&addr);
}

static VALUE
unix_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    if (len == 0)
        addr.sun_path[0] = '\0';
    return unixaddr(&addr);
}
#endif

static void
setup_domain_and_type(domain, dv, type, tv)
    VALUE domain, type;
    int *dv, *tv;
{
    char *ptr;

    if (TYPE(domain) == T_STRING) {
	SafeStringValue(domain);
	ptr = RSTRING(domain)->ptr;
	if (strcmp(ptr, "AF_INET") == 0)
	    *dv = AF_INET;
#ifdef AF_UNIX
	else if (strcmp(ptr, "AF_UNIX") == 0)
	    *dv = AF_UNIX;
#endif
#ifdef AF_ISO
	else if (strcmp(ptr, "AF_ISO") == 0)
	    *dv = AF_ISO;
#endif
#ifdef AF_NS
	else if (strcmp(ptr, "AF_NS") == 0)
	    *dv = AF_NS;
#endif
#ifdef AF_IMPLINK
	else if (strcmp(ptr, "AF_IMPLINK") == 0)
	    *dv = AF_IMPLINK;
#endif
#ifdef PF_INET
	else if (strcmp(ptr, "PF_INET") == 0)
	    *dv = PF_INET;
#endif
#ifdef PF_UNIX
	else if (strcmp(ptr, "PF_UNIX") == 0)
	    *dv = PF_UNIX;
#endif
#ifdef PF_IMPLINK
	else if (strcmp(ptr, "PF_IMPLINK") == 0)
	    *dv = PF_IMPLINK;
	else if (strcmp(ptr, "AF_IMPLINK") == 0)
	    *dv = AF_IMPLINK;
#endif
#ifdef PF_AX25
	else if (strcmp(ptr, "PF_AX25") == 0)
	    *dv = PF_AX25;
#endif
#ifdef PF_IPX
	else if (strcmp(ptr, "PF_IPX") == 0)
	    *dv = PF_IPX;
#endif
	else
	    rb_raise(rb_eSocket, "Unknown socket domain %s", ptr);
    }
    else {
	*dv = NUM2INT(domain);
    }
    if (TYPE(type) == T_STRING) {
	SafeStringValue(type);
	ptr = RSTRING(type)->ptr;
	if (strcmp(ptr, "SOCK_STREAM") == 0)
	    *tv = SOCK_STREAM;
	else if (strcmp(ptr, "SOCK_DGRAM") == 0)
	    *tv = SOCK_DGRAM;
#ifdef SOCK_RAW
	else if (strcmp(ptr, "SOCK_RAW") == 0)
	    *tv = SOCK_RAW;
#endif
#ifdef SOCK_SEQPACKET
	else if (strcmp(ptr, "SOCK_SEQPACKET") == 0)
	    *tv = SOCK_SEQPACKET;
#endif
#ifdef SOCK_RDM
	else if (strcmp(ptr, "SOCK_RDM") == 0)
	    *tv = SOCK_RDM;
#endif
#ifdef SOCK_PACKET
	else if (strcmp(ptr, "SOCK_PACKET") == 0)
	    *tv = SOCK_PACKET;
#endif
	else
	    rb_raise(rb_eSocket, "Unknown socket type %s", ptr);
    }
    else {
	*tv = NUM2INT(type);
    }
}

static VALUE
sock_initialize(sock, domain, type, protocol)
    VALUE sock, domain, type, protocol;
{
    int fd;
    int d, t;

    rb_secure(3);
    setup_domain_and_type(domain, &d, type, &t);
    fd = ruby_socket(d, t, NUM2INT(protocol));
    if (fd < 0) rb_sys_fail("socket(2)");

    return init_sock(sock, fd);
}

static VALUE
sock_s_socketpair(klass, domain, type, protocol)
    VALUE klass, domain, type, protocol;
{
#if !defined(_WIN32) && !defined(__BEOS__) && !defined(__EMX__) && !defined(__QNXNTO__)
    int d, t, sp[2];

    setup_domain_and_type(domain, &d, type, &t);
  again:
    if (socketpair(d, t, NUM2INT(protocol), sp) < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    goto again;
	}
	rb_sys_fail("socketpair(2)");
    }

    return rb_assoc_new(init_sock(rb_obj_alloc(klass), sp[0]),
			init_sock(rb_obj_alloc(klass), sp[1]));
#else
    rb_notimplement();
#endif
}

#ifdef HAVE_SYS_UN_H
static VALUE
unix_s_socketpair(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE domain, type, protocol;
    domain = INT2FIX(PF_UNIX);

    rb_scan_args(argc, argv, "02", &type, &protocol);
    if (argc == 0)
	type = INT2FIX(SOCK_STREAM);
    if (argc <= 1)
	protocol = INT2FIX(0);

    return sock_s_socketpair(klass, domain, type, protocol);
}
#endif

static VALUE
sock_connect(sock, addr)
    VALUE sock, addr;
{
    OpenFile *fptr;
    int fd;

    StringValue(addr);
    rb_str_modify(addr);

    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
    if (ruby_connect(fd, (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len, 0) < 0) {
	rb_sys_fail("connect(2)");
    }

    return INT2FIX(0);
}

static VALUE
sock_bind(sock, addr)
    VALUE sock, addr;
{
    OpenFile *fptr;

    StringValue(addr);
    rb_str_modify(addr);

    GetOpenFile(sock, fptr);
    if (bind(fileno(fptr->f), (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len) < 0)
	rb_sys_fail("bind(2)");

    return INT2FIX(0);
}

static VALUE
sock_listen(sock, log)
    VALUE sock, log;
{
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(sock, fptr);
    if (listen(fileno(fptr->f), NUM2INT(log)) < 0)
	rb_sys_fail("listen(2)");

    return INT2FIX(0);
}

static VALUE
sock_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_SOCKET);
}

static VALUE
sock_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    VALUE sock2;
    char buf[1024];
    socklen_t len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept(rb_cSocket,fileno(fptr->f),(struct sockaddr*)buf,&len);

    return rb_assoc_new(sock2, rb_str_new(buf, len));
}

static VALUE
sock_sysaccept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    VALUE sock2;
    char buf[1024];
    socklen_t len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept(0,fileno(fptr->f),(struct sockaddr*)buf,&len);

    return rb_assoc_new(sock2, rb_str_new(buf, len));
}

#ifdef HAVE_GETHOSTNAME
static VALUE
sock_gethostname(obj)
    VALUE obj;
{
    char buf[1024];

    rb_secure(3);
    if (gethostname(buf, (int)sizeof buf - 1) < 0)
	rb_sys_fail("gethostname");

    buf[sizeof buf - 1] = '\0';
    return rb_str_new2(buf);
}
#else
#ifdef HAVE_UNAME

#include <sys/utsname.h>

static VALUE
sock_gethostname(obj)
    VALUE obj;
{
    struct utsname un;

    rb_secure(3);
    uname(&un);
    return rb_str_new2(un.nodename);
}
#else
static VALUE
sock_gethostname(obj)
    VALUE obj;
{
    rb_notimplement();
}
#endif
#endif

static VALUE
make_addrinfo(res0)
    struct addrinfo *res0;
{
    VALUE base, ary;
    struct addrinfo *res;

    if (res0 == NULL) {
	rb_raise(rb_eSocket, "host not found");
    }
    base = rb_ary_new();
    for (res = res0; res; res = res->ai_next) {
	ary = ipaddr(res->ai_addr, do_not_reverse_lookup);
	if (res->ai_canonname) {
	    RARRAY(ary)->ptr[2] = rb_str_new2(res->ai_canonname);
	}
	rb_ary_push(ary, INT2FIX(res->ai_family));
	rb_ary_push(ary, INT2FIX(res->ai_socktype));
	rb_ary_push(ary, INT2FIX(res->ai_protocol));
	rb_ary_push(base, ary);
    }
    return base;
}

VALUE
sock_sockaddr(addr, len)
    struct sockaddr *addr;
    size_t len;
{
    return rb_str_new((char*)addr, len);
}

static VALUE
sock_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    rb_secure(3);
    return make_hostent(host, sock_addrinfo(host, Qnil, SOCK_STREAM, AI_CANONNAME), sock_sockaddr);
}

static VALUE
sock_s_gethostbyaddr(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE addr, type;
    struct hostent *h;
    struct sockaddr *sa;
    char **pch;
    VALUE ary, names;
    int t = AF_INET;

    rb_scan_args(argc, argv, "11", &addr, &type);
    sa = (struct sockaddr*)StringValuePtr(addr);
    if (!NIL_P(type)) {
	t = NUM2INT(type);
    }
#ifdef INET6
    else if (RSTRING(addr)->len == 16) {
	t = AF_INET6;
    }
#endif
    h = gethostbyaddr((char*)RSTRING(addr)->ptr, RSTRING(addr)->len, t);
    if (h == NULL) {
#ifdef HAVE_HSTRERROR
	extern int h_errno;
	rb_raise(rb_eSocket, "%s", (char*)hstrerror(h_errno));
#else
	rb_raise(rb_eSocket, "host not found");
#endif
    }
    ary = rb_ary_new();
    rb_ary_push(ary, rb_str_new2(h->h_name));
    names = rb_ary_new();
    rb_ary_push(ary, names);
    if (h->h_aliases != NULL) {
	for (pch = h->h_aliases; *pch; pch++) {
	    rb_ary_push(names, rb_str_new2(*pch));
	}
    }
    rb_ary_push(ary, INT2NUM(h->h_addrtype));
#ifdef h_addr
    for (pch = h->h_addr_list; *pch; pch++) {
	rb_ary_push(ary, rb_str_new(*pch, h->h_length));
    }
#else
    rb_ary_push(ary, rb_str_new(h->h_addr, h->h_length));
#endif

    return ary;
}

static VALUE
sock_s_getservbyaname(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE service, protocol;
    char *proto;
    struct servent *sp;
    int port;

    rb_scan_args(argc, argv, "11", &service, &protocol);
    if (NIL_P(protocol)) proto = "tcp";
    else proto = StringValuePtr(protocol);

    StringValue(service);
    sp = getservbyname((char*)RSTRING(service)->ptr, proto);
    if (sp) {
	port = ntohs(sp->s_port);
    }
    else {
	char *s = RSTRING(service)->ptr;
	char *end;

	port = strtoul(s, &end, 0);
	if (*end != '\0') {
	    rb_raise(rb_eSocket, "no such service %s/%s", s, proto);
	}
    }
    return INT2FIX(port);
}

static VALUE
sock_s_getaddrinfo(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE host, port, family, socktype, protocol, flags, ret;
    char hbuf[1024], pbuf[1024];
    char *hptr, *pptr, *ap;
    struct addrinfo hints, *res;
    int error;

    host = port = family = socktype = protocol = flags = Qnil;
    rb_scan_args(argc, argv, "24", &host, &port, &family, &socktype, &protocol, &flags);
    if (NIL_P(host)) {
	hptr = NULL;
    }
    else {
	strncpy(hbuf, StringValuePtr(host), sizeof(hbuf));
	hbuf[sizeof(hbuf) - 1] = '\0';
	hptr = hbuf;
    }
    if (NIL_P(port)) {
	pptr = NULL;
    }
    else if (FIXNUM_P(port)) {
	snprintf(pbuf, sizeof(pbuf), "%ld", FIX2LONG(port));
	pptr = pbuf;
    }
    else {
	strncpy(pbuf, StringValuePtr(port), sizeof(pbuf));
	pbuf[sizeof(pbuf) - 1] = '\0';
	pptr = pbuf;
    }

    MEMZERO(&hints, struct addrinfo, 1);
    if (NIL_P(family)) {
	hints.ai_family = PF_UNSPEC;
    }
    else if (FIXNUM_P(family)) {
	hints.ai_family = FIX2INT(family);
    }
    else if ((ap = StringValuePtr(family)) != 0) {
	if (strcmp(ap, "AF_INET") == 0) {
	    hints.ai_family = PF_INET;
	}
#ifdef INET6
	else if (strcmp(ap, "AF_INET6") == 0) {
	    hints.ai_family = PF_INET6;
	}
#endif
    }

    if (!NIL_P(socktype)) {
	hints.ai_socktype = NUM2INT(socktype);
    }
    if (!NIL_P(protocol)) {
	hints.ai_protocol = NUM2INT(protocol);
    }
    if (!NIL_P(flags)) {
	hints.ai_flags = NUM2INT(flags);
    }
    error = getaddrinfo(hptr, pptr, &hints, &res);
    if (error) {
	raise_socket_error("getaddrinfo", error);
    }

    ret = make_addrinfo(res);
    freeaddrinfo(res);
    return ret;
}

static VALUE
sock_s_getnameinfo(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE sa, af = Qnil, host = Qnil, port = Qnil, flags;
    char *hptr, *pptr;
    char hbuf[1024], pbuf[1024];
    int fl;
    struct addrinfo hints, *res = NULL, *r;
    int error;
    struct sockaddr_storage ss;
    struct sockaddr *sap;
    char *ap;

    sa = flags = Qnil;
    rb_scan_args(argc, argv, "11", &sa, &flags);

    fl = 0;
    if (!NIL_P(flags)) {
	fl = NUM2INT(flags);
    }
    if (TYPE(sa) == T_STRING) {
	if (sizeof(ss) < RSTRING(sa)->len) {
	    rb_raise(rb_eTypeError, "sockaddr length too big");
	}
	memcpy(&ss, RSTRING(sa)->ptr, RSTRING(sa)->len);
	if (RSTRING(sa)->len != SA_LEN((struct sockaddr*)&ss)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
	sap = (struct sockaddr*)&ss;
    }
    else if (TYPE(sa) == T_ARRAY) {
	MEMZERO(&hints, struct addrinfo, 1);
	if (RARRAY(sa)->len == 3) {
	    af = RARRAY(sa)->ptr[0];
	    port = RARRAY(sa)->ptr[1];
	    host = RARRAY(sa)->ptr[2];
	}
	else if (RARRAY(sa)->len >= 4) {
	    af = RARRAY(sa)->ptr[0];
	    port = RARRAY(sa)->ptr[1];
	    host = RARRAY(sa)->ptr[3];
	    if (NIL_P(host)) {
		host = RARRAY(sa)->ptr[2];
	    }
	    else {
		/*
		 * 4th element holds numeric form, don't resolve.
		 * see ipaddr().
		 */
		hints.ai_flags |= AI_NUMERICHOST;
	    }
	}
	else {
	    rb_raise(rb_eArgError, "array size should be 3 or 4, %ld given",
		     RARRAY(sa)->len);
	}
	/* host */
	if (NIL_P(host)) {
	    hptr = NULL;
	}
	else {
	    strncpy(hbuf, StringValuePtr(host), sizeof(hbuf));
	    hbuf[sizeof(hbuf) - 1] = '\0';
	    hptr = hbuf;
	}
	/* port */
	if (NIL_P(port)) {
	    strcpy(pbuf, "0");
	    pptr = NULL;
	}
	else if (FIXNUM_P(port)) {
	    snprintf(pbuf, sizeof(pbuf), "%ld", NUM2LONG(port));
	    pptr = pbuf;
	}
	else {
	    strncpy(pbuf, StringValuePtr(port), sizeof(pbuf));
	    pbuf[sizeof(pbuf) - 1] = '\0';
	    pptr = pbuf;
	}
	hints.ai_socktype = (fl & NI_DGRAM) ? SOCK_DGRAM : SOCK_STREAM;
	/* af */
	if (NIL_P(af)) {
	    hints.ai_family = PF_UNSPEC;
	}
	else if (FIXNUM_P(af)) {
	    hints.ai_family = FIX2INT(af);
	}
	else if ((ap = StringValuePtr(af)) != 0) {
	    if (strcmp(ap, "AF_INET") == 0) {
		hints.ai_family = PF_INET;
	    }
#ifdef INET6
	    else if (strcmp(ap, "AF_INET6") == 0) {
		hints.ai_family = PF_INET6;
	    }
#endif
	}
	error = getaddrinfo(hptr, pptr, &hints, &res);
	if (error) goto error_exit_addr;
	sap = res->ai_addr;
    }
    else {
	rb_raise(rb_eTypeError, "expecting String or Array");
    }

    error = getnameinfo(sap, SA_LEN(sap), hbuf, sizeof(hbuf),
			pbuf, sizeof(pbuf), fl);
    if (error) goto error_exit_name;
    if (res) {
	for (r = res->ai_next; r; r = r->ai_next) {
	    char hbuf2[1024], pbuf2[1024];

	    sap = r->ai_addr;
	    error = getnameinfo(sap, SA_LEN(sap), hbuf2, sizeof(hbuf2),
				pbuf2, sizeof(pbuf2), fl);
	    if (error) goto error_exit_name;
	    if (strcmp(hbuf, hbuf2) != 0|| strcmp(pbuf, pbuf2) != 0) {
		freeaddrinfo(res);
		rb_raise(rb_eSocket, "sockaddr resolved to multiple nodename");
	    }
	}
	freeaddrinfo(res);
    }
    return rb_assoc_new(rb_str_new2(hbuf), rb_str_new2(pbuf));

  error_exit_addr:
    if (res) freeaddrinfo(res);
    raise_socket_error("getaddrinfo", error);

  error_exit_name:
    if (res) freeaddrinfo(res);
    raise_socket_error("getnameinfo", error);
}

static VALUE
sock_s_pack_sockaddr_in(self, port, host)
    VALUE self, port, host;
{
    struct addrinfo *res = sock_addrinfo(host, port, 0, 0);
    VALUE addr = rb_str_new((char*)res->ai_addr, res->ai_addrlen);

    freeaddrinfo(res);
    OBJ_INFECT(addr, port);
    OBJ_INFECT(addr, host);

    return addr;
}

static VALUE
sock_s_unpack_sockaddr_in(self, addr)
    VALUE self, addr;
{
    struct sockaddr_in * sockaddr;
    VALUE host;

    sockaddr = (struct sockaddr_in*)StringValuePtr(addr);
    host = make_ipaddr((struct sockaddr*)sockaddr);
    OBJ_INFECT(host, addr);
    return rb_assoc_new(INT2NUM(ntohs(sockaddr->sin_port)), host);
}

#ifdef HAVE_SYS_UN_H
static VALUE
sock_s_pack_sockaddr_un(self, path)
    VALUE self, path;
{
    struct sockaddr_un sockaddr;
    VALUE addr;

    MEMZERO(&sockaddr, struct sockaddr_un, 1);
    sockaddr.sun_family = AF_UNIX;
    strncpy(sockaddr.sun_path, StringValuePtr(path), sizeof(sockaddr.sun_path)-1);
    addr = rb_str_new((char*)&sockaddr, sizeof(sockaddr));
    OBJ_INFECT(addr, path);

    return addr;
}

static VALUE
sock_s_unpack_sockaddr_un(self, addr)
    VALUE self, addr;
{
    struct sockaddr_un * sockaddr;
    VALUE path;

    sockaddr = (struct sockaddr_un*)StringValuePtr(addr);
    if (RSTRING(addr)->len != sizeof(struct sockaddr_un)) {
	rb_raise(rb_eTypeError, "sockaddr_un size differs - %ld required; %d given",
		 RSTRING(addr)->len, sizeof(struct sockaddr_un));
    }
    /* xxx: should I check against sun_path size? */
    path = rb_str_new2(sockaddr->sun_path);
    OBJ_INFECT(path, addr);
    return path;
}
#endif

static VALUE mConst;

static void
sock_define_const(name, value)
    char *name;
    int value;
{
    rb_define_const(rb_cSocket, name, INT2FIX(value));
    rb_define_const(mConst, name, INT2FIX(value));
}

void
Init_socket()
{
    rb_eSocket = rb_define_class("SocketError", rb_eStandardError);

    rb_cBasicSocket = rb_define_class("BasicSocket", rb_cIO);
    rb_undef_method(rb_cBasicSocket, "initialize");

    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup",
			       bsock_do_not_rev_lookup, 0);
    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup=",
			       bsock_do_not_rev_lookup_set, 1);
    rb_define_singleton_method(rb_cBasicSocket, "for_fd", bsock_s_for_fd, 1);

    rb_define_method(rb_cBasicSocket, "close_read", bsock_close_read, 0);
    rb_define_method(rb_cBasicSocket, "close_write", bsock_close_write, 0);
    rb_define_method(rb_cBasicSocket, "shutdown", bsock_shutdown, -1);
    rb_define_method(rb_cBasicSocket, "setsockopt", bsock_setsockopt, 3);
    rb_define_method(rb_cBasicSocket, "getsockopt", bsock_getsockopt, 2);
    rb_define_method(rb_cBasicSocket, "getsockname", bsock_getsockname, 0);
    rb_define_method(rb_cBasicSocket, "getpeername", bsock_getpeername, 0);
    rb_define_method(rb_cBasicSocket, "send", bsock_send, -1);
    rb_define_method(rb_cBasicSocket, "recv", bsock_recv, -1);
    rb_define_method(rb_cBasicSocket, "do_not_reverse_lookup", bsock_do_not_reverse_lookup, 0);
    rb_define_method(rb_cBasicSocket, "do_not_reverse_lookup=", bsock_do_not_reverse_lookup_set, 1);

    rb_cIPSocket = rb_define_class("IPSocket", rb_cBasicSocket);
    rb_define_global_const("IPsocket", rb_cIPSocket);
    rb_define_method(rb_cIPSocket, "addr", ip_addr, 0);
    rb_define_method(rb_cIPSocket, "peeraddr", ip_peeraddr, 0);
    rb_define_method(rb_cIPSocket, "recvfrom", ip_recvfrom, -1);
    rb_define_singleton_method(rb_cIPSocket, "getaddress", ip_s_getaddress, 1);

    rb_cTCPSocket = rb_define_class("TCPSocket", rb_cIPSocket);
    rb_define_global_const("TCPsocket", rb_cTCPSocket);
    rb_define_singleton_method(rb_cTCPSocket, "gethostbyname", tcp_s_gethostbyname, 1);
    rb_define_method(rb_cTCPSocket, "initialize", tcp_init, -1);

#ifdef SOCKS
    rb_cSOCKSSocket = rb_define_class("SOCKSSocket", rb_cTCPSocket);
    rb_define_global_const("SOCKSsocket", rb_cSOCKSSocket);
    rb_define_method(rb_cSOCKSSocket, "initialize", socks_init, 2);
#ifdef SOCKS5
    rb_define_method(rb_cSOCKSSocket, "close", socks_s_close, 0);
#endif
#endif

    rb_cTCPServer = rb_define_class("TCPServer", rb_cTCPSocket);
    rb_define_global_const("TCPserver", rb_cTCPServer);
    rb_define_method(rb_cTCPServer, "accept", tcp_accept, 0);
    rb_define_method(rb_cTCPServer, "sysaccept", tcp_sysaccept, 0);
    rb_define_method(rb_cTCPServer, "initialize", tcp_svr_init, -1);
    rb_define_method(rb_cTCPServer, "listen", sock_listen, 1);

    rb_cUDPSocket = rb_define_class("UDPSocket", rb_cIPSocket);
    rb_define_global_const("UDPsocket", rb_cUDPSocket);
    rb_define_method(rb_cUDPSocket, "initialize", udp_init, -1);
    rb_define_method(rb_cUDPSocket, "connect", udp_connect, 2);
    rb_define_method(rb_cUDPSocket, "bind", udp_bind, 2);
    rb_define_method(rb_cUDPSocket, "send", udp_send, -1);

#ifdef HAVE_SYS_UN_H
    rb_cUNIXSocket = rb_define_class("UNIXSocket", rb_cBasicSocket);
    rb_define_global_const("UNIXsocket", rb_cUNIXSocket);
    rb_define_method(rb_cUNIXSocket, "initialize", unix_init, 1);
    rb_define_method(rb_cUNIXSocket, "path", unix_path, 0);
    rb_define_method(rb_cUNIXSocket, "addr", unix_addr, 0);
    rb_define_method(rb_cUNIXSocket, "peeraddr", unix_peeraddr, 0);
    rb_define_method(rb_cUNIXSocket, "recvfrom", unix_recvfrom, -1);
    rb_define_method(rb_cUNIXSocket, "send_io", unix_send_io, 1);
    rb_define_method(rb_cUNIXSocket, "recv_io", unix_recv_io, -1);
    rb_define_singleton_method(rb_cUNIXSocket, "socketpair", unix_s_socketpair, -1);
    rb_define_singleton_method(rb_cUNIXSocket, "pair", unix_s_socketpair, -1);

    rb_cUNIXServer = rb_define_class("UNIXServer", rb_cUNIXSocket);
    rb_define_global_const("UNIXserver", rb_cUNIXServer);
    rb_define_method(rb_cUNIXServer, "initialize", unix_svr_init, 1);
    rb_define_method(rb_cUNIXServer, "accept", unix_accept, 0);
    rb_define_method(rb_cUNIXServer, "sysaccept", unix_sysaccept, 0);
    rb_define_method(rb_cUNIXServer, "listen", sock_listen, 1);
#endif

    rb_cSocket = rb_define_class("Socket", rb_cBasicSocket);

    rb_define_method(rb_cSocket, "initialize", sock_initialize, 3);
    rb_define_method(rb_cSocket, "connect", sock_connect, 1);
    rb_define_method(rb_cSocket, "bind", sock_bind, 1);
    rb_define_method(rb_cSocket, "listen", sock_listen, 1);
    rb_define_method(rb_cSocket, "accept", sock_accept, 0);
    rb_define_method(rb_cSocket, "sysaccept", sock_sysaccept, 0);

    rb_define_method(rb_cSocket, "recvfrom", sock_recvfrom, -1);

    rb_define_singleton_method(rb_cSocket, "socketpair", sock_s_socketpair, 3);
    rb_define_singleton_method(rb_cSocket, "pair", sock_s_socketpair, 3);
    rb_define_singleton_method(rb_cSocket, "gethostname", sock_gethostname, 0);
    rb_define_singleton_method(rb_cSocket, "gethostbyname", sock_s_gethostbyname, 1);
    rb_define_singleton_method(rb_cSocket, "gethostbyaddr", sock_s_gethostbyaddr, -1);
    rb_define_singleton_method(rb_cSocket, "getservbyname", sock_s_getservbyaname, -1);
    rb_define_singleton_method(rb_cSocket, "getaddrinfo", sock_s_getaddrinfo, -1);
    rb_define_singleton_method(rb_cSocket, "getnameinfo", sock_s_getnameinfo, -1);
    rb_define_singleton_method(rb_cSocket, "sockaddr_in", sock_s_pack_sockaddr_in, 2);
    rb_define_singleton_method(rb_cSocket, "pack_sockaddr_in", sock_s_pack_sockaddr_in, 2);
    rb_define_singleton_method(rb_cSocket, "unpack_sockaddr_in", sock_s_unpack_sockaddr_in, 1);
#ifdef HAVE_SYS_UN_H
    rb_define_singleton_method(rb_cSocket, "sockaddr_un", sock_s_pack_sockaddr_un, 1);
    rb_define_singleton_method(rb_cSocket, "pack_sockaddr_un", sock_s_pack_sockaddr_un, 1);
    rb_define_singleton_method(rb_cSocket, "unpack_sockaddr_un", sock_s_unpack_sockaddr_un, 1);
#endif

    /* constants */
    mConst = rb_define_module_under(rb_cSocket, "Constants");
    sock_define_const("SOCK_STREAM", SOCK_STREAM);
    sock_define_const("SOCK_DGRAM", SOCK_DGRAM);
#ifdef SOCK_RAW
    sock_define_const("SOCK_RAW", SOCK_RAW);
#endif
#ifdef SOCK_RDM
    sock_define_const("SOCK_RDM", SOCK_RDM);
#endif
#ifdef SOCK_SEQPACKET
    sock_define_const("SOCK_SEQPACKET", SOCK_SEQPACKET);
#endif
#ifdef SOCK_PACKET
    sock_define_const("SOCK_PACKET", SOCK_PACKET);
#endif

    sock_define_const("AF_INET", AF_INET);
#ifdef PF_INET
    sock_define_const("PF_INET", PF_INET);
#endif
#ifdef AF_UNIX
    sock_define_const("AF_UNIX", AF_UNIX);
    sock_define_const("PF_UNIX", PF_UNIX);
#endif
#ifdef AF_AX25
    sock_define_const("AF_AX25", AF_AX25);
    sock_define_const("PF_AX25", PF_AX25);
#endif
#ifdef AF_IPX
    sock_define_const("AF_IPX", AF_IPX);
    sock_define_const("PF_IPX", PF_IPX);
#endif
#ifdef AF_APPLETALK
    sock_define_const("AF_APPLETALK", AF_APPLETALK);
    sock_define_const("PF_APPLETALK", PF_APPLETALK);
#endif
#ifdef AF_UNSPEC
    sock_define_const("AF_UNSPEC", AF_UNSPEC);
    sock_define_const("PF_UNSPEC", PF_UNSPEC);
#endif
#ifdef INET6
    sock_define_const("AF_INET6", AF_INET6);
#endif
#ifdef INET6
    sock_define_const("PF_INET6", PF_INET6);
#endif

    sock_define_const("MSG_OOB", MSG_OOB);
#ifdef MSG_PEEK
    sock_define_const("MSG_PEEK", MSG_PEEK);
#endif
#ifdef MSG_DONTROUTE
    sock_define_const("MSG_DONTROUTE", MSG_DONTROUTE);
#endif

    sock_define_const("SOL_SOCKET", SOL_SOCKET);
#ifdef SOL_IP
    sock_define_const("SOL_IP", SOL_IP);
#endif
#ifdef SOL_IPX
    sock_define_const("SOL_IPX", SOL_IPX);
#endif
#ifdef SOL_AX25
    sock_define_const("SOL_AX25", SOL_AX25);
#endif
#ifdef SOL_ATALK
    sock_define_const("SOL_ATALK", SOL_ATALK);
#endif
#ifdef SOL_TCP
    sock_define_const("SOL_TCP", SOL_TCP);
#endif
#ifdef SOL_UDP
    sock_define_const("SOL_UDP", SOL_UDP);
#endif

#ifdef	IPPROTO_IP
    sock_define_const("IPPROTO_IP", IPPROTO_IP);
#else
    sock_define_const("IPPROTO_IP", 0);
#endif
#ifdef	IPPROTO_ICMP
    sock_define_const("IPPROTO_ICMP", IPPROTO_ICMP);
#else
    sock_define_const("IPPROTO_ICMP", 1);
#endif
#ifdef	IPPROTO_IGMP
    sock_define_const("IPPROTO_IGMP", IPPROTO_IGMP);
#endif
#ifdef	IPPROTO_GGP
    sock_define_const("IPPROTO_GGP", IPPROTO_GGP);
#endif
#ifdef	IPPROTO_TCP
    sock_define_const("IPPROTO_TCP", IPPROTO_TCP);
#else
    sock_define_const("IPPROTO_TCP", 6);
#endif
#ifdef	IPPROTO_EGP
    sock_define_const("IPPROTO_EGP", IPPROTO_EGP);
#endif
#ifdef	IPPROTO_PUP
    sock_define_const("IPPROTO_PUP", IPPROTO_PUP);
#endif
#ifdef	IPPROTO_UDP
    sock_define_const("IPPROTO_UDP", IPPROTO_UDP);
#else
    sock_define_const("IPPROTO_UDP", 17);
#endif
#ifdef	IPPROTO_IDP
    sock_define_const("IPPROTO_IDP", IPPROTO_IDP);
#endif
#ifdef	IPPROTO_HELLO
    sock_define_const("IPPROTO_HELLO", IPPROTO_HELLO);
#endif
#ifdef	IPPROTO_ND
    sock_define_const("IPPROTO_ND", IPPROTO_ND);
#endif
#ifdef	IPPROTO_TP
    sock_define_const("IPPROTO_TP", IPPROTO_TP);
#endif
#ifdef	IPPROTO_XTP
    sock_define_const("IPPROTO_XTP", IPPROTO_XTP);
#endif
#ifdef	IPPROTO_EON
    sock_define_const("IPPROTO_EON", IPPROTO_EON);
#endif
#ifdef	IPPROTO_BIP
    sock_define_const("IPPROTO_BIP", IPPROTO_BIP);
#endif
/**/
#ifdef	IPPROTO_RAW
    sock_define_const("IPPROTO_RAW", IPPROTO_RAW);
#else
    sock_define_const("IPPROTO_RAW", 255);
#endif
#ifdef	IPPROTO_MAX
    sock_define_const("IPPROTO_MAX", IPPROTO_MAX);
#endif

	/* Some port configuration */
#ifdef	IPPORT_RESERVED
    sock_define_const("IPPORT_RESERVED", IPPORT_RESERVED);
#else
    sock_define_const("IPPORT_RESERVED", 1024);
#endif
#ifdef	IPPORT_USERRESERVED
    sock_define_const("IPPORT_USERRESERVED", IPPORT_USERRESERVED);
#else
    sock_define_const("IPPORT_USERRESERVED", 5000);
#endif
	/* Some reserved IP v.4 addresses */
#ifdef	INADDR_ANY
    sock_define_const("INADDR_ANY", INADDR_ANY);
#else
    sock_define_const("INADDR_ANY", 0x00000000);
#endif
#ifdef	INADDR_BROADCAST
    sock_define_const("INADDR_BROADCAST", INADDR_BROADCAST);
#else
    sock_define_const("INADDR_BROADCAST", 0xffffffff);
#endif
#ifdef	INADDR_LOOPBACK
    sock_define_const("INADDR_LOOPBACK", INADDR_LOOPBACK);
#else
    sock_define_const("INADDR_LOOPBACK", 0x7F000001);
#endif
#ifdef	INADDR_UNSPEC_GROUP
    sock_define_const("INADDR_UNSPEC_GROUP", INADDR_UNSPEC_GROUP);
#else
    sock_define_const("INADDR_UNSPEC_GROUP", 0xe0000000);
#endif
#ifdef	INADDR_ALLHOSTS_GROUP
    sock_define_const("INADDR_ALLHOSTS_GROUP", INADDR_ALLHOSTS_GROUP);
#else
    sock_define_const("INADDR_ALLHOSTS_GROUP", 0xe0000001);
#endif
#ifdef	INADDR_MAX_LOCAL_GROUP
    sock_define_const("INADDR_MAX_LOCAL_GROUP", INADDR_MAX_LOCAL_GROUP);
#else
    sock_define_const("INADDR_MAX_LOCAL_GROUP", 0xe00000ff);
#endif
#ifdef	INADDR_NONE
    sock_define_const("INADDR_NONE", INADDR_NONE);
#else
    sock_define_const("INADDR_NONE", 0xffffffff);
#endif
	/* IP [gs]etsockopt options */
#ifdef	IP_OPTIONS
    sock_define_const("IP_OPTIONS", IP_OPTIONS);
#endif
#ifdef	IP_HDRINCL
    sock_define_const("IP_HDRINCL", IP_HDRINCL);
#endif
#ifdef	IP_TOS
    sock_define_const("IP_TOS", IP_TOS);
#endif
#ifdef	IP_TTL
    sock_define_const("IP_TTL", IP_TTL);
#endif
#ifdef	IP_RECVOPTS
    sock_define_const("IP_RECVOPTS", IP_RECVOPTS);
#endif
#ifdef	IP_RECVRETOPTS
    sock_define_const("IP_RECVRETOPTS", IP_RECVRETOPTS);
#endif
#ifdef	IP_RECVDSTADDR
    sock_define_const("IP_RECVDSTADDR", IP_RECVDSTADDR);
#endif
#ifdef	IP_RETOPTS
    sock_define_const("IP_RETOPTS", IP_RETOPTS);
#endif
#ifdef	IP_MULTICAST_IF
    sock_define_const("IP_MULTICAST_IF", IP_MULTICAST_IF);
#endif
#ifdef	IP_MULTICAST_TTL
    sock_define_const("IP_MULTICAST_TTL", IP_MULTICAST_TTL);
#endif
#ifdef	IP_MULTICAST_LOOP
    sock_define_const("IP_MULTICAST_LOOP", IP_MULTICAST_LOOP);
#endif
#ifdef	IP_ADD_MEMBERSHIP
    sock_define_const("IP_ADD_MEMBERSHIP", IP_ADD_MEMBERSHIP);
#endif
#ifdef	IP_DROP_MEMBERSHIP
    sock_define_const("IP_DROP_MEMBERSHIP", IP_DROP_MEMBERSHIP);
#endif
#ifdef	IP_DEFAULT_MULTICAST_TTL
    sock_define_const("IP_DEFAULT_MULTICAST_TTL", IP_DEFAULT_MULTICAST_TTL);
#endif
#ifdef	IP_DEFAULT_MULTICAST_LOOP
    sock_define_const("IP_DEFAULT_MULTICAST_LOOP", IP_DEFAULT_MULTICAST_LOOP);
#endif
#ifdef	IP_MAX_MEMBERSHIPS
    sock_define_const("IP_MAX_MEMBERSHIPS", IP_MAX_MEMBERSHIPS);
#endif
#ifdef SO_DEBUG
    sock_define_const("SO_DEBUG", SO_DEBUG);
#endif
    sock_define_const("SO_REUSEADDR", SO_REUSEADDR);
#ifdef SO_TYPE
    sock_define_const("SO_TYPE", SO_TYPE);
#endif
#ifdef SO_ERROR
    sock_define_const("SO_ERROR", SO_ERROR);
#endif
#ifdef SO_DONTROUTE
    sock_define_const("SO_DONTROUTE", SO_DONTROUTE);
#endif
#ifdef SO_BROADCAST
    sock_define_const("SO_BROADCAST", SO_BROADCAST);
#endif
#ifdef SO_SNDBUF
    sock_define_const("SO_SNDBUF", SO_SNDBUF);
#endif
#ifdef SO_RCVBUF
    sock_define_const("SO_RCVBUF", SO_RCVBUF);
#endif
#ifdef SO_KEEPALIVE
    sock_define_const("SO_KEEPALIVE", SO_KEEPALIVE);
#endif
#ifdef SO_OOBINLINE
    sock_define_const("SO_OOBINLINE", SO_OOBINLINE);
#endif
#ifdef SO_NO_CHECK
    sock_define_const("SO_NO_CHECK", SO_NO_CHECK);
#endif
#ifdef SO_PRIORITY
    sock_define_const("SO_PRIORITY", SO_PRIORITY);
#endif
#ifdef SO_LINGER
    sock_define_const("SO_LINGER", SO_LINGER);
#endif
#ifdef SO_PASSCRED
    sock_define_const("SO_PASSCRED", SO_PASSCRED);
#endif
#ifdef SO_PEERCRED
    sock_define_const("SO_PEERCRED", SO_PEERCRED);
#endif
#ifdef SO_RCVLOWAT
    sock_define_const("SO_RCVLOWAT", SO_RCVLOWAT);
#endif
#ifdef SO_SNDLOWAT
    sock_define_const("SO_SNDLOWAT", SO_SNDLOWAT);
#endif
#ifdef SO_RCVTIMEO
    sock_define_const("SO_RCVTIMEO", SO_RCVTIMEO);
#endif
#ifdef SO_SNDTIMEO
    sock_define_const("SO_SNDTIMEO", SO_SNDTIMEO);
#endif

#ifdef SO_SECURITY_AUTHENTICATION
    sock_define_const("SO_SECURITY_AUTHENTICATION", SO_SECURITY_AUTHENTICATION);
#endif
#ifdef SO_SECURITY_ENCRYPTION_TRANSPORT
    sock_define_const("SO_SECURITY_ENCRYPTION_TRANSPORT", SO_SECURITY_ENCRYPTION_TRANSPORT);
#endif
#ifdef SO_SECURITY_ENCRYPTION_NETWORK
    sock_define_const("SO_SECURITY_ENCRYPTION_NETWORK", SO_SECURITY_ENCRYPTION_NETWORK);
#endif

#ifdef SO_BINDTODEVICE
    sock_define_const("SO_BINDTODEVICE", SO_BINDTODEVICE);
#endif
#ifdef SO_ATTACH_FILTER
    sock_define_const("SO_ATTACH_FILTER", SO_ATTACH_FILTER);
#endif
#ifdef SO_DETACH_FILTER
    sock_define_const("SO_DETACH_FILTER", SO_DETACH_FILTER);
#endif
#ifdef SO_PEERNAME
    sock_define_const("SO_PEERNAME", SO_PEERNAME);
#endif
#ifdef SO_TIMESTAMP
    sock_define_const("SO_TIMESTAMP", SO_TIMESTAMP);
#endif

#ifdef SOPRI_INTERACTIVE
    sock_define_const("SOPRI_INTERACTIVE", SOPRI_INTERACTIVE);
#endif
#ifdef SOPRI_NORMAL
    sock_define_const("SOPRI_NORMAL", SOPRI_NORMAL);
#endif
#ifdef SOPRI_BACKGROUND
    sock_define_const("SOPRI_BACKGROUND", SOPRI_BACKGROUND);
#endif

#ifdef IPX_TYPE
    sock_define_const("IPX_TYPE", IPX_TYPE);
#endif

#ifdef TCP_NODELAY
    sock_define_const("TCP_NODELAY", TCP_NODELAY);
#endif
#ifdef TCP_MAXSEG
    sock_define_const("TCP_MAXSEG", TCP_MAXSEG);
#endif

#ifdef EAI_ADDRFAMILY
    sock_define_const("EAI_ADDRFAMILY", EAI_ADDRFAMILY);
#endif
#ifdef EAI_AGAIN
    sock_define_const("EAI_AGAIN", EAI_AGAIN);
#endif
#ifdef EAI_BADFLAGS
    sock_define_const("EAI_BADFLAGS", EAI_BADFLAGS);
#endif
#ifdef EAI_FAIL
    sock_define_const("EAI_FAIL", EAI_FAIL);
#endif
#ifdef EAI_FAMILY
    sock_define_const("EAI_FAMILY", EAI_FAMILY);
#endif
#ifdef EAI_MEMORY
    sock_define_const("EAI_MEMORY", EAI_MEMORY);
#endif
#ifdef EAI_NODATA
    sock_define_const("EAI_NODATA", EAI_NODATA);
#endif
#ifdef EAI_NONAME
    sock_define_const("EAI_NONAME", EAI_NONAME);
#endif
#ifdef EAI_SERVICE
    sock_define_const("EAI_SERVICE", EAI_SERVICE);
#endif
#ifdef EAI_SOCKTYPE
    sock_define_const("EAI_SOCKTYPE", EAI_SOCKTYPE);
#endif
#ifdef EAI_SYSTEM
    sock_define_const("EAI_SYSTEM", EAI_SYSTEM);
#endif
#ifdef EAI_BADHINTS
    sock_define_const("EAI_BADHINTS", EAI_BADHINTS);
#endif
#ifdef EAI_PROTOCOL
    sock_define_const("EAI_PROTOCOL", EAI_PROTOCOL);
#endif
#ifdef EAI_MAX
    sock_define_const("EAI_MAX", EAI_MAX);
#endif
#ifdef AI_PASSIVE
    sock_define_const("AI_PASSIVE", AI_PASSIVE);
#endif
#ifdef AI_CANONNAME
    sock_define_const("AI_CANONNAME", AI_CANONNAME);
#endif
#ifdef AI_NUMERICHOST
    sock_define_const("AI_NUMERICHOST", AI_NUMERICHOST);
#endif
#ifdef AI_MASK
    sock_define_const("AI_MASK", AI_MASK);
#endif
#ifdef AI_ALL
    sock_define_const("AI_ALL", AI_ALL);
#endif
#ifdef AI_V4MAPPED_CFG
    sock_define_const("AI_V4MAPPED_CFG", AI_V4MAPPED_CFG);
#endif
#ifdef AI_ADDRCONFIG
    sock_define_const("AI_ADDRCONFIG", AI_ADDRCONFIG);
#endif
#ifdef AI_V4MAPPED
    sock_define_const("AI_V4MAPPED", AI_V4MAPPED);
#endif
#ifdef AI_DEFAULT
    sock_define_const("AI_DEFAULT", AI_DEFAULT);
#endif
#ifdef NI_MAXHOST
    sock_define_const("NI_MAXHOST", NI_MAXHOST);
#endif
#ifdef NI_MAXSERV
    sock_define_const("NI_MAXSERV", NI_MAXSERV);
#endif
#ifdef NI_NOFQDN
    sock_define_const("NI_NOFQDN", NI_NOFQDN);
#endif
#ifdef NI_NUMERICHOST
    sock_define_const("NI_NUMERICHOST", NI_NUMERICHOST);
#endif
#ifdef NI_NAMEREQD
    sock_define_const("NI_NAMEREQD", NI_NAMEREQD);
#endif
#ifdef NI_NUMERICSERV
    sock_define_const("NI_NUMERICSERV", NI_NUMERICSERV);
#endif
#ifdef NI_DGRAM
    sock_define_const("NI_DGRAM", NI_DGRAM);
#endif
#ifdef SHUT_RD
    sock_define_const("SHUT_RD", SHUT_RD);
#else
    sock_define_const("SHUT_RD", 0);
#endif
#ifdef SHUT_WR
    sock_define_const("SHUT_WR", SHUT_WR);
#else
    sock_define_const("SHUT_WR", 1);
#endif
#ifdef SHUT_RDWR
    sock_define_const("SHUT_RDWR", SHUT_RDWR);
#else
    sock_define_const("SHUT_RDWR", 2);
#endif
}
