/************************************************

  socket.c -

  $Author$
  $Date$
  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include <stdio.h>
#include <sys/types.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef NT
#if defined(__BEOS__)
# include <net/socket.h>
#else
# include <sys/socket.h>
#endif
#include <netinet/in.h>
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
rb_getaddrinfo(nodename, servname, hints, res)
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
#define getaddrinfo(node,serv,hints,res) rb_getaddrinfo((node),(serv),(hints),(res))
#endif

#ifdef HAVE_CLOSESOCKET
#undef close
#define close closesocket
#endif

static VALUE
sock_new(class, fd)
    VALUE class;
    int fd;
{
    OpenFile *fp;
    NEWOBJ(sock, struct RFile);
    OBJSETUP(sock, class, T_FILE);

    MakeOpenFile(sock, fp);
    fp->f = rb_fdopen(fd, "r");
    fd = dup(fd);
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE;
    rb_io_synchronized(fp);

    return (VALUE)sock;
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
    if (fptr->f2 == 0) {
	return rb_io_close(sock);
    }
    rb_thread_fd_close(fileno(fptr->f));
    fptr->mode &= ~FMODE_READABLE;
    fclose(fptr->f);
    fptr->f = fptr->f2;
    fptr->f2 = 0;

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
    if (fptr->f2 == 0) {
	return rb_io_close(sock);
    }
    shutdown(fileno(fptr->f2), 1);
    fptr->mode &= ~FMODE_WRITABLE;
    fclose(fptr->f2);
    fptr->f2 = 0;

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
	v = rb_str2cstr(val, &vlen);
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
    VALUE msg, to;
    VALUE flags;
    OpenFile *fptr;
    FILE *f;
    int fd, n;
    char *m, *t;
    int mlen, tlen;

    rb_secure(4);
    rb_scan_args(argc, argv, "21", &msg, &flags, &to);

    GetOpenFile(sock, fptr);
    f = GetWriteFile(fptr);
    fd = fileno(f);
  retry:
    rb_thread_fd_writable(fd);
    m = rb_str2cstr(msg, &mlen);
    if (!NIL_P(to)) {
	t = rb_str2cstr(to, &tlen);
	n = sendto(fd, m, mlen, NUM2INT(flags),
		   (struct sockaddr*)t, tlen);
    }
    else {
	n = send(fd, m, mlen, NUM2INT(flags));
    }
    if (n < 0) {
	switch (errno) {
	  case EINTR:
	    rb_thread_schedule();
	    goto retry;
	}
	rb_sys_fail("send(2)");
    }
    return INT2FIX(n);
}

static VALUE ipaddr _((struct sockaddr *));
#ifdef HAVE_SYS_UN_H
static VALUE unixaddr _((struct sockaddr_un *));
#endif

enum sock_recv_type {
    RECV_RECV,			/* BasicSocket#recv(no from) */
    RECV_IP,			/* IPSocket#recvfrom */
    RECV_UNIX,			/* UNIXSocket#recvfrom */
    RECV_SOCKET,		/* Socket#recvfrom */
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

    slen = NUM2INT(len);
    str = rb_tainted_str_new(0, slen);

  retry:
    rb_thread_wait_fd(fd);
    TRAP_BEG;
    slen = recvfrom(fd, RSTRING(str)->ptr, slen, flags, (struct sockaddr*)buf, &alen);
    TRAP_END;

    if (slen < 0) {
	switch (errno) {
	  case EINTR:
	    rb_thread_schedule();
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
	return rb_assoc_new(str, ipaddr((struct sockaddr *)buf));
#ifdef HAVE_SYS_UN_H
      case RECV_UNIX:
	return rb_assoc_new(str, unixaddr((struct sockaddr_un *)buf));
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
{
    rb_secure(4);
    do_not_reverse_lookup = RTEST(val);
    return val;
}

static void
mkipaddr0(addr, buf, len)
    struct sockaddr *addr;
    char *buf;
    size_t len;
{
    int error;

    error = getnameinfo(addr, SA_LEN(addr), buf, len, NULL, 0, NI_NUMERICHOST);
    if (error) {
	rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
    }
}

static VALUE
mkipaddr(addr)
    struct sockaddr *addr;
{
    char buf[1024];

    mkipaddr0(addr, buf, sizeof(buf));
    return rb_str_new2(buf);
}

static void
mkinetaddr(host, buf, len)
    long host;
    char *buf;
    size_t len;
{
    struct sockaddr_in sin;

    MEMZERO(&sin, struct sockaddr_in, 1);
    sin.sin_family = AF_INET;
    SET_SIN_LEN(&sin, sizeof(sin));
    sin.sin_addr.s_addr = host;
    mkipaddr0((struct sockaddr *)&sin, buf, len);
}

static struct addrinfo*
ip_addrsetup(host, port)
    VALUE host, port;
{
    struct addrinfo hints, *res;
    char *hostp, *portp;
    int error;
    char hbuf[1024], pbuf[16];

    if (NIL_P(host)) {
	hostp = NULL;
    }
    else if (rb_obj_is_kind_of(host, rb_cInteger)) {
	long i = NUM2LONG(host);

	mkinetaddr(htonl(i), hbuf, sizeof(hbuf));
	hostp = hbuf;
    }
    else {
	char *name;

	Check_SafeStr(host);
	name = RSTRING(host)->ptr;
	if (*name == 0) {
	    mkinetaddr(INADDR_ANY, hbuf, sizeof(hbuf));
	}
	else if (name[0] == '<' && strcmp(name, "<broadcast>") == 0) {
	    mkinetaddr(INADDR_BROADCAST, hbuf, sizeof(hbuf));
	}
	else if (strlen(name) >= sizeof(hbuf)) {
	    rb_raise(rb_eArgError, "hostname too long (%d)", strlen(name));
	}
	else {
	    strcpy(hbuf, name);
	}
	hostp = hbuf;
    }
    if (NIL_P(port)) {
	portp = 0;
    }
    else if (FIXNUM_P(port)) {
	snprintf(pbuf, sizeof(pbuf), "%d", FIX2INT(port));
	portp = pbuf;
    }
    else {
	Check_SafeStr(port);
	portp = STR2CSTR(port);
    }

    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    error = getaddrinfo(hostp, portp, &hints, &res);
    if (error) {
	if (hostp && hostp[strlen(hostp)-1] == '\n') {
	    rb_raise(rb_eSocket, "newline at the end of hostname");
	}
	rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));
    }

    return res;
}

static void
setipaddr(name, addr)
    VALUE name;
    struct sockaddr *addr;
{
    struct addrinfo *res = ip_addrsetup(name, Qnil);

    /* just take the first one */
    memcpy(addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);
}

static VALUE
ipaddr(sockaddr)
    struct sockaddr *sockaddr;
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
    if (!do_not_reverse_lookup) {
	error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			    NULL, 0, 0);
	if (error) {
	    rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
	}
	addr1 = rb_str_new2(hbuf);
    }
    error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV);
    if (error) {
	rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
    }
    addr2 = rb_str_new2(hbuf);
    if (do_not_reverse_lookup) {
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

static int
ruby_connect(fd, sockaddr, len, socks)
    int fd;
    struct sockaddr *sockaddr;
    int len;
    int socks;
{
    int status;
    int mode;
#if defined __CYGWIN__
    int wait_in_progress = -1;
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
#if defined __CYGWIN__
	      case EALREADY:
		wait_in_progress = 10;
#endif
#endif
		thread_write_select(fd);
		continue;

#if defined __CYGWIN__
	      case EINVAL:
		if (wait_in_progress-- > 0) {
		    struct timeval tv = {0, 100000};
		    rb_thread_wait_for(tv);
		    continue;
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
    VALUE host, serv;
    struct addrinfo *res;
    int type;
    int fd;
};

static VALUE
inetsock_cleanup(arg)
    struct inetsock_arg *arg;
{
    if (arg->res) {
	freeaddrinfo(arg->res);
	arg->res = 0;
    }
    if (arg->fd >= 0) {
	close(arg->fd);
    }
    return Qnil;
}

static VALUE
open_inet_internal(arg)
    struct inetsock_arg *arg;
{
    int type = arg->type;
    struct addrinfo hints, *res;
    int fd, status;
    char *syscall;
    char pbuf[1024], *portp;
    char *host;
    int error;

    if (arg->host) {
	Check_SafeStr(arg->host);
	host = RSTRING(arg->host)->ptr;
    }
    else {
	host = NULL;
    }
    if (FIXNUM_P(arg->serv)) {
	snprintf(pbuf, sizeof(pbuf), "%ld", FIX2UINT(arg->serv));
	portp = pbuf;
    }
    else {
	Check_SafeStr(arg->serv);
	if (RSTRING(arg->serv)->len >= sizeof(pbuf))
	    rb_raise(rb_eArgError, "servicename too long (%d)", RSTRING(arg->serv)->len);
	strcpy(pbuf, RSTRING(arg->serv)->ptr);
	portp = pbuf;
    }
    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (arg->type == INET_SERVER) {
	hints.ai_flags = AI_PASSIVE;
    }
    error = getaddrinfo(host, portp, &hints, &arg->res);
    if (error) {
	rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));
    }

    fd = -1;
    for (res = arg->res; res; res = res->ai_next) {
	status = ruby_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
	syscall = "socket(2)";
	fd = status;
	if (fd < 0) {
	    continue;
	}
	arg->fd = fd;
	if (type == INET_SERVER) {
#ifndef NT
	    status = 1;
	    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
		       (char*)&status, sizeof(status));
#endif
	    status = bind(fd, res->ai_addr, res->ai_addrlen);
	    syscall = "bind(2)";
	}
	else {
	    status = ruby_connect(fd, res->ai_addr, res->ai_addrlen,
				  (type == INET_SOCKS));
	    syscall = "connect(2)";
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
    return sock_new(arg->sock, fd);
}

static VALUE
open_inet(class, h, serv, type)
    VALUE class, h, serv;
    int type;
{
    struct inetsock_arg arg;
    arg.sock = class;
    arg.host = h;
    arg.serv = serv;
    arg.res = 0;
    arg.type = type;
    arg.fd = -1;
    return rb_ensure(open_inet_internal, (VALUE)&arg,
		     inetsock_cleanup, (VALUE)&arg);
}

static VALUE
tcp_s_open(class, host, serv)
    VALUE class, host, serv;
{
    Check_SafeStr(host);
    return open_inet(class, host, serv, INET_CLIENT);
}

#ifdef SOCKS
static VALUE
socks_s_open(class, host, serv)
    VALUE class, host, serv;
{
    static init = 0;

    if (init == 0) {
	SOCKSinit("ruby");
	init = 1;
    }
	
    Check_SafeStr(host);
    return open_inet(class, host, serv, INET_SOCKS);
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

/*
 * NOTE: using gethostbyname() against AF_INET6 is a bad idea, as it
 * does not initialize sin_flowinfo nor sin_scope_id properly.
 */
static VALUE
tcp_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    struct sockaddr_storage addr;
    struct hostent *h;
    char **pch;
    VALUE ary, names;

    rb_secure(3);
    if (rb_obj_is_kind_of(host, rb_cInteger)) {
	long i = NUM2LONG(host);
	struct sockaddr_in *sin;

	sin = (struct sockaddr_in *)&addr;
	MEMZERO(sin, struct sockaddr_in, 1);
	sin->sin_family = AF_INET;
	SET_SIN_LEN(sin, sizeof(*sin));
	sin->sin_addr.s_addr = htonl(i);
    }
    else {
	setipaddr(host, &addr);
    }
    switch (addr.ss_family) {
    case AF_INET:
      {
	struct sockaddr_in *sin;
	sin = (struct sockaddr_in *)&addr;
	h = gethostbyaddr((char *)&sin->sin_addr,
			  sizeof(sin->sin_addr),
			  sin->sin_family);
	break;
      }
#ifdef INET6
    case AF_INET6:
      {
	struct sockaddr_in6 *sin6;
	sin6 = (struct sockaddr_in6 *)&addr;
	h = gethostbyaddr((char *)&sin6->sin6_addr,
			  sizeof(sin6->sin6_addr),
			  sin6->sin6_family);
	break;
      }
#endif
    default:
	h = NULL;
    }

    if (h == NULL) {
#ifdef HAVE_HSTERROR
	extern int h_errno;
	rb_raise(rb_eSocket, "%s", (char *)hsterror(h_errno));
#else
	rb_raise(rb_eSocket, "host not found");
#endif
    }
    ary = rb_ary_new();
    rb_ary_push(ary, rb_str_new2(h->h_name));
    names = rb_ary_new();
    rb_ary_push(ary, names);
    for (pch = h->h_aliases; *pch; pch++) {
	rb_ary_push(names, rb_str_new2(*pch));
    }
    rb_ary_push(ary, INT2NUM(h->h_addrtype));
#ifdef h_addr
    for (pch = h->h_addr_list; *pch; pch++) {
	switch (addr.ss_family) {
	case AF_INET:
	  {
	    struct sockaddr_in sin;
	    MEMZERO(&sin, struct sockaddr_in, 1);
	    sin.sin_family = AF_INET;
	    SET_SIN_LEN(&sin, sizeof(sin));
	    memcpy((char *) &sin.sin_addr, *pch, h->h_length);
	    h = gethostbyaddr((char *)&sin.sin_addr,
			      sizeof(sin.sin_addr),
			      sin.sin_family);
	    rb_ary_push(ary, mkipaddr((struct sockaddr *)&sin));
	    break;
	  }
#ifdef INET6
	case AF_INET6:
	  {
	    struct sockaddr_in6 sin6;
	    MEMZERO(&sin6, struct sockaddr_in6, 1);
	    sin6.sin6_family = AF_INET;
#ifdef SIN6_LEN
	    sin6.sin6_len = sizeof(sin6);
#endif
	    memcpy((char *) &sin6.sin6_addr, *pch, h->h_length);
	    h = gethostbyaddr((char *)&sin6.sin6_addr,
			      sizeof(sin6.sin6_addr),
			      sin6.sin6_family);
	    rb_ary_push(ary, mkipaddr((struct sockaddr *)&sin6));
	    break;
	  }
#endif
	default:
	    h = NULL;
	}
    }
#else
    memcpy((char *)&addr.sin_addr, h->h_addr, h->h_length);
    rb_ary_push(ary, mkipaddr((struct sockaddr *)&addr));
#endif

    return ary;
}

static VALUE
tcp_svr_s_open(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2)
	return open_inet(class, arg1, arg2, INET_SERVER);
    else
	return open_inet(class, 0, arg1, INET_SERVER);
}

static VALUE
s_accept(class, fd, sockaddr, len)
    VALUE class;
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
	  case EINTR:
	    rb_thread_schedule();
	    goto retry;
	}
	rb_sys_fail(0);
    }
    return sock_new(class, fd2);
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
open_unix(class, path, server)
    VALUE class;
    struct RString *path;
    int server;
{
    struct sockaddr_un sockaddr;
    int fd, status;
    VALUE sock;
    OpenFile *fptr;

    Check_SafeStr(path);
    fd = ruby_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
	rb_sys_fail("socket(2)");
    }

    MEMZERO(&sockaddr, struct sockaddr_un, 1);
    sockaddr.sun_family = AF_UNIX;
    strncpy(sockaddr.sun_path, path->ptr, sizeof(sockaddr.sun_path)-1);
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

    sock = sock_new(class, fd);
    GetOpenFile(sock, fptr);
    fptr->path = strdup(path->ptr);

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
    return ipaddr((struct sockaddr *)&addr);
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
    return ipaddr((struct sockaddr *)&addr);
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

    setipaddr(host, &addr);
    return mkipaddr((struct sockaddr *)&addr);
}

static VALUE
udp_s_open(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
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

    return sock_new(class, fd);
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
    int fd;
    struct udp_arg arg;
    VALUE ret;

    rb_secure(3);
    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
    arg.res = ip_addrsetup(host, port);
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
    res0 = ip_addrsetup(host, port);
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
    char *m;
    int mlen;
    struct addrinfo *res0, *res;

    if (argc == 2 || argc == 3) {
	return bsock_send(argc, argv, sock);
    }
    rb_secure(4);
    rb_scan_args(argc, argv, "4", &mesg, &flags, &host, &port);

    GetOpenFile(sock, fptr);
    res0 = ip_addrsetup(host, port);
    f = GetWriteFile(fptr);
    m = rb_str2cstr(mesg, &mlen);
    for (res = res0; res; res = res->ai_next) {
      retry:
	n = sendto(fileno(f), m, mlen, NUM2INT(flags), res->ai_addr,
		    res->ai_addrlen);
	if (n >= 0) {
	    freeaddrinfo(res0);
	    return INT2FIX(n);
	}
	switch (errno) {
	  case EINTR:
	    rb_thread_schedule();
	    goto retry;
	}
    }
    freeaddrinfo(res0);
    rb_sys_fail("sendto(2)");
    return INT2FIX(n);
}

#ifdef HAVE_SYS_UN_H
static VALUE
unix_s_sock_open(sock, path)
    VALUE sock, path;
{
    return open_unix(sock, path, 0);
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
unix_svr_s_open(sock, path)
    VALUE sock, path;
{
    return open_unix(sock, path, 1);
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
unixaddr(sockaddr)
    struct sockaddr_un *sockaddr;
{
    return rb_assoc_new(rb_str_new2("AF_UNIX"),
			rb_str_new2(sockaddr->sun_path));
}

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
	Check_SafeStr(domain);
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
	Check_SafeStr(type);
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
sock_s_open(class, domain, type, protocol)
    VALUE class, domain, type, protocol;
{
    int fd;
    int d, t;

    rb_secure(3);
    setup_domain_and_type(domain, &d, type, &t);
    fd = ruby_socket(d, t, NUM2INT(protocol));
    if (fd < 0) rb_sys_fail("socket(2)");

    return sock_new(class, fd);
}

static VALUE
sock_s_for_fd(class, fd)
    VALUE class, fd;
{
    return sock_new(class, NUM2INT(fd));
}

static VALUE
sock_s_socketpair(class, domain, type, protocol)
    VALUE class, domain, type, protocol;
{
#if !defined(NT) && !defined(__BEOS__) && !defined(__EMX__) && !defined(__QNXNTO__)
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

    return rb_assoc_new(sock_new(class, sp[0]), sock_new(class, sp[1]));
#else
    rb_notimplement();
#endif
}

static VALUE
sock_connect(sock, addr)
    VALUE sock, addr;
{
    OpenFile *fptr;
    int fd;

    Check_Type(addr, T_STRING);
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

    Check_Type(addr, T_STRING);
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

    return rb_assoc_new(sock2, rb_tainted_str_new(buf, len));
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
mkhostent(h)
    struct hostent *h;
{
    char **pch;
    VALUE ary, names;

    if (h == NULL) {
#ifdef HAVE_HSTRERROR
	extern int h_errno;
	rb_raise(rb_eSocket, "%s", (char *)hstrerror(h_errno));
#else
	rb_raise(rb_eSocket, "host not found");
#endif
    }
    ary = rb_ary_new();
    rb_ary_push(ary, rb_str_new2(h->h_name));
    names = rb_ary_new();
    rb_ary_push(ary, names);
    for (pch = h->h_aliases; *pch; pch++) {
	rb_ary_push(names, rb_str_new2(*pch));
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
mkaddrinfo(res0)
    struct addrinfo *res0;
{
    VALUE base, ary;
    struct addrinfo *res;

    if (res0 == NULL) {
	rb_raise(rb_eSocket, "host not found");
    }
    base = rb_ary_new();
    for (res = res0; res; res = res->ai_next) {
	ary = ipaddr(res->ai_addr);
	rb_ary_push(ary, INT2FIX(res->ai_family));
	rb_ary_push(ary, INT2FIX(res->ai_socktype));
	rb_ary_push(ary, INT2FIX(res->ai_protocol));
	rb_ary_push(base, ary);
    }
    return base;
}

/*
 * NOTE: using gethostbyname() against AF_INET6 is a bad idea, as it
 * does not initialize sin_flowinfo nor sin_scope_id properly.
 */
static VALUE
sock_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    struct sockaddr_storage addr;
    struct hostent *h;

    if (rb_obj_is_kind_of(host, rb_cInteger)) {
	long i = NUM2LONG(host);
	struct sockaddr_in *sin;
	sin = (struct sockaddr_in *)&addr;
	MEMZERO(sin, struct sockaddr_in, 1);
	sin->sin_family = AF_INET;
	SET_SIN_LEN(sin, sizeof(*sin));
	sin->sin_addr.s_addr = htonl(i);
    }
    else {
	setipaddr(host, (struct sockaddr *)&addr);
    }
    switch (addr.ss_family) {
    case AF_INET:
      {
	struct sockaddr_in *sin;
	sin = (struct sockaddr_in *)&addr;
	h = gethostbyaddr((char *)&sin->sin_addr,
			  sizeof(sin->sin_addr),
			  sin->sin_family);
	break;
      }
#ifdef INET6
    case AF_INET6:
      {
	struct sockaddr_in6 *sin6;
	sin6 = (struct sockaddr_in6 *)&addr;
	h = gethostbyaddr((char *)&sin6->sin6_addr,
			  sizeof(sin6->sin6_addr),
			  sin6->sin6_family);
	break;
      }
#endif
    default:
	h = NULL;
    }

    return mkhostent(h);
}

static VALUE
sock_s_gethostbyaddr(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vaddr, vtype;
    int type;
    int alen;
    char *addr;
    struct hostent *h;

    rb_scan_args(argc, argv, "11", &vaddr, &vtype);
    addr = rb_str2cstr(vaddr, &alen);
    if (!NIL_P(vtype)) {
	type = NUM2INT(vtype);
    }
    else {
	type = AF_INET;
    }

    h = gethostbyaddr(addr, alen, type);

    return mkhostent(h);
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
    else proto = STR2CSTR(protocol);

    sp = getservbyname(STR2CSTR(service), proto);
    if (sp) {
	port = ntohs(sp->s_port);
    }
    else {
	char *s = STR2CSTR(service);
	char *end;

	port = strtoul(s, &end, 0);
	if (*end != '\0') {
	    rb_raise(rb_eSocket, "no such servce %s/%s", s, proto);
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
    char *hptr, *pptr;
    struct addrinfo hints, *res;
    int error;

    host = port = family = socktype = protocol = flags = Qnil;
    rb_scan_args(argc, argv, "24", &host, &port, &family, &socktype, &protocol, &flags);
    if (NIL_P(host)) {
	hptr = NULL;
    }
    else {
	strncpy(hbuf, STR2CSTR(host), sizeof(hbuf));
	hbuf[sizeof(hbuf) - 1] = '\0';
	hptr = hbuf;
    }
    if (NIL_P(port)) {
	pptr = NULL;
    }
    else if (FIXNUM_P(port)) {
	snprintf(pbuf, sizeof(pbuf), "%ld", FIX2INT(port));
	pptr = pbuf;
    }
    else {
	strncpy(pbuf, STR2CSTR(port), sizeof(pbuf));
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
    else if (strcmp(STR2CSTR(family), "AF_INET") == 0) {
	hints.ai_family = PF_INET;
    }
#ifdef INET6
    else if (strcmp(STR2CSTR(family), "AF_INET6") == 0) {
	hints.ai_family = PF_INET6;
    }
#endif

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
	rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));
    }

    ret = mkaddrinfo(res);
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
    char *ep;

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
	if (RSTRING(sa)->len != SA_LEN((struct sockaddr *)&ss)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
	sap = (struct sockaddr *)&ss;
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
	    rb_raise(rb_eArgError, "array size should be 3 or 4, %d given",
		     RARRAY(sa)->len);
	}
	/* host */
	if (NIL_P(host)) {
	    hptr = NULL;
	}
	else {
	    strncpy(hbuf, STR2CSTR(host), sizeof(hbuf));
	    hbuf[sizeof(hbuf) - 1] = '\0';
	    hptr = hbuf;
	}
	/* port */
	if (NIL_P(port)) {
	    strcpy(pbuf, "0");
	    pptr = NULL;
	}
	else if (FIXNUM_P(port)) {
	    snprintf(pbuf, sizeof(pbuf), "%ld", NUM2INT(port));
	    pptr = pbuf;
	}
	else {
	    strncpy(pbuf, STR2CSTR(port), sizeof(pbuf));
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
	else if (strcmp(STR2CSTR(af), "AF_INET") == 0) {
	    hints.ai_family = PF_INET;
	}
#ifdef INET6
	else if (strcmp(STR2CSTR(af), "AF_INET6") == 0) {
	    hints.ai_family = PF_INET6;
	}
#endif
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
    rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));

  error_exit_name:
    if (res) freeaddrinfo(res);
    rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
}

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
    rb_undef_method(CLASS_OF(rb_cBasicSocket), "new");
    rb_undef_method(CLASS_OF(rb_cBasicSocket), "open");

    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup",
			       bsock_do_not_rev_lookup, 0);
    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup=",
			       bsock_do_not_rev_lookup_set, 1);

    rb_define_method(rb_cBasicSocket, "close_read", bsock_close_read, 0);
    rb_define_method(rb_cBasicSocket, "close_write", bsock_close_write, 0);
    rb_define_method(rb_cBasicSocket, "shutdown", bsock_shutdown, -1);
    rb_define_method(rb_cBasicSocket, "setsockopt", bsock_setsockopt, 3);
    rb_define_method(rb_cBasicSocket, "getsockopt", bsock_getsockopt, 2);
    rb_define_method(rb_cBasicSocket, "getsockname", bsock_getsockname, 0);
    rb_define_method(rb_cBasicSocket, "getpeername", bsock_getpeername, 0);
    rb_define_method(rb_cBasicSocket, "send", bsock_send, -1);
    rb_define_method(rb_cBasicSocket, "recv", bsock_recv, -1);

    rb_cIPSocket = rb_define_class("IPSocket", rb_cBasicSocket);
    rb_define_global_const("IPsocket", rb_cIPSocket);
    rb_define_method(rb_cIPSocket, "addr", ip_addr, 0);
    rb_define_method(rb_cIPSocket, "peeraddr", ip_peeraddr, 0);
    rb_define_method(rb_cIPSocket, "recvfrom", ip_recvfrom, -1);
    rb_define_singleton_method(rb_cIPSocket, "getaddress", ip_s_getaddress, 1);

    rb_cTCPSocket = rb_define_class("TCPSocket", rb_cIPSocket);
    rb_define_global_const("TCPsocket", rb_cTCPSocket);
    rb_define_singleton_method(rb_cTCPSocket, "open", tcp_s_open, 2);
    rb_define_singleton_method(rb_cTCPSocket, "new", tcp_s_open, 2);
    rb_define_singleton_method(rb_cTCPSocket, "gethostbyname", tcp_s_gethostbyname, 1);

#ifdef SOCKS
    rb_cSOCKSSocket = rb_define_class("SOCKSSocket", rb_cTCPSocket);
    rb_define_global_const("SOCKSsocket", rb_cSOCKSSocket);
    rb_define_singleton_method(rb_cSOCKSSocket, "open", socks_s_open, 2);
    rb_define_singleton_method(rb_cSOCKSSocket, "new", socks_s_open, 2);
#ifdef SOCKS5
    rb_define_method(rb_cSOCKSSocket, "close", socks_s_close, 0);
#endif
#endif

    rb_cTCPServer = rb_define_class("TCPServer", rb_cTCPSocket);
    rb_define_global_const("TCPserver", rb_cTCPServer);
    rb_define_singleton_method(rb_cTCPServer, "open", tcp_svr_s_open, -1);
    rb_define_singleton_method(rb_cTCPServer, "new", tcp_svr_s_open, -1);
    rb_define_method(rb_cTCPServer, "accept", tcp_accept, 0);

    rb_cUDPSocket = rb_define_class("UDPSocket", rb_cIPSocket);
    rb_define_global_const("UDPsocket", rb_cUDPSocket);
    rb_define_singleton_method(rb_cUDPSocket, "open", udp_s_open, -1);
    rb_define_singleton_method(rb_cUDPSocket, "new", udp_s_open, -1);
    rb_define_method(rb_cUDPSocket, "connect", udp_connect, 2);
    rb_define_method(rb_cUDPSocket, "bind", udp_bind, 2);
    rb_define_method(rb_cUDPSocket, "send", udp_send, -1);

#ifdef HAVE_SYS_UN_H
    rb_cUNIXSocket = rb_define_class("UNIXSocket", rb_cBasicSocket);
    rb_define_global_const("UNIXsocket", rb_cUNIXSocket);
    rb_define_singleton_method(rb_cUNIXSocket, "open", unix_s_sock_open, 1);
    rb_define_singleton_method(rb_cUNIXSocket, "new", unix_s_sock_open, 1);
    rb_define_method(rb_cUNIXSocket, "path", unix_path, 0);
    rb_define_method(rb_cUNIXSocket, "addr", unix_addr, 0);
    rb_define_method(rb_cUNIXSocket, "peeraddr", unix_peeraddr, 0);
    rb_define_method(rb_cUNIXSocket, "recvfrom", unix_recvfrom, -1);

    rb_cUNIXServer = rb_define_class("UNIXServer", rb_cUNIXSocket);
    rb_define_global_const("UNIXserver", rb_cUNIXServer);
    rb_define_singleton_method(rb_cUNIXServer, "open", unix_svr_s_open, 1);
    rb_define_singleton_method(rb_cUNIXServer, "new", unix_svr_s_open, 1);
    rb_define_method(rb_cUNIXServer, "accept", unix_accept, 0);
#endif

    rb_cSocket = rb_define_class("Socket", rb_cBasicSocket);
    rb_define_singleton_method(rb_cSocket, "open", sock_s_open, 3);
    rb_define_singleton_method(rb_cSocket, "new", sock_s_open, 3);
    rb_define_singleton_method(rb_cSocket, "for_fd", sock_s_for_fd, 1);

    rb_define_method(rb_cSocket, "connect", sock_connect, 1);
    rb_define_method(rb_cSocket, "bind", sock_bind, 1);
    rb_define_method(rb_cSocket, "listen", sock_listen, 1);
    rb_define_method(rb_cSocket, "accept", sock_accept, 0);

    rb_define_method(rb_cSocket, "recvfrom", sock_recvfrom, -1);

    rb_define_singleton_method(rb_cSocket, "socketpair", sock_s_socketpair, 3);
    rb_define_singleton_method(rb_cSocket, "pair", sock_s_socketpair, 3);
    rb_define_singleton_method(rb_cSocket, "gethostname", sock_gethostname, 0);
    rb_define_singleton_method(rb_cSocket, "gethostbyname", sock_s_gethostbyname, 1);
    rb_define_singleton_method(rb_cSocket, "gethostbyaddr", sock_s_gethostbyaddr, -1);
    rb_define_singleton_method(rb_cSocket, "getservbyname", sock_s_getservbyaname, -1);
    rb_define_singleton_method(rb_cSocket, "getaddrinfo", sock_s_getaddrinfo, -1);
    rb_define_singleton_method(rb_cSocket, "getnameinfo", sock_s_getnameinfo, -1);

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
#ifdef AF_INET6
    sock_define_const("AF_INET6", AF_INET6);
#endif
#ifdef PF_INET6
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
}
