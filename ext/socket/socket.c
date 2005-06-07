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
#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
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

#if defined(_AIX)
static int
ruby_getaddrinfo__aix(nodename, servname, hints, res)
     char *nodename;
     char *servname;
     struct addrinfo *hints;
     struct addrinfo **res;
{
    int error = getaddrinfo(nodename, servname, hints, res);
    struct addrinfo *r;
    if (error)
	return error;
    for (r = *res; r != NULL; r = r->ai_next) {
	if (r->ai_addr->sa_family == 0)
	    r->ai_addr->sa_family = r->ai_family;
	if (r->ai_addr->sa_len == 0)
	    r->ai_addr->sa_len = r->ai_addrlen;
    }
    return 0;
}
#undef getaddrinfo
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo__aix((node),(serv),(hints),(res))
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
    fp->fd = fd;
    fp->mode = FMODE_READWRITE|FMODE_DUPLEX;
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
    if (shutdown(fptr->fd, how) == -1)
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
    shutdown(fptr->fd, 0);
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
    shutdown(fptr->fd, 1);
    fptr->mode &= ~FMODE_WRITABLE;

    return Qnil;
}

/*
 * Document-method: setsockopt
 * call-seq: setsockopt(level, optname, optval)
 *
 * Sets a socket option. These are protocol and system specific, see your
 * local sytem documentation for details.
 *
 * === Parameters
 * * +level+ is an integer, usually one of the SOL_ constants such as
 *   Socket::SOL_SOCKET, or a protocol level.
 * * +optname+ is an integer, usually one of the SO_ constants, such
 *   as Socket::SO_REUSEADDR.
 * * +optval+ is the value of the option, it is passed to the underlying
 *   setsockopt() as a pointer to a certain number of bytes. How this is
 *   done depends on the type:
 *   - Fixnum: value is assigned to an int, and a pointer to the int is
 *     passed, with length of sizeof(int).
 *   - true or false: 1 or 0 (respectively) is assigned to an int, and the
 *     int is passed as for a Fixnum. Note that +false+ must be passed,
 *     not +nil+.
 *   - String: the string's data and length is passed to the socket.
 *
 * === Examples
 *
 * Some socket options are integers with boolean values, in this case
 * #setsockopt could be called like this:
 *   sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
 *
 * Some socket options are integers with numeric values, in this case
 * #setsockopt could be called like this:
 *   sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, 255)
 *
 * Option values may be structs. Passing them can be complex as it involves
 * examining your system headers to determine the correct definition. An
 * example is an +ip_mreq+, which may be defined in your system headers as:
 *   struct ip_mreq {
 *     struct  in_addr imr_multiaddr;
 *     struct  in_addr imr_interface;
 *   };
 * 
 * In this case #setsockopt could be called like this:
 *   optval =  IPAddr.new("224.0.0.251") + Socket::INADDR_ANY
 *   sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, optval)
 *
*/
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
    if (setsockopt(fptr->fd, level, option, v, vlen) < 0)
	rb_sys_fail(fptr->path);

    return INT2FIX(0);
}

/*
 * Document-method: getsockopt
 * call-seq: getsockopt(level, optname)
 *
 * Gets a socket option. These are protocol and system specific, see your
 * local sytem documentation for details. The option is returned as
 * a String with the data being the binary value of the socket option.
 *
 * === Parameters
 * * +level+ is an integer, usually one of the SOL_ constants such as
 *   Socket::SOL_SOCKET, or a protocol level.
 * * +optname+ is an integer, usually one of the SO_ constants, such
 *   as Socket::SO_REUSEADDR.
 *
 * === Examples
 *
 * Some socket options are integers with boolean values, in this case
 * #getsockopt could be called like this:
 *   optval = sock.getsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR)
 *   optval = optval.unpack "i"
 *   reuseaddr = optval[0] == 0 ? false : true
 *
 * Some socket options are integers with numeric values, in this case
 * #getsockopt could be called like this:
 *   optval = sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL)
 *   ipttl = optval.unpack("i")[0]
 *
 * Option values may be structs. Decoding them can be complex as it involves
 * examining your system headers to determine the correct definition. An
 * example is a +struct linger+, which may be defined in your system headers
 * as:
 *   struct linger {
 *     int l_onoff;
 *     int l_linger;
 *   };
 * 
 * In this case #getsockopt could be called like this:
 *   optval =  sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER)
 *   onoff, linger = optval.unpack "ii"
*/
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
    if (getsockopt(fptr->fd, level, option, buf, &len) < 0)
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
    if (getsockname(fptr->fd, (struct sockaddr*)buf, &len) < 0)
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
    if (getpeername(fptr->fd, (struct sockaddr*)buf, &len) < 0)
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
    int fd, n;

    rb_secure(4);
    rb_scan_args(argc, argv, "21", &mesg, &flags, &to);

    StringValue(mesg);
    if (!NIL_P(to)) StringValue(to);
    GetOpenFile(sock, fptr);
    fd = fptr->fd;
    rb_thread_fd_writable(fd);
  retry:
    if (!NIL_P(to)) {
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
    buflen = NUM2INT(len);

    GetOpenFile(sock, fptr);
    if (rb_io_read_pending(fptr)) {
	rb_raise(rb_eIOError, "recv for buffered IO");
    }
    fd = fptr->fd;

    str = rb_tainted_str_new(0, buflen);

  retry:
    rb_thread_wait_fd(fd);
    rb_io_check_closed(fptr);
    if (RSTRING(str)->len != buflen) {
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
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
	if (alen) /* OSX doesn't return a from result for connection-oriented sockets */
	  return rb_assoc_new(str, ipaddr((struct sockaddr*)buf, fptr->mode & FMODE_NOREVLOOKUP));
	else
	  return rb_assoc_new(str, Qnil);

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

static int
wait_connectable0(fd, fds_w, fds_e)
    int fd;
    rb_fdset_t *fds_w, *fds_e;
{
    int sockerr, sockerrlen;

    for (;;) {
	rb_fd_zero(fds_w);
	rb_fd_zero(fds_e);

	rb_fd_set(fd, fds_w);
	rb_fd_set(fd, fds_e);

	rb_thread_select(fd+1, 0, rb_fd_ptr(fds_w), rb_fd_ptr(fds_e), 0);

	if (rb_fd_isset(fd, fds_w)) {
	    return 0;
	}
	else if (rb_fd_isset(fd, fds_e)) {
	    sockerrlen = sizeof(sockerr);
	    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&sockerr,
			   &sockerrlen) == 0) {
		if (sockerr == 0)
		    continue;	/* workaround for winsock */
		errno = sockerr;
	    }
	    return -1;
	}
    }

    return 0;
}

struct wait_connectable_arg {
    int fd;
    rb_fdset_t fds_w;
    rb_fdset_t fds_e;
};

#ifdef HAVE_RB_FD_INIT
static VALUE
try_wait_connectable(arg)
    VALUE arg;
{
    struct wait_connectable_arg *p = (struct wait_connectable_arg *)arg;
    return (VALUE)wait_connectable0(p->fd, &p->fds_w, &p->fds_e);
}

static VALUE
wait_connectable_ensure(arg)
    VALUE arg;
{
    struct wait_connectable_arg *p = (struct wait_connectable_arg *)arg;
    rb_fd_term(&p->fds_w);
    rb_fd_term(&p->fds_e);
    return Qnil;
}
#endif

static int
wait_connectable(fd)
    int fd;
{
    struct wait_connectable_arg arg;

    rb_fd_init(&arg.fds_w);
    rb_fd_init(&arg.fds_e);
#ifdef HAVE_RB_FD_INIT
    arg.fd = fd;
    return (int)rb_ensure(try_wait_connectable, (VALUE)&arg,
			  wait_connectable_ensure,(VALUE)&arg);
#else
    return wait_connectable0(fd, &arg.fds_w, &arg.fds_e);
#endif
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
# if defined(F_GETFL)
    mode = fcntl(fd, F_GETFL, 0);
# else
    mode = 0;
# endif

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
		status = wait_connectable(fd);
		if (status) {
		    break;
		}
		errno = 0;
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
    shutdown(fptr->fd, 2);
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
	  case EWOULDBLOCK:
	    break;
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
    return s_accept(rb_cTCPSocket, fptr->fd,
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
    return s_accept(0, fptr->fd, (struct sockaddr*)&from, &fromlen);
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
    return (VALUE)ruby_connect(arg->fd, arg->sockaddr, sizeof(*arg->sockaddr), 0);
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

    if (getsockname(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
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

    if (getpeername(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
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
    arg.res = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    GetOpenFile(sock, fptr);
    arg.fd = fptr->fd;
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
    res0 = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    GetOpenFile(sock, fptr);
    for (res = res0; res; res = res->ai_next) {
	if (bind(fptr->fd, res->ai_addr, res->ai_addrlen) < 0) {
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
    int n;
    struct addrinfo *res0, *res;

    if (argc == 2 || argc == 3) {
	return bsock_send(argc, argv, sock);
    }
    rb_secure(4);
    rb_scan_args(argc, argv, "4", &mesg, &flags, &host, &port);

    StringValue(mesg);
    res0 = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    GetOpenFile(sock, fptr);
    for (res = res0; res; res = res->ai_next) {
      retry:
	n = sendto(fptr->fd, RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags),
		   res->ai_addr, res->ai_addrlen);
	if (n >= 0) {
	    freeaddrinfo(res0);
	    return INT2FIX(n);
	}
	if (rb_io_wait_writable(fptr->fd)) {
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
	if (getsockname(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
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

#if defined(HAVE_ST_MSG_CONTROL) && defined(SCM_RIGHTS)
#define FD_PASSING_BY_MSG_CONTROL 1
#else
#define FD_PASSING_BY_MSG_CONTROL 0
#endif

#if defined(HAVE_ST_MSG_ACCRIGHTS)
#define FD_PASSING_BY_MSG_ACCRIGHTS 1
#else
#define FD_PASSING_BY_MSG_ACCRIGHTS 0
#endif

static VALUE
unix_send_io(sock, val)
    VALUE sock, val;
{
#if defined(HAVE_SENDMSG) && (FD_PASSING_BY_MSG_CONTROL || FD_PASSING_BY_MSG_ACCRIGHTS)
    int fd;
    OpenFile *fptr;
    struct msghdr msg;
    struct iovec vec[1];
    char buf[1];

#if FD_PASSING_BY_MSG_CONTROL
    struct {
	struct cmsghdr hdr;
	int fd;
    } cmsg;
#endif

    if (rb_obj_is_kind_of(val, rb_cIO)) {
        OpenFile *valfptr;
	GetOpenFile(val, valfptr);
	fd = valfptr->fd;
    }
    else if (FIXNUM_P(val)) {
        fd = FIX2INT(val);
    }
    else {
	rb_raise(rb_eTypeError, "neither IO nor file descriptor");
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

#if FD_PASSING_BY_MSG_CONTROL
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

    if (sendmsg(fptr->fd, &msg, 0) == -1)
	rb_sys_fail("sendmsg(2)");

    return Qnil;
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
unix_recv_io(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
#if defined(HAVE_RECVMSG) && (FD_PASSING_BY_MSG_CONTROL || FD_PASSING_BY_MSG_ACCRIGHTS)
    VALUE klass, mode;
    OpenFile *fptr;
    struct msghdr msg;
    struct iovec vec[2];
    char buf[1];

    int fd;
#if FD_PASSING_BY_MSG_CONTROL
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

    rb_io_wait_readable(fptr->fd);

    msg.msg_name = NULL;
    msg.msg_namelen = 0;

    vec[0].iov_base = buf;
    vec[0].iov_len = sizeof(buf);
    msg.msg_iov = vec;
    msg.msg_iovlen = 1;

#if FD_PASSING_BY_MSG_CONTROL
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

    if (recvmsg(fptr->fd, &msg, 0) == -1)
	rb_sys_fail("recvmsg(2)");

    if (
#if FD_PASSING_BY_MSG_CONTROL
	msg.msg_controllen != sizeof(struct cmsghdr) + sizeof(int) ||
        cmsg.hdr.cmsg_len != sizeof(struct cmsghdr) + sizeof(int) ||
	cmsg.hdr.cmsg_level != SOL_SOCKET ||
	cmsg.hdr.cmsg_type != SCM_RIGHTS
#else
        msg.msg_accrightslen != sizeof(fd)
#endif
	) {
	rb_raise(rb_eSocket, "file descriptor was not passed");
    }

#if FD_PASSING_BY_MSG_CONTROL
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
    return s_accept(rb_cUNIXSocket, fptr->fd,
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
    return s_accept(0, fptr->fd, (struct sockaddr*)&from, &fromlen);
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

    if (getsockname(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
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

    if (getpeername(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
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
    VALUE tmp;
    char *ptr;

    tmp = rb_check_string_type(domain);
    if (!NIL_P(tmp)) {
	domain = tmp;
	rb_check_safe_obj(domain);
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
	    rb_raise(rb_eSocket, "unknown socket domain %s", ptr);
    }
    else {
	*dv = NUM2INT(domain);
    }
    tmp = rb_check_string_type(type);
    if (!NIL_P(tmp)) {
	type = tmp;
	rb_check_safe_obj(type);
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
	    rb_raise(rb_eSocket, "unknown socket type %s", ptr);
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
    int fd, n;
    volatile VALUE tmpaddr;

    StringValue(addr);
    addr = rb_str_new4(addr);
    GetOpenFile(sock, fptr);
    fd = fptr->fd;
    n = ruby_connect(fd, (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len, 0);
    if (n < 0) {
	rb_sys_fail("connect(2)");
    }

    return INT2FIX(n);
}

static VALUE
sock_bind(sock, addr)
    VALUE sock, addr;
{
    OpenFile *fptr;

    StringValue(addr);
    GetOpenFile(sock, fptr);
    if (bind(fptr->fd, (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len) < 0)
	rb_sys_fail("bind(2)");

    return INT2FIX(0);
}

static VALUE
sock_listen(sock, log)
    VALUE sock, log;
{
    OpenFile *fptr;
    int backlog;

    rb_secure(4);
    backlog = NUM2INT(log);
    GetOpenFile(sock, fptr);
    if (listen(fptr->fd, backlog) < 0)
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
    sock2 = s_accept(rb_cSocket,fptr->fd,(struct sockaddr*)buf,&len);

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
    sock2 = s_accept(0,fptr->fd,(struct sockaddr*)buf,&len);

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
    char *ptr;

    switch (addr->sa_family) {
      case AF_INET:
	ptr = (char*)&((struct sockaddr_in*)addr)->sin_addr.s_addr;
	len = sizeof(((struct sockaddr_in*)addr)->sin_addr.s_addr);
	break;
#ifdef INET6
      case AF_INET6:
	ptr = (char*)&((struct sockaddr_in6*)addr)->sin6_addr.s6_addr;
	len = sizeof(((struct sockaddr_in6*)addr)->sin6_addr.s6_addr);
	break;
#endif
      default:
        rb_raise(rb_eSocket, "unknown socket family:%d", addr->sa_family);
	break;
    }
    return rb_str_new(ptr, len);
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
    h = gethostbyaddr(RSTRING(addr)->ptr, RSTRING(addr)->len, t);
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
sock_s_getservbyname(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE service, proto;
    struct servent *sp;
    int port;

    rb_scan_args(argc, argv, "11", &service, &proto);
    if (NIL_P(proto)) proto = rb_str_new2("tcp");
    StringValue(service);
    StringValue(proto);

    sp = getservbyname(StringValueCStr(service),  StringValueCStr(proto));
    if (sp) {
	port = ntohs(sp->s_port);
    }
    else {
	char *s = RSTRING(service)->ptr;
	char *end;

	port = strtoul(s, &end, 0);
	if (*end != '\0') {
	    rb_raise(rb_eSocket, "no such service %s/%s", s, RSTRING(proto)->ptr);
	}
    }
    return INT2FIX(port);
}

static VALUE
sock_s_getservbyport(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE port, proto;
    struct servent *sp;

    rb_scan_args(argc, argv, "11", &port, &proto);
    if (NIL_P(proto)) proto = rb_str_new2("tcp");
    StringValue(proto);

    sp = getservbyport(NUM2INT(port),  StringValueCStr(proto));
    if (!sp) {
	rb_raise(rb_eSocket, "no such service for port %d/%s", NUM2INT(port), RSTRING(proto)->ptr);
    }
    return rb_tainted_str_new2(sp->s_name);
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
    VALUE sa, af = Qnil, host = Qnil, port = Qnil, flags, tmp;
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
    tmp = rb_check_string_type(sa);
    if (!NIL_P(tmp)) {
	sa = tmp;
	if (sizeof(ss) < RSTRING(sa)->len) {
	    rb_raise(rb_eTypeError, "sockaddr length too big");
	}
	memcpy(&ss, RSTRING(sa)->ptr, RSTRING(sa)->len);
	if (RSTRING(sa)->len != SA_LEN((struct sockaddr*)&ss)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
	sap = (struct sockaddr*)&ss;
	goto call_nameinfo;
    }
    tmp = rb_check_array_type(sa);
    if (!NIL_P(tmp)) {
	sa = tmp;
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
#ifdef AI_NUMERICHOST /* AIX 4.3.3 doesn't have AI_NUMERICHOST. */
		hints.ai_flags |= AI_NUMERICHOST;
#endif
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

  call_nameinfo:
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
    rb_define_singleton_method(rb_cSocket, "getservbyname", sock_s_getservbyname, -1);
    rb_define_singleton_method(rb_cSocket, "getservbyport", sock_s_getservbyport, -1);
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
#include "constants.h"
#ifdef INET6 /* IPv6 is not supported although AF_INET6 is defined on bcc32/mingw */
    sock_define_const("AF_INET6", AF_INET6);
    sock_define_const("PF_INET6", PF_INET6);
#endif
}
