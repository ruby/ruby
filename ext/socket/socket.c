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
#if defined(__BEOS__) && !defined(BONE)
# include <net/socket.h>
#else
# include <sys/socket.h>
# define pseudo_AF_FTIP pseudo_AF_RTIP	/* workaround for NetBSD and etc. */
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
#ifdef HAVE_ARPA_INET_H
# include <arpa/inet.h>
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
#include "addrinfo.h"
#endif
#include "sockport.h"

#if defined(__vms)
#include <tcp.h>
#endif

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
static int
ruby_getnameinfo__aix(sa, salen, host, hostlen, serv, servlen, flags)
     const struct sockaddr *sa;
     size_t salen;
     char *host;
     size_t hostlen;
     char *serv;
     size_t servlen;
     int flags;
{
  struct sockaddr_in6 *sa6;
  u_int32_t *a6;

  if (sa->sa_family == AF_INET6) {
    sa6 = (struct sockaddr_in6 *)sa;
    a6 = sa6->sin6_addr.u6_addr.u6_addr32;

    if (a6[0] == 0 && a6[1] == 0 && a6[2] == 0 && a6[3] == 0) {
      strncpy(host, "::", hostlen);
      snprintf(serv, servlen, "%d", sa6->sin6_port);
      return 0;
    }
  }
  return getnameinfo(sa, salen, host, hostlen, serv, servlen, flags);
}
#undef getnameinfo
#define getnameinfo(sa, salen, host, hostlen, serv, servlen, flags) \
            ruby_getnameinfo__aix((sa), (salen), (host), (hostlen), (serv), (servlen), (flags))
#ifndef CMSG_SPACE
# define CMSG_SPACE(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + _CMSG_ALIGN(len))
#endif
#ifndef CMSG_LEN
# define CMSG_LEN(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
#endif
#endif

static int str_isnumber _((const char *));

#if defined(__APPLE__)
/* fix [ruby-core:29427] */
static int
ruby_getaddrinfo__darwin(const char *nodename, const char *servname,
			 struct addrinfo *hints, struct addrinfo **res)
{
    const char *tmp_servname;
    struct addrinfo tmp_hints;
    tmp_servname = servname;
    MEMCPY(&tmp_hints, hints, struct addrinfo, 1);
    if (nodename && servname) {
	if (str_isnumber(tmp_servname) && atoi(servname) == 0) {
	    tmp_servname = NULL;
#ifdef AI_NUMERICSERV
	    if (tmp_hints.ai_flags) tmp_hints.ai_flags &= ~AI_NUMERICSERV;
#endif
	}
    }
    int error = getaddrinfo(nodename, tmp_servname, &tmp_hints, res);
    return error;
}
#undef getaddrinfo
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo__darwin((node),(serv),(hints),(res))
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
    rb_io_t *fp;

    MakeOpenFile(sock, fp);
    fp->f = rb_fdopen(fd, "r");
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE;
    rb_io_synchronized(fp);

    return sock;
}

static VALUE
bsock_s_for_fd(klass, fd)
    VALUE klass, fd;
{
    rb_io_t *fptr;
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
    rb_io_t *fptr;

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
    rb_io_t *fptr;

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
    rb_io_t *fptr;

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
    rb_io_t *fptr;
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
    rb_io_t *fptr;

    level = NUM2INT(lev);
    option = NUM2INT(optname);
    len = 256;
    buf = ALLOCA_N(char,len);
    GetOpenFile(sock, fptr);

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
    rb_io_t *fptr;

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
    rb_io_t *fptr;

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
    rb_io_t *fptr;
    FILE *f;
    int fd, n;

    rb_secure(4);
    rb_scan_args(argc, argv, "21", &mesg, &flags, &to);

    StringValue(mesg);
    if (!NIL_P(to)) StringValue(to);
    GetOpenFile(sock, fptr);
    f = GetWriteFile(fptr);
    fd = fileno(f);
    rb_thread_fd_writable(fd);
  retry:
    if (!NIL_P(to)) {
        TRAP_BEG;
	n = sendto(fd, RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags),
		   (struct sockaddr*)RSTRING(to)->ptr, RSTRING(to)->len);
        TRAP_END;
    }
    else {
        TRAP_BEG;
	n = send(fd, RSTRING(mesg)->ptr, RSTRING(mesg)->len, NUM2INT(flags));
        TRAP_END;
    }
    if (n < 0) {
	if (rb_io_wait_writable(fd)) {
	    goto retry;
	}
	rb_sys_fail("send(2)");
    }
    return INT2FIX(n);
}

static VALUE ipaddr _((struct sockaddr*));
#ifdef HAVE_SYS_UN_H
static VALUE unixaddr _((struct sockaddr_un*, socklen_t));
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
    rb_io_t *fptr;
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
    if (rb_read_pending(fptr->f)) {
	rb_raise(rb_eIOError, "recv for buffered IO");
    }
    fd = fileno(fptr->f);

    str = rb_tainted_str_new(0, buflen);

  retry:
    rb_str_locktmp(str);
    rb_thread_wait_fd(fd);
    TRAP_BEG;
    slen = recvfrom(fd, RSTRING(str)->ptr, buflen, flags, (struct sockaddr*)buf, &alen);
    TRAP_END;
    rb_str_unlocktmp(str);

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
	if (alen && alen != sizeof(buf)) /* OSX doesn't return a 'from' result from recvfrom for connection-oriented sockets */
	    return rb_assoc_new(str, ipaddr((struct sockaddr*)buf));
	else
	    return rb_assoc_new(str, Qnil);

#ifdef HAVE_SYS_UN_H
      case RECV_UNIX:
        return rb_assoc_new(str, unixaddr((struct sockaddr_un*)buf, alen));
#endif
      case RECV_SOCKET:
	return rb_assoc_new(str, rb_str_new(buf, alen));
      default:
	rb_bug("s_recvfrom called with bad value");
    }
}

static VALUE
s_recvfrom_nonblock(VALUE sock, int argc, VALUE *argv, enum sock_recv_type from)
{
    rb_io_t *fptr;
    VALUE str;
    char buf[1024];
    socklen_t alen = sizeof buf;
    VALUE len, flg;
    long buflen;
    long slen;
    int fd, flags;
    VALUE addr = Qnil;

    rb_scan_args(argc, argv, "11", &len, &flg);

    if (flg == Qnil) flags = 0;
    else             flags = NUM2INT(flg);
    buflen = NUM2INT(len);

#ifdef MSG_DONTWAIT
    /* MSG_DONTWAIT avoids the race condition between fcntl and recvfrom.
       It is not portable, though. */
    flags |= MSG_DONTWAIT;
#endif

    GetOpenFile(sock, fptr);
    if (rb_read_pending(fptr->f)) {
	rb_raise(rb_eIOError, "recvfrom for buffered IO");
    }
    fd = fileno(fptr->f);

    str = rb_tainted_str_new(0, buflen);

    rb_io_check_closed(fptr);
    rb_io_set_nonblock(fptr);
    slen = recvfrom(fd, RSTRING(str)->ptr, buflen, flags, (struct sockaddr*)buf, &alen);

    if (slen < 0) {
	rb_sys_fail("recvfrom(2)");
    }
    if (slen < RSTRING(str)->len) {
	RSTRING(str)->len = slen;
	RSTRING(str)->ptr[slen] = '\0';
    }
    rb_obj_taint(str);
    switch (from) {
      case RECV_RECV:
	return str;

      case RECV_IP:
        if (alen && alen != sizeof(buf)) /* connection-oriented socket may not return a from result */
            addr = ipaddr((struct sockaddr*)buf);
        break;

      case RECV_SOCKET:
        addr = rb_str_new(buf, alen);
        break;

      default:
        rb_bug("s_recvfrom_nonblock called with bad value");
    }
    return rb_assoc_new(str, addr);
}

static VALUE
bsock_recv(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_RECV);
}

/*
 * call-seq:
 * 	basicsocket.recv_nonblock(maxlen) => mesg
 * 	basicsocket.recv_nonblock(maxlen, flags) => mesg
 * 
 * Receives up to _maxlen_ bytes from +socket+ using recvfrom(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * _flags_ is zero or more of the +MSG_+ options.
 * The result, _mesg_, is the data received.
 *
 * When recvfrom(2) returns 0, Socket#recv_nonblock returns
 * an empty string as data.
 * The meaning depends on the socket: EOF on TCP, empty packet on UDP, etc.
 * 
 * === Parameters
 * * +maxlen+ - the number of bytes to receive from the socket
 * * +flags+ - zero or more of the +MSG_+ options 
 * 
 * === Example
 * 	serv = TCPServer.new("127.0.0.1", 0)
 * 	af, port, host, addr = serv.addr
 * 	c = TCPSocket.new(addr, port)
 * 	s = serv.accept
 * 	c.send "aaa", 0
 * 	IO.select([s])
 * 	p s.recv_nonblock(10) #=> "aaa"
 *
 * Refer to Socket#recvfrom for the exceptions that may be thrown if the call
 * to _recv_nonblock_ fails. 
 *
 * BasicSocket#recv_nonblock may raise any error corresponding to recvfrom(2) failure,
 * including Errno::EAGAIN.
 *
 * === See
 * * Socket#recvfrom
 */

static VALUE
bsock_recv_nonblock(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom_nonblock(sock, argc, argv, RECV_RECV);
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

static void
make_ipaddr0(addr, buf, len)
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
	unsigned long i = NUM2ULONG(host);

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
# define NI_MAXHOST 1025
#endif
#ifndef NI_MAXSERV
# define NI_MAXSERV 32
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
	rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));
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
    addr1 = Qnil;
    if (!do_not_reverse_lookup) {
	error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			    NULL, 0, 0);
	if (! error) {
	    addr1 = rb_str_new2(hbuf);
	}
    }
    error = getnameinfo(sockaddr, SA_LEN(sockaddr), hbuf, sizeof(hbuf),
			pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV);
    if (error) {
	rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
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
wait_connectable(fd)
    int fd;
{
    int sockerr;
    socklen_t sockerrlen;
    fd_set fds_w;
    fd_set fds_e;

    for (;;) {
	FD_ZERO(&fds_w);
	FD_ZERO(&fds_e);

	FD_SET(fd, &fds_w);
	FD_SET(fd, &fds_e);

	rb_thread_select(fd+1, 0, &fds_w, &fds_e, 0);

	if (FD_ISSET(fd, &fds_w)) {
	    return 0;
	}
	else if (FD_ISSET(fd, &fds_e)) {
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
    int sockerr;
    socklen_t sockerrlen;
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
    const char *syscall = 0;

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
#if !defined(_WIN32) && !defined(__CYGWIN__)
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

/*
 * call-seq:
 *    TCPSocket.new(remote_host, remote_port, local_host=nil, local_port=nil)
 *
 * Opens a TCP connection to +remote_host+ on +remote_port+.  If +local_host+
 * and +local_port+ are specified, then those parameters are used on the local
 * end to establish the connection.
 */
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
    rb_io_t *fptr;

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
      /* Pushing all addresses regardless of address family is not the
       * behaviour expected of gethostbyname(). All the addresses in struct
       * hostent->h_addr_list must be of the same family.
       */
       if(ai->ai_family == addr->ai_family) {
	   rb_ary_push(ary, (*ipaddr)(ai->ai_addr, ai->ai_addrlen));
       }
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

static void
make_fd_nonblock(int fd)
{
    int flags;
#ifdef F_GETFL
    flags = fcntl(fd, F_GETFL);
    if (flags == -1) {
        rb_sys_fail(0);
    }
#else
    flags = 0;
#endif
    flags |= O_NONBLOCK;
    if (fcntl(fd, F_SETFL, flags) == -1) {
        rb_sys_fail(0);
    }
}

static VALUE
s_accept_nonblock(VALUE klass, rb_io_t *fptr, struct sockaddr *sockaddr, socklen_t *len)
{
    int fd2;

    rb_secure(3);
    rb_io_set_nonblock(fptr);
    fd2 = accept(fileno(fptr->f), (struct sockaddr*)sockaddr, len);
    if (fd2 < 0) {
        rb_sys_fail("accept(2)");
    }
    make_fd_nonblock(fd2);
    return init_sock(rb_obj_alloc(klass), fd2);
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
    rb_io_t *fptr;
    struct sockaddr_storage from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(from);
    return s_accept(rb_cTCPSocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

/*
 * call-seq:
 * 	tcpserver.accept_nonblock => tcpsocket
 * 
 * Accepts an incoming connection using accept(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * It returns an accepted TCPSocket for the incoming connection.
 * 
 * === Example
 * 	require 'socket'
 * 	serv = TCPServer.new(2202)
 * 	begin
 * 	  sock = serv.accept_nonblock
 * 	rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
 * 	  IO.select([serv])
 * 	  retry
 * 	end
 * 	# sock is an accepted socket.
 * 
 * Refer to Socket#accept for the exceptions that may be thrown if the call
 * to TCPServer#accept_nonblock fails. 
 *
 * TCPServer#accept_nonblock may raise any error corresponding to accept(2) failure,
 * including Errno::EAGAIN.
 * 
 * === See
 * * TCPServer#accept
 * * Socket#accept
 */
static VALUE
tcp_accept_nonblock(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_storage from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(from);
    return s_accept_nonblock(rb_cTCPSocket, fptr,
                             (struct sockaddr *)&from, &fromlen);
}

static VALUE
tcp_sysaccept(sock)
    VALUE sock;
{
    rb_io_t *fptr;
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
    rb_io_t *fptr;

    SafeStringValue(path);
    fd = ruby_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
	rb_sys_fail("socket(2)");
    }

    MEMZERO(&sockaddr, struct sockaddr_un, 1);
    sockaddr.sun_family = AF_UNIX;
    if (sizeof(sockaddr.sun_path) <= RSTRING(path)->len) {
        rb_raise(rb_eArgError, "too long unix socket path (max: %dbytes)",
            (int)sizeof(sockaddr.sun_path)-1);
    }
    strcpy(sockaddr.sun_path, StringValueCStr(path));

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
    if (server) {
        fptr->path = strdup(RSTRING(path)->ptr);
    }

    return sock;
}
#endif

static VALUE
ip_addr(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return ipaddr((struct sockaddr*)&addr);
}

static VALUE
ip_peeraddr(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return ipaddr((struct sockaddr*)&addr);
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
    rb_io_t *fptr;
    struct udp_arg arg;
    VALUE ret;

    rb_secure(3);
    arg.res = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    GetOpenFile(sock, fptr);
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
    rb_io_t *fptr;
    struct addrinfo *res0, *res;

    rb_secure(3);
    res0 = sock_addrinfo(host, port, SOCK_DGRAM, 0);
    GetOpenFile(sock, fptr);
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
    rb_io_t *fptr;
    FILE *f;
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
    f = GetWriteFile(fptr);
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

/*
 * call-seq:
 * 	udpsocket.recvfrom_nonblock(maxlen) => [mesg, sender_inet_addr]
 * 	udpsocket.recvfrom_nonblock(maxlen, flags) => [mesg, sender_inet_addr]
 * 
 * Receives up to _maxlen_ bytes from +udpsocket+ using recvfrom(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * _flags_ is zero or more of the +MSG_+ options.
 * The first element of the results, _mesg_, is the data received.
 * The second element, _sender_inet_addr_, is an array to represent the sender address.
 *
 * When recvfrom(2) returns 0,
 * Socket#recvfrom_nonblock returns an empty string as data.
 * It means an empty packet.
 * 
 * === Parameters
 * * +maxlen+ - the number of bytes to receive from the socket
 * * +flags+ - zero or more of the +MSG_+ options 
 * 
 * === Example
 * 	require 'socket'
 * 	s1 = UDPSocket.new
 * 	s1.bind("127.0.0.1", 0)
 * 	s2 = UDPSocket.new
 * 	s2.bind("127.0.0.1", 0)
 * 	s2.connect(*s1.addr.values_at(3,1))
 * 	s1.connect(*s2.addr.values_at(3,1))
 * 	s1.send "aaa", 0
 * 	IO.select([s2])
 * 	p s2.recvfrom_nonblock(10)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
 *
 * Refer to Socket#recvfrom for the exceptions that may be thrown if the call
 * to _recvfrom_nonblock_ fails. 
 *
 * UDPSocket#recvfrom_nonblock may raise any error corresponding to recvfrom(2) failure,
 * including Errno::EAGAIN.
 *
 * === See
 * * Socket#recvfrom
 */
static VALUE
udp_recvfrom_nonblock(int argc, VALUE *argv, VALUE sock)
{
    return s_recvfrom_nonblock(sock, argc, argv, RECV_IP);
}

#ifdef HAVE_SYS_UN_H
static VALUE
unix_init(sock, path)
    VALUE sock, path;
{
    return init_unixsock(sock, path, 0);
}

static const char *
unixpath(struct sockaddr_un *sockaddr, socklen_t len)
{
    if (sockaddr->sun_path < (char*)sockaddr + len)
        return sockaddr->sun_path;
    else
        return "";
}

static VALUE
unix_path(sock)
    VALUE sock;
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (fptr->path == 0) {
	struct sockaddr_un addr;
	socklen_t len = sizeof(addr);
	if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	    rb_sys_fail(0);
	fptr->path = strdup(unixpath(&addr, len));
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
#  define FD_PASSING_BY_MSG_CONTROL 1
#else
#  define FD_PASSING_BY_MSG_CONTROL 0
#endif

#if defined(HAVE_ST_MSG_ACCRIGHTS)
#  define FD_PASSING_BY_MSG_ACCRIGHTS 1
#else
#  define FD_PASSING_BY_MSG_ACCRIGHTS 0
#endif

static VALUE
unix_send_io(sock, val)
    VALUE sock, val;
{
#if defined(HAVE_SENDMSG) && (FD_PASSING_BY_MSG_CONTROL || FD_PASSING_BY_MSG_ACCRIGHTS)
    int fd;
    rb_io_t *fptr;
    struct msghdr msg;
    struct iovec vec[1];
    char buf[1];

#if FD_PASSING_BY_MSG_CONTROL
    struct {
	struct cmsghdr hdr;
        char pad[8+sizeof(int)+8];
    } cmsg;
#endif

    if (rb_obj_is_kind_of(val, rb_cIO)) {
        rb_io_t *valfptr;
	GetOpenFile(val, valfptr);
	fd = fileno(valfptr->f);
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
    msg.msg_controllen = CMSG_LEN(sizeof(int));
    msg.msg_flags = 0;
    MEMZERO((char*)&cmsg, char, sizeof(cmsg));
    cmsg.hdr.cmsg_len = CMSG_LEN(sizeof(int));
    cmsg.hdr.cmsg_level = SOL_SOCKET;
    cmsg.hdr.cmsg_type = SCM_RIGHTS;
    *(int *)CMSG_DATA(&cmsg.hdr) = fd;
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

#if defined(HAVE_RECVMSG) && FD_PASSING_BY_MSG_CONTROL
void
rsock_discard_cmsg_resource(struct msghdr *mh)
{
    struct cmsghdr *cmh;

    if (mh->msg_controllen == 0)
        return;

    for (cmh = CMSG_FIRSTHDR(mh); cmh != NULL; cmh = CMSG_NXTHDR(mh, cmh)) {
        if (cmh->cmsg_level == SOL_SOCKET && cmh->cmsg_type == SCM_RIGHTS) {
            int *fdp = (int *)CMSG_DATA(cmh);
            int *end = (int *)((char *)cmh + cmh->cmsg_len);
            while (fdp < end) {
                close(*fdp);
                fdp++;
            }
        }
    }
}
#endif

#if defined(HAVE_RECVMSG) && (FD_PASSING_BY_MSG_CONTROL || FD_PASSING_BY_MSG_ACCRIGHTS)
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
#if defined(HAVE_RECVMSG) && (FD_PASSING_BY_MSG_CONTROL || FD_PASSING_BY_MSG_ACCRIGHTS)
    VALUE klass, mode;
    rb_io_t *fptr;
    struct msghdr msg;
    struct iovec vec[2];
    char buf[1];

    int fd;
#if FD_PASSING_BY_MSG_CONTROL
    struct {
	struct cmsghdr hdr;
        char pad[8+sizeof(int)+8];
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

#if FD_PASSING_BY_MSG_CONTROL
    msg.msg_control = (caddr_t)&cmsg;
    msg.msg_controllen = CMSG_SPACE(sizeof(int));
    msg.msg_flags = 0;
    cmsg.hdr.cmsg_len = CMSG_LEN(sizeof(int));
    cmsg.hdr.cmsg_level = SOL_SOCKET;
    cmsg.hdr.cmsg_type = SCM_RIGHTS;
    *(int *)CMSG_DATA(&cmsg.hdr) = -1;
#else
    msg.msg_accrights = (caddr_t)&fd;
    msg.msg_accrightslen = sizeof(fd);
    fd = -1;
#endif

    if (recvmsg(fileno(fptr->f), &msg, 0) == -1)
	rb_sys_fail("recvmsg(2)");

#if FD_PASSING_BY_MSG_CONTROL
    if (msg.msg_controllen < sizeof(struct cmsghdr)) {
        rb_raise(rb_eSocket,
                 "file descriptor was not passed (msg_controllen=%d smaller than sizeof(struct cmsghdr)=%d)",
                 (int)msg.msg_controllen, (int)sizeof(struct cmsghdr));
    }
    if (cmsg.hdr.cmsg_level != SOL_SOCKET) {
      rb_raise(rb_eSocket,
          "file descriptor was not passed (cmsg_level=%d, %d expected)",
          cmsg.hdr.cmsg_level, SOL_SOCKET);
    }
    if (cmsg.hdr.cmsg_type != SCM_RIGHTS) {
      rb_raise(rb_eSocket,
          "file descriptor was not passed (cmsg_type=%d, %d expected)",
          cmsg.hdr.cmsg_type, SCM_RIGHTS);
    }
    if (msg.msg_controllen < CMSG_LEN(sizeof(int))) {
        rb_raise(rb_eSocket,
		 "file descriptor was not passed (msg_controllen=%d smaller than CMSG_LEN(sizeof(int))=%d)",
		 (int)msg.msg_controllen, (int)CMSG_LEN(sizeof(int)));
    }
    if (CMSG_SPACE(sizeof(int)) < msg.msg_controllen) {
	rb_raise(rb_eSocket,
		 "file descriptor was not passed (msg_controllen=%d bigger than CMSG_SPACE(sizeof(int))=%d)",
                 (int)msg.msg_controllen, (int)CMSG_SPACE(sizeof(int)));
    }
    if (cmsg.hdr.cmsg_len != CMSG_LEN(sizeof(int))) {
        rsock_discard_cmsg_resource(&msg);
        rb_raise(rb_eSocket,
                 "file descriptor was not passed (cmsg_len=%d, %d expected)",
                 (int)cmsg.hdr.cmsg_len, (int)CMSG_LEN(sizeof(int)));
    }
#else
    if (msg.msg_accrightslen != sizeof(fd)) {
	rb_raise(rb_eSocket,
            "file descriptor was not passed (accrightslen) : %d != %d",
            msg.msg_accrightslen, sizeof(fd));
    }
#endif

#if FD_PASSING_BY_MSG_CONTROL
    fd = *(int *)CMSG_DATA(&cmsg.hdr);
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
    rb_io_t *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return s_accept(rb_cUNIXSocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

/*
 * call-seq:
 * 	unixserver.accept_nonblock => unixsocket
 * 
 * Accepts an incoming connection using accept(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * It returns an accepted UNIXSocket for the incoming connection.
 * 
 * === Example
 * 	require 'socket'
 * 	serv = UNIXServer.new("/tmp/sock")
 * 	begin
 * 	  sock = serv.accept_nonblock
 * 	rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
 * 	  IO.select([serv])
 * 	  retry
 * 	end
 * 	# sock is an accepted socket.
 * 
 * Refer to Socket#accept for the exceptions that may be thrown if the call
 * to UNIXServer#accept_nonblock fails. 
 *
 * UNIXServer#accept_nonblock may raise any error corresponding to accept(2) failure,
 * including Errno::EAGAIN.
 * 
 * === See
 * * UNIXServer#accept
 * * Socket#accept
 */
static VALUE
unix_accept_nonblock(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(from);
    return s_accept_nonblock(rb_cUNIXSocket, fptr,
                             (struct sockaddr *)&from, &fromlen);
}

static VALUE
unix_sysaccept(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return s_accept(0, fileno(fptr->f), (struct sockaddr*)&from, &fromlen);
}

static VALUE
unixaddr(sockaddr, len)
    struct sockaddr_un *sockaddr;
    socklen_t len;
{
    return rb_assoc_new(rb_str_new2("AF_UNIX"),
                        rb_str_new2(unixpath(sockaddr, len)));
}

static VALUE
unix_addr(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_un addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return unixaddr(&addr, len);
}

static VALUE
unix_peeraddr(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    struct sockaddr_un addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return unixaddr(&addr, len);
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
#if defined HAVE_SOCKETPAIR
    int d, t, p, sp[2];
    int ret;

    setup_domain_and_type(domain, &d, type, &t);
    p = NUM2INT(protocol);
    ret = socketpair(d, t, p, sp);
    if (ret < 0 && (errno == EMFILE || errno == ENFILE)) {
        rb_gc();
        ret = socketpair(d, t, p, sp);
    }
    if (ret < 0) {
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

/*
 * call-seq:
 * 	socket.connect(server_sockaddr) => 0
 * 
 * Requests a connection to be made on the given +server_sockaddr+. Returns 0 if
 * successful, otherwise an exception is raised.
 *  
 * === Parameter
 * * +server_sockaddr+ - the +struct+ sockaddr contained in a string
 * 
 * === Example:
 * 	# Pull down Google's web page
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 80, 'www.google.com' )
 * 	socket.connect( sockaddr )
 * 	socket.write( "GET / HTTP/1.0\r\n\r\n" )
 * 	results = socket.read 
 * 
 * === Unix-based Exceptions
 * On unix-based systems the following system exceptions may be raised if 
 * the call to _connect_ fails:
 * * Errno::EACCES - search permission is denied for a component of the prefix
 *   path or write access to the +socket+ is denided
 * * Errno::EADDRINUSE - the _sockaddr_ is already in use
 * * Errno::EADDRNOTAVAIL - the specified _sockaddr_ is not available from the
 *   local machine
 * * Errno::EAFNOSUPPORT - the specified _sockaddr_ is not a valid address for 
 *   the address family of the specified +socket+
 * * Errno::EALREADY - a connection is already in progress for the specified
 *   socket
 * * Errno::EBADF - the +socket+ is not a valid file descriptor
 * * Errno::ECONNREFUSED - the target _sockaddr_ was not listening for connections
 *   refused the connection request
 * * Errno::ECONNRESET - the remote host reset the connection request
 * * Errno::EFAULT - the _sockaddr_ cannot be accessed
 * * Errno::EHOSTUNREACH - the destination host cannot be reached (probably 
 *   because the host is down or a remote router cannot reach it)
 * * Errno::EINPROGRESS - the O_NONBLOCK is set for the +socket+ and the
 *   connection cnanot be immediately established; the connection will be
 *   established asynchronously
 * * Errno::EINTR - the attempt to establish the connection was interrupted by
 *   delivery of a signal that was caught; the connection will be established
 *   asynchronously
 * * Errno::EISCONN - the specified +socket+ is already connected
 * * Errno::EINVAL - the address length used for the _sockaddr_ is not a valid
 *   length for the address family or there is an invalid family in _sockaddr_ 
 * * Errno::ENAMETOOLONG - the pathname resolved had a length which exceeded
 *   PATH_MAX
 * * Errno::ENETDOWN - the local interface used to reach the destination is down
 * * Errno::ENETUNREACH - no route to the network is present
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOSR - there were insufficient STREAMS resources available to 
 *   complete the operation
 * * Errno::ENOTSOCK - the +socket+ argument does not refer to a socket
 * * Errno::EOPNOTSUPP - the calling +socket+ is listening and cannot be connected
 * * Errno::EPROTOTYPE - the _sockaddr_ has a different type than the socket 
 *   bound to the specified peer address
 * * Errno::ETIMEDOUT - the attempt to connect time out before a connection
 *   was made.
 * 
 * On unix-based systems if the address family of the calling +socket+ is
 * AF_UNIX the follow exceptions may be raised if the call to _connect_
 * fails:
 * * Errno::EIO - an i/o error occured while reading from or writing to the 
 *   file system
 * * Errno::ELOOP - too many symbolic links were encountered in translating
 *   the pathname in _sockaddr_
 * * Errno::ENAMETOOLLONG - a component of a pathname exceeded NAME_MAX 
 *   characters, or an entired pathname exceeded PATH_MAX characters
 * * Errno::ENOENT - a component of the pathname does not name an existing file
 *   or the pathname is an empty string
 * * Errno::ENOTDIR - a component of the path prefix of the pathname in _sockaddr_
 *   is not a directory 
 * 
 * === Windows Exceptions
 * On Windows systems the following system exceptions may be raised if 
 * the call to _connect_ fails:
 * * Errno::ENETDOWN - the network is down
 * * Errno::EADDRINUSE - the socket's local address is already in use
 * * Errno::EINTR - the socket was cancelled
 * * Errno::EINPROGRESS - a blocking socket is in progress or the service provider
 *   is still processing a callback function. Or a nonblocking connect call is 
 *   in progress on the +socket+.
 * * Errno::EALREADY - see Errno::EINVAL
 * * Errno::EADDRNOTAVAIL - the remote address is not a valid address, such as 
 *   ADDR_ANY TODO check ADDRANY TO INADDR_ANY
 * * Errno::EAFNOSUPPORT - addresses in the specified family cannot be used with
 *   with this +socket+
 * * Errno::ECONNREFUSED - the target _sockaddr_ was not listening for connections
 *   refused the connection request
 * * Errno::EFAULT - the socket's internal address or address length parameter
 *   is too small or is not a valid part of the user space address
 * * Errno::EINVAL - the +socket+ is a listening socket
 * * Errno::EISCONN - the +socket+ is already connected
 * * Errno::ENETUNREACH - the network cannot be reached from this host at this time
 * * Errno::EHOSTUNREACH - no route to the network is present
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOTSOCK - the +socket+ argument does not refer to a socket
 * * Errno::ETIMEDOUT - the attempt to connect time out before a connection
 *   was made.
 * * Errno::EWOULDBLOCK - the socket is marked as nonblocking and the 
 *   connection cannot be completed immediately
 * * Errno::EACCES - the attempt to connect the datagram socket to the 
 *   broadcast address failed
 * 
 * === See
 * * connect manual pages on unix-based systems
 * * connect function in Microsoft's Winsock functions reference
 */
static VALUE
sock_connect(sock, addr)
    VALUE sock, addr;
{
    rb_io_t *fptr;
    int fd;

    StringValue(addr);
    addr = rb_str_new4(addr);
    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
    if (ruby_connect(fd, (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len, 0) < 0) {
	rb_sys_fail("connect(2)");
    }

    return INT2FIX(0);
}

/*
 * call-seq:
 * 	socket.connect_nonblock(server_sockaddr) => 0
 * 
 * Requests a connection to be made on the given +server_sockaddr+ after
 * O_NONBLOCK is set for the underlying file descriptor.
 * Returns 0 if successful, otherwise an exception is raised.
 *  
 * === Parameter
 * * +server_sockaddr+ - the +struct+ sockaddr contained in a string
 * 
 * === Example:
 * 	# Pull down Google's web page
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new(AF_INET, SOCK_STREAM, 0)
 * 	sockaddr = Socket.sockaddr_in(80, 'www.google.com')
 * 	begin
 * 	  socket.connect_nonblock(sockaddr)
 * 	rescue Errno::EINPROGRESS
 * 	  IO.select(nil, [socket])
 * 	  begin
 * 	    socket.connect_nonblock(sockaddr)
 * 	  rescue Errno::EISCONN
 * 	  end
 * 	end
 * 	socket.write("GET / HTTP/1.0\r\n\r\n")
 * 	results = socket.read 
 * 
 * Refer to Socket#connect for the exceptions that may be thrown if the call
 * to _connect_nonblock_ fails. 
 *
 * Socket#connect_nonblock may raise any error corresponding to connect(2) failure,
 * including Errno::EINPROGRESS.
 *
 * === See
 * * Socket#connect
 */
static VALUE
sock_connect_nonblock(sock, addr)
    VALUE sock, addr;
{
    rb_io_t *fptr;
    int n;

    StringValue(addr);
    addr = rb_str_new4(addr);
    GetOpenFile(sock, fptr);
    rb_io_set_nonblock(fptr);
    n = connect(fileno(fptr->f), (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len);
    if (n < 0) {
	rb_sys_fail("connect(2)");
    }

    return INT2FIX(n);
}

/*
 * call-seq:
 * 	socket.bind(server_sockaddr) => 0
 * 
 * Binds to the given +struct+ sockaddr.
 * 
 * === Parameter
 * * +server_sockaddr+ - the +struct+ sockaddr contained in a string
 *
 * === Example
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.bind( sockaddr )
 *  
 * === Unix-based Exceptions
 * On unix-based based systems the following system exceptions may be raised if 
 * the call to _bind_ fails:
 * * Errno::EACCES - the specified _sockaddr_ is protected and the current
 *   user does not have permission to bind to it
 * * Errno::EADDRINUSE - the specified _sockaddr_ is already in use
 * * Errno::EADDRNOTAVAIL - the specified _sockaddr_ is not available from the
 *   local machine
 * * Errno::EAFNOSUPPORT - the specified _sockaddr_ isnot a valid address for
 *   the family of the calling +socket+
 * * Errno::EBADF - the _sockaddr_ specified is not a valid file descriptor
 * * Errno::EFAULT - the _sockaddr_ argument cannot be accessed
 * * Errno::EINVAL - the +socket+ is already bound to an address, and the 
 *   protocol does not support binding to the new _sockaddr_ or the +socket+
 *   has been shut down.
 * * Errno::EINVAL - the address length is not a valid length for the address
 *   family
 * * Errno::ENAMETOOLONG - the pathname resolved had a length which exceeded
 *   PATH_MAX
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOSR - there were insufficient STREAMS resources available to 
 *   complete the operation
 * * Errno::ENOTSOCK - the +socket+ does not refer to a socket
 * * Errno::EOPNOTSUPP - the socket type of the +socket+ does not support 
 *   binding to an address
 * 
 * On unix-based based systems if the address family of the calling +socket+ is
 * Socket::AF_UNIX the follow exceptions may be raised if the call to _bind_
 * fails:
 * * Errno::EACCES - search permission is denied for a component of the prefix
 *   path or write access to the +socket+ is denided
 * * Errno::EDESTADDRREQ - the _sockaddr_ argument is a null pointer
 * * Errno::EISDIR - same as Errno::EDESTADDRREQ
 * * Errno::EIO - an i/o error occurred
 * * Errno::ELOOP - too many symbolic links were encountered in translating
 *   the pathname in _sockaddr_
 * * Errno::ENAMETOOLLONG - a component of a pathname exceeded NAME_MAX 
 *   characters, or an entired pathname exceeded PATH_MAX characters
 * * Errno::ENOENT - a component of the pathname does not name an existing file
 *   or the pathname is an empty string
 * * Errno::ENOTDIR - a component of the path prefix of the pathname in _sockaddr_
 *   is not a directory
 * * Errno::EROFS - the name would reside on a read only filesystem
 * 
 * === Windows Exceptions
 * On Windows systems the following system exceptions may be raised if 
 * the call to _bind_ fails:
 * * Errno::ENETDOWN-- the network is down
 * * Errno::EACCES - the attempt to connect the datagram socket to the 
 *   broadcast address failed
 * * Errno::EADDRINUSE - the socket's local address is already in use
 * * Errno::EADDRNOTAVAIL - the specified address is not a valid address for this
 *   computer
 * * Errno::EFAULT - the socket's internal address or address length parameter
 *   is too small or is not a valid part of the user space addressed
 * * Errno::EINVAL - the +socket+ is already bound to an address
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOTSOCK - the +socket+ argument does not refer to a socket
 * 
 * === See
 * * bind manual pages on unix-based systems
 * * bind function in Microsoft's Winsock functions reference
 */ 
static VALUE
sock_bind(sock, addr)
    VALUE sock, addr;
{
    rb_io_t *fptr;

    StringValue(addr);
    GetOpenFile(sock, fptr);
    if (bind(fileno(fptr->f), (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len) < 0)
	rb_sys_fail("bind(2)");

    return INT2FIX(0);
}

/*
 * call-seq:
 * 	socket.listen( int ) => 0
 * 
 * Listens for connections, using the specified +int+ as the backlog. A call
 * to _listen_ only applies if the +socket+ is of type SOCK_STREAM or 
 * SOCK_SEQPACKET.
 * 
 * === Parameter
 * * +backlog+ - the maximum length of the queue for pending connections.
 * 
 * === Example 1
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.bind( sockaddr )
 * 	socket.listen( 5 )
 * 
 * === Example 2 (listening on an arbitary port, unix-based systems only):
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	socket.listen( 1 )
 * 
 * === Unix-based Exceptions
 * On unix based systems the above will work because a new +sockaddr+ struct
 * is created on the address ADDR_ANY, for an arbitrary port number as handed
 * off by the kernel. It will not work on Windows, because Windows requires that
 * the +socket+ is bound by calling _bind_ before it can _listen_.
 * 
 * If the _backlog_ amount exceeds the implementation-dependent maximum
 * queue length, the implementation's maximum queue length will be used.
 * 
 * On unix-based based systems the following system exceptions may be raised if the
 * call to _listen_ fails:
 * * Errno::EBADF - the _socket_ argument is not a valid file descriptor
 * * Errno::EDESTADDRREQ - the _socket_ is not bound to a local address, and 
 *   the protocol does not support listening on an unbound socket
 * * Errno::EINVAL - the _socket_ is already connected
 * * Errno::ENOTSOCK - the _socket_ argument does not refer to a socket
 * * Errno::EOPNOTSUPP - the _socket_ protocol does not support listen
 * * Errno::EACCES - the calling process does not have approriate privileges
 * * Errno::EINVAL - the _socket_ has been shut down
 * * Errno::ENOBUFS - insufficient resources are available in the system to 
 *   complete the call
 * 
 * === Windows Exceptions
 * On Windows systems the following system exceptions may be raised if 
 * the call to _listen_ fails:
 * * Errno::ENETDOWN - the network is down
 * * Errno::EADDRINUSE - the socket's local address is already in use. This 
 *   usually occurs during the execution of _bind_ but could be delayed
 *   if the call to _bind_ was to a partially wildcard address (involving
 *   ADDR_ANY) and if a specific address needs to be commmitted at the 
 *   time of the call to _listen_
 * * Errno::EINPROGRESS - a Windows Sockets 1.1 call is in progress or the
 *   service provider is still processing a callback function
 * * Errno::EINVAL - the +socket+ has not been bound with a call to _bind_.
 * * Errno::EISCONN - the +socket+ is already connected
 * * Errno::EMFILE - no more socket descriptors are available
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOTSOC - +socket+ is not a socket
 * * Errno::EOPNOTSUPP - the referenced +socket+ is not a type that supports
 *   the _listen_ method
 * 
 * === See
 * * listen manual pages on unix-based systems
 * * listen function in Microsoft's Winsock functions reference
 */
static VALUE
sock_listen(sock, log)
    VALUE sock, log;
{
    rb_io_t *fptr;
    int backlog;

    rb_secure(4);
    backlog = NUM2INT(log);
    GetOpenFile(sock, fptr);
    if (listen(fileno(fptr->f), backlog) < 0)
	rb_sys_fail("listen(2)");

    return INT2FIX(0);
}

/*
 * call-seq:
 * 	socket.recvfrom(maxlen) => [mesg, sender_sockaddr]
 * 	socket.recvfrom(maxlen, flags) => [mesg, sender_sockaddr]
 * 
 * Receives up to _maxlen_ bytes from +socket+. _flags_ is zero or more
 * of the +MSG_+ options. The first element of the results, _mesg_, is the data
 * received. The second element, _sender_sockaddr_, contains protocol-specific information
 * on the sender.
 * 
 * === Parameters
 * * +maxlen+ - the number of bytes to receive from the socket
 * * +flags+ - zero or more of the +MSG_+ options 
 * 
 * === Example
 * 	# In one file, start this first
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.bind( sockaddr )
 * 	socket.listen( 5 )
 * 	client, client_sockaddr = socket.accept
 * 	data = client.recvfrom( 20 )[0].chomp
 * 	puts "I only received 20 bytes '#{data}'"
 * 	sleep 1
 * 	socket.close
 * 
 * 	# In another file, start this second
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.connect( sockaddr )
 * 	socket.puts "Watch this get cut short!"
 * 	socket.close 
 * 
 * === Unix-based Exceptions
 * On unix-based based systems the following system exceptions may be raised if the
 * call to _recvfrom_ fails:
 * * Errno::EAGAIN - the +socket+ file descriptor is marked as O_NONBLOCK and no
 *   data is waiting to be received; or MSG_OOB is set and no out-of-band data
 *   is available and either the +socket+ file descriptor is marked as 
 *   O_NONBLOCK or the +socket+ does not support blocking to wait for 
 *   out-of-band-data
 * * Errno::EWOULDBLOCK - see Errno::EAGAIN
 * * Errno::EBADF - the +socket+ is not a valid file descriptor
 * * Errno::ECONNRESET - a connection was forcibly closed by a peer
 * * Errno::EFAULT - the socket's internal buffer, address or address length 
 *   cannot be accessed or written
 * * Errno::EINTR - a signal interupted _recvfrom_ before any data was available
 * * Errno::EINVAL - the MSG_OOB flag is set and no out-of-band data is available
 * * Errno::EIO - an i/o error occurred while reading from or writing to the 
 *   filesystem
 * * Errno::ENOBUFS - insufficient resources were available in the system to 
 *   perform the operation
 * * Errno::ENOMEM - insufficient memory was available to fulfill the request
 * * Errno::ENOSR - there were insufficient STREAMS resources available to 
 *   complete the operation
 * * Errno::ENOTCONN - a receive is attempted on a connection-mode socket that
 *   is not connected
 * * Errno::ENOTSOCK - the +socket+ does not refer to a socket
 * * Errno::EOPNOTSUPP - the specified flags are not supported for this socket type
 * * Errno::ETIMEDOUT - the connection timed out during connection establishment
 *   or due to a transmission timeout on an active connection
 * 
 * === Windows Exceptions
 * On Windows systems the following system exceptions may be raised if 
 * the call to _recvfrom_ fails:
 * * Errno::ENETDOWN - the network is down
 * * Errno::EFAULT - the internal buffer and from parameters on +socket+ are not
 *   part of the user address space, or the internal fromlen parameter is
 *   too small to accomodate the peer address
 * * Errno::EINTR - the (blocking) call was cancelled by an internal call to
 *   the WinSock function WSACancelBlockingCall
 * * Errno::EINPROGRESS - a blocking Windows Sockets 1.1 call is in progress or 
 *   the service provider is still processing a callback function
 * * Errno::EINVAL - +socket+ has not been bound with a call to _bind_, or an
 *   unknown flag was specified, or MSG_OOB was specified for a socket with
 *   SO_OOBINLINE enabled, or (for byte stream-style sockets only) the internal
 *   len parameter on +socket+ was zero or negative
 * * Errno::EISCONN - +socket+ is already connected. The call to _recvfrom_ is
 *   not permitted with a connected socket on a socket that is connetion 
 *   oriented or connectionless.
 * * Errno::ENETRESET - the connection has been broken due to the keep-alive 
 *   activity detecting a failure while the operation was in progress.
 * * Errno::EOPNOTSUPP - MSG_OOB was specified, but +socket+ is not stream-style
 *   such as type SOCK_STREAM. OOB data is not supported in the communication
 *   domain associated with +socket+, or +socket+ is unidirectional and 
 *   supports only send operations
 * * Errno::ESHUTDOWN - +socket+ has been shutdown. It is not possible to 
 *   call _recvfrom_ on a socket after _shutdown_ has been invoked.
 * * Errno::EWOULDBLOCK - +socket+ is marked as nonblocking and a  call to 
 *   _recvfrom_ would block.
 * * Errno::EMSGSIZE - the message was too large to fit into the specified buffer
 *   and was truncated.
 * * Errno::ETIMEDOUT - the connection has been dropped, because of a network
 *   failure or because the system on the other end went down without
 *   notice
 * * Errno::ECONNRESET - the virtual circuit was reset by the remote side 
 *   executing a hard or abortive close. The application should close the
 *   socket; it is no longer usable. On a UDP-datagram socket this error
 *   indicates a previous send operation resulted in an ICMP Port Unreachable
 *   message.
 */
static VALUE
sock_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recvfrom(sock, argc, argv, RECV_SOCKET);
}

/*
 * call-seq:
 * 	socket.recvfrom_nonblock(maxlen) => [mesg, sender_sockaddr]
 * 	socket.recvfrom_nonblock(maxlen, flags) => [mesg, sender_sockaddr]
 * 
 * Receives up to _maxlen_ bytes from +socket+ using recvfrom(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * _flags_ is zero or more of the +MSG_+ options.
 * The first element of the results, _mesg_, is the data received.
 * The second element, _sender_sockaddr_, contains protocol-specific information
 * on the sender.
 *
 * When recvfrom(2) returns 0, Socket#recvfrom_nonblock returns
 * an empty string as data.
 * The meaning depends on the socket: EOF on TCP, empty packet on UDP, etc.
 * 
 * === Parameters
 * * +maxlen+ - the number of bytes to receive from the socket
 * * +flags+ - zero or more of the +MSG_+ options 
 * 
 * === Example
 * 	# In one file, start this first
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new(AF_INET, SOCK_STREAM, 0)
 * 	sockaddr = Socket.sockaddr_in(2200, 'localhost')
 * 	socket.bind(sockaddr)
 * 	socket.listen(5)
 * 	client, client_sockaddr = socket.accept
 * 	begin
 * 	  pair = client.recvfrom_nonblock(20)
 * 	rescue Errno::EAGAIN, Errno::EWOULDBLOCK
 * 	  IO.select([client])
 * 	  retry
 * 	end
 * 	data = pair[0].chomp
 * 	puts "I only received 20 bytes '#{data}'"
 * 	sleep 1
 * 	socket.close
 * 
 * 	# In another file, start this second
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new(AF_INET, SOCK_STREAM, 0)
 * 	sockaddr = Socket.sockaddr_in(2200, 'localhost')
 * 	socket.connect(sockaddr)
 * 	socket.puts "Watch this get cut short!"
 * 	socket.close 
 * 
 * Refer to Socket#recvfrom for the exceptions that may be thrown if the call
 * to _recvfrom_nonblock_ fails. 
 *
 * Socket#recvfrom_nonblock may raise any error corresponding to recvfrom(2) failure,
 * including Errno::EAGAIN.
 *
 * === See
 * * Socket#recvfrom
 */
static VALUE
sock_recvfrom_nonblock(int argc, VALUE *argv, VALUE sock)
{
    return s_recvfrom_nonblock(sock, argc, argv, RECV_SOCKET);
}

/*
 * call-seq:
 * 	socket.accept => [ socket, string ]
 * 
 * Accepts an incoming connection returning an array containing a new
 * Socket object and a string holding the +struct+ sockaddr information about 
 * the caller.
 * 
 * === Example
 * 	# In one script, start this first
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.bind( sockaddr )
 * 	socket.listen( 5 )
 * 	client, client_sockaddr = socket.accept
 * 	puts "The client said, '#{client.readline.chomp}'"
 * 	client.puts "Hello from script one!"
 * 	socket.close
 * 
 * 	# In another script, start this second
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.connect( sockaddr )
 * 	socket.puts "Hello from script 2." 
 * 	puts "The server said, '#{socket.readline.chomp}'"
 * 	socket.close 
 * 
 * === Unix-based Exceptions
 * On unix-based based systems the following system exceptions may be raised if the
 * call to _accept_ fails:
 * * Errno::EAGAIN - O_NONBLOCK is set for the +socket+ file descriptor and no 
 *   connections are parent to be accepted
 * * Errno::EWOULDBLOCK - same as Errno::EAGAIN
 * * Errno::EBADF - the +socket+ is not a valid file descriptor
 * * Errno::ECONNABORTED - a connection has been aborted
 * * Errno::EFAULT - the socket's internal address or address length parameter 
 *   cannot be access or written
 * * Errno::EINTR - the _accept_ method was interrupted by a signal that was 
 *   caught before a valid connection arrived
 * * Errno::EINVAL - the +socket+ is not accepting connections
 * * Errno::EMFILE - OPEN_MAX file descriptors are currently open in the calling 
 *   process
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOMEM - there was insufficient memory available to complete the
 *   operation
 * * Errno::ENOSR - there was insufficient STREAMS resources available to 
 *   complete the operation
 * * Errno::ENFILE - the maximum number of file descriptors in the system are 
 *   already open
 * * Errno::ENOTSOCK - the +socket+ does not refer to a socket
 * * Errno::EOPNOTSUPP - the socket type for the calling +socket+ does not 
 *   support accept connections
 * * Errno::EPROTO - a protocol error has occurred
 * 
 * === Windows Exceptions
 * On Windows systems the following system exceptions may be raised if 
 * the call to _accept_ fails:
 * * Errno::ECONNRESET - an incoming connection was indicated, but was 
 *   terminated by the remote peer prior to accepting the connection
 * * Errno::EFAULT - the socket's internal address or address length parameter
 *   is too small or is not a valid part of the user space address
 * * Errno::EINVAL - the _listen_ method was not invoked prior to calling _accept_
 * * Errno::EINPROGRESS - a blocking Windows Sockets 1.1 call is in progress or
 *   the service provider is still processing a callback function
 * * Errno::EMFILE - the queue is not empty, upong etry to _accept_ and there are
 *   no socket descriptors available
 * * Errno::ENETDOWN - the network is down
 * * Errno::ENOBUFS - no buffer space is available
 * * Errno::ENOTSOCK - +socket+ is not a socket
 * * Errno::EOPNOTSUPP - +socket+ is not a type that supports connection-oriented
 *   service.
 * * Errno::EWOULDBLOCK - +socket+ is marked as nonblocking and no connections are
 *   present to be accepted
 * 
 * === See
 * * accept manual pages on unix-based systems
 * * accept function in Microsoft's Winsock functions reference
 */
static VALUE
sock_accept(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    VALUE sock2;
    char buf[1024];
    socklen_t len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept(rb_cSocket,fileno(fptr->f),(struct sockaddr*)buf,&len);

    return rb_assoc_new(sock2, rb_str_new(buf, len));
}

/*
 * call-seq:
 *    socket.accept_nonblock => [client_socket, client_sockaddr]
 * 
 * Accepts an incoming connection using accept(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * It returns an array containg the accpeted socket
 * for the incoming connection, _client_socket_,
 * and a string that contains the +struct+ sockaddr information
 * about the caller, _client_sockaddr_.
 * 
 * === Example
 * 	# In one script, start this first
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new(AF_INET, SOCK_STREAM, 0)
 * 	sockaddr = Socket.sockaddr_in(2200, 'localhost')
 * 	socket.bind(sockaddr)
 * 	socket.listen(5)
 * 	begin
 * 	  client_socket, client_sockaddr = socket.accept_nonblock
 * 	rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
 * 	  IO.select([socket])
 * 	  retry
 * 	end
 * 	puts "The client said, '#{client_socket.readline.chomp}'"
 * 	client_socket.puts "Hello from script one!"
 * 	socket.close
 *
 * 	# In another script, start this second
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new(AF_INET, SOCK_STREAM, 0)
 * 	sockaddr = Socket.sockaddr_in(2200, 'localhost')
 * 	socket.connect(sockaddr)
 * 	socket.puts "Hello from script 2." 
 * 	puts "The server said, '#{socket.readline.chomp}'"
 * 	socket.close
 * 
 * Refer to Socket#accept for the exceptions that may be thrown if the call
 * to _accept_nonblock_ fails. 
 *
 * Socket#accept_nonblock may raise any error corresponding to accept(2) failure,
 * including Errno::EAGAIN.
 * 
 * === See
 * * Socket#accept
 */
static VALUE
sock_accept_nonblock(sock)
    VALUE sock;
{
    rb_io_t *fptr;
    VALUE sock2;
    char buf[1024];
    socklen_t len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept_nonblock(rb_cSocket, fptr, (struct sockaddr *)buf, &len);
    return rb_assoc_new(sock2, rb_str_new(buf, len));
}

/*
 * call-seq:
 * 	socket.sysaccept => [client_socket_fd, client_sockaddr]
 * 
 * Accepts an incoming connection returnings an array containg the (integer)
 * file descriptor for the incoming connection, _client_socket_fd_,
 * and a string that contains the +struct+ sockaddr information
 * about the caller, _client_sockaddr_.
 * 
 * === Example
 * 	# In one script, start this first
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.bind( sockaddr )
 * 	socket.listen( 5 )
 * 	client_fd, client_sockaddr = socket.sysaccept
 * 	client_socket = Socket.for_fd( client_fd )
 * 	puts "The client said, '#{client_socket.readline.chomp}'"
 * 	client_socket.puts "Hello from script one!"
 * 	socket.close
 * 
 * 	# In another script, start this second
 * 	require 'socket'
 * 	include Socket::Constants
 * 	socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
 * 	sockaddr = Socket.pack_sockaddr_in( 2200, 'localhost' )
 * 	socket.connect( sockaddr )
 * 	socket.puts "Hello from script 2." 
 * 	puts "The server said, '#{socket.readline.chomp}'"
 * 	socket.close
 * 
 * Refer to Socket#accept for the exceptions that may be thrown if the call
 * to _sysaccept_ fails. 
 * 
 * === See
 * * Socket#accept
 */
static VALUE
sock_sysaccept(sock)
    VALUE sock;
{
    rb_io_t *fptr;
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
	ary = ipaddr(res->ai_addr);
	rb_ary_push(ary, INT2FIX(res->ai_family));
	rb_ary_push(ary, INT2FIX(res->ai_socktype));
	rb_ary_push(ary, INT2FIX(res->ai_protocol));
	rb_ary_push(base, ary);
    }
    return base;
}

/* Returns a String containing the binary value of a struct sockaddr. */
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

/*
 * Document-class: IPSocket
 *
 * IPSocket is the parent of TCPSocket and UDPSocket and implements
 * functionality common to them.
 *
 * A number of APIs in IPSocket, Socket, and their descendants return an
 * address as an array. The members of that array are:
 * - address family: A string like "AF_INET" or "AF_INET6" if it is one of the
 *   commonly used families, the string "unknown:#" (where `#' is the address
 *   family number) if it is not one of the common ones.  The strings map to
 *   the Socket::AF_* constants.
 * - port: The port number.
 * - name: Either the canonical name from looking the address up in the DNS, or
 *   the address in presentation format
 * - address: The address in presentation format (a dotted decimal string for
 *   IPv4, a hex string for IPv6).
 *
 * The address and port can be used directly to create sockets and to bind or
 * connect them to the address.
 */

/*
 * Document-class: Socket
 *
 * Socket contains a number of generally useful singleton methods and
 * constants, as well as offering low-level interfaces that can be used to
 * develop socket applications using protocols other than TCP, UDP, and UNIX
 * domain sockets.
 */

/*
 * Document-method: gethostbyname
 * call-seq: Socket.gethostbyname(host) => hostent
 *
 * Resolve +host+ and return name and address information for it, similarly to
 * gethostbyname(3). +host+ can be a domain name or the presentation format of
 * an address.
 *
 * Returns an array of information similar to that found in a +struct hostent+:
 *   - cannonical name: the cannonical name for host in the DNS, or a
 *     string representing the address
 *   - aliases: an array of aliases for the canonical name, there may be no aliases
 *   - address family: usually one of Socket::AF_INET or Socket::AF_INET6
 *   - address: a string, the binary value of the +struct sockaddr+ for this name, in
 *     the indicated address family
 *   - ...: if there are multiple addresses for this host,  a series of
 *     strings/+struct sockaddr+s may follow, not all necessarily in the same
 *     address family. Note that the fact that they may not be all in the same
 *     address family is a departure from the behaviour of gethostbyname(3).
 *
 * Note: I believe that the fact that the multiple addresses returned are not
 * necessarily in the same address family may be a bug, since if this function
 * actually called gethostbyname(3), ALL the addresses returned in the trailing
 * address list (h_addr_list from struct hostent) would be of the same address
 * family!  Examples from my system, OS X 10.3:
 *
 *   ["localhost", [], 30, "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\001", "\177\000\000\001"]
 *     and
 *   ["ensemble.local", [], 30, "\376\200\000\004\000\000\000\000\002\003\223\377\376\255\010\214", "\300\250{\232" ]
 *
 * Similar information can be returned by Socket.getaddrinfo if called as:
 *
 *    Socket.getaddrinfo(+host+, 0, Socket::AF_UNSPEC, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME)
 *
 * == Examples
 *   
 *   Socket.gethostbyname "example.com"                                                           
 *   => ["example.com", [], 2, "\300\000\"\246"]
 *   
 * This name has no DNS aliases, and a single IPv4 address.
 *   
 *   Socket.gethostbyname "smtp.telus.net"
 *   => ["smtp.svc.telus.net", ["smtp.telus.net"], 2, "\307\271\334\371"]
 *   
 * This name is an an alias so the canonical name is returned, as well as the
 * alias and a single IPv4 address.
 *   
 *   Socket.gethostbyname "localhost"
 *   => ["localhost", [], 30, "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\001", "\177\000\000\001"]
 *   
 * This machine has no aliases, returns an IPv6 address, and has an additional IPv4 address.
 *
 * +host+ can also be an IP address in presentation format, in which case a
 * reverse lookup is done on the address:
 *
 *   Socket.gethostbyname("127.0.0.1")
 *   => ["localhost", [], 2, "\177\000\000\001"]
 *
 *   Socket.gethostbyname("192.0.34.166")
 *   => ["www.example.com", [], 2, "\300\000\"\246"]
 *
 *
 * == See
 * See: Socket.getaddrinfo
 */
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

/*
 * Document-method: getservbyname
 * call-seq: Socket.getservbyname(name, proto="tcp") => port
 *
 * +name+ is a service name ("ftp", "telnet", ...) and proto is a protocol name
 * ("udp", "tcp", ...). '/etc/services' (or your system's equivalent) is
 * searched for a service for +name+ and +proto+, and the port number is
 * returned.
 *
 * Note that unlike Socket.getaddrinfo, +proto+ may not be specified using the
 * Socket::SOCK_* constants, a string must must be used.
 */
static VALUE
sock_s_getservbyaname(argc, argv)
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

/*
Documentation should explain the following:

  $ pp Socket.getaddrinfo("", 1, Socket::AF_UNSPEC, Socket::SOCK_STREAM, 0, Socket::AI_PASSIVE)
  [["AF_INET", 1, "0.0.0.0", "0.0.0.0", 2, 1, 6]]

  $ pp Socket.getaddrinfo(nil, 1, Socket::AF_UNSPEC, Socket::SOCK_STREAM, 0, Socket::AI_PASSIVE)
  [["AF_INET6", 1, "::", "::", 30, 1, 6],
   ["AF_INET", 1, "0.0.0.0", "0.0.0.0", 2, 1, 6]]

  $ pp Socket.getaddrinfo("localhost", 1, Socket::AF_UNSPEC, Socket::SOCK_STREAM, 0, Socket::AI_PASSIVE)
  [["AF_INET6", 1, "localhost", "::1", 30, 1, 6],
   ["AF_INET", 1, "localhost", "127.0.0.1", 2, 1, 6]]

  $ pp Socket.getaddrinfo("ensemble.local.", 1, Socket::AF_UNSPEC, Socket::SOCK_STREAM, 0, Socket::AI_PASSIVE)
  [["AF_INET", 1, "localhost", "192.168.123.154", 2, 1, 6]]

Does it?

API suggestion: this method has too many arguments, it would be backwards compatible and easier
to understand if limit args were accepted as :family=>..., :flags=>...
*/

/*
 * Document-method: getaddrinfo
 * call-seq: Socket.getaddrinfo(host, service, family=nil, socktype=nil, protocol=nil, flags=nil) => addrinfo
 *
 * Return address information for +host+ and +port+. The remaining arguments
 * are hints that limit the address information returned.
 *
 * This method corresponds closely to the POSIX.1g getaddrinfo() definition.
 *
 * === Parameters
 * - +host+ is a host name or an address string (dotted decimal for IPv4, or a hex string
 *   for IPv6) for which to return information. A nil is also allowed, its meaning
 *   depends on +flags+, see below.
 * - +service+ is a service name ("http", "ssh", ...), or 
 *   a port number (80, 22, ...), see Socket.getservbyname for more
 *   information. A nil is also allowed, meaning zero.
 * - +family+ limits the output to a specific address family, one of the
 *   Socket::AF_* constants. Socket::AF_INET (IPv4) and Socket::AF_INET6 (IPv6)
 *   are the most commonly used families. You will usually pass either nil or
 *   Socket::AF_UNSPEC, allowing the IPv6 information to be returned first if
 *   +host+ is reachable via IPv6, and IPv4 information otherwise.  The two
 *   strings "AF_INET" or "AF_INET6" are also allowed, they are converted to
 *   their respective Socket::AF_* constants.
 * - +socktype+ limits the output to a specific type of socket, one of the
 *   Socket::SOCK_* constants. Socket::SOCK_STREAM (for TCP) and
 *   Socket::SOCK_DGRAM (for UDP) are the most commonly used socket types. If
 *   nil, then information for all types of sockets supported by +service+ will
 *   be returned. You will usually know what type of socket you intend to
 *   create, and should pass that socket type in.
 * - +protocol+ limits the output to a specific protocol numpber, one of the
 *   Socket::IPPROTO_* constants. It is usually implied by the socket type
 *   (Socket::SOCK_STREAM => Socket::IPPROTO_TCP, ...), if you pass other than
 *   nil you already know what this is for.
 * - +flags+ is one of the Socket::AI_* constants. They mean:
 *   - Socket::AI_PASSIVE: when set, if +host+ is nil the 'any' address will be
 *     returned, Socket::INADDR_ANY or 0 for IPv4, "0::0" or "::" for IPv6.  This
 *     address is suitable for use by servers that will bind their socket and do
 *     a passive listen, thus the name of the flag. Otherwise the local or
 *     loopback address will be returned, this is "127.0.0.1" for IPv4 and "::1'
 *     for IPv6.
 *   - ...
 *
 *
 * === Returns
 *
 * Returns an array of arrays, where each subarray contains:
 * - address family, a string like "AF_INET" or "AF_INET6"
 * - port number, the port number for +service+
 * - host name, either a canonical name for +host+, or it's address in presentation
 *   format if the address could not be looked up.
 * - host IP, the address of +host+ in presentation format
 * - address family, as a numeric value (one of the Socket::AF_* constants).
 * - socket type, as a numeric value (one of the Socket::SOCK_* constants).
 * - protocol number, as a numeric value (one of the Socket::IPPROTO_* constants).
 *
 * The first four values are identical to what is commonly returned as an
 * address array, see IPSocket for more information.
 *
 * === Examples
 *
 * Not all input combinations are valid, and while there are many combinations,
 * only a few cases are common.
 *
 * A typical client will call getaddrinfo with the +host+ and +service+ it
 * wants to connect to. It knows that it will attempt to connect with either
 * TCP or UDP, and specifies +socktype+ accordingly. It loops through all
 * returned addresses, and try to connect to them in turn:
 *
 *   addrinfo = Socket::getaddrinfo('www.example.com', 'www', nil, Socket::SOCK_STREAM)
 *   addrinfo.each do |af, port, name, addr|
 *     begin
 *       sock = TCPSocket.new(addr, port)
 *       # ...
 *       exit 1
 *     rescue
 *     end
 *   end
 *
 * With UDP you don't know if connect suceeded, but if communication fails,
 * the next address can be tried.
 *
 * A typical server will call getaddrinfo with a +host+ of nil, the +service+
 * it listens to, and a +flags+ of Socket::AI_PASSIVE. It will listen for
 * connections on the first returned address:
 *   addrinfo = Socket::getaddrinfo(nil, 'www', nil, Socket::SOCK_STREAM, nil, Socket::AI_PASSIVE)
 *   af, port, name, addr = addrinfo.first
 *   sock = TCPServer(addr, port)
 *   while( client = s.accept )
 *     # ...
 *   end
 */
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
	rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));
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
    rb_raise(rb_eSocket, "getaddrinfo: %s", gai_strerror(error));

  error_exit_name:
    if (res) freeaddrinfo(res);
    rb_raise(rb_eSocket, "getnameinfo: %s", gai_strerror(error));
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
    if (RSTRING_LEN(addr) < 
        (char*)&((struct sockaddr *)sockaddr)->sa_family +
        sizeof(((struct sockaddr *)sockaddr)->sa_family) -
        (char*)sockaddr)
        rb_raise(rb_eArgError, "too short sockaddr");
    if (((struct sockaddr *)sockaddr)->sa_family != AF_INET
#ifdef INET6
        && ((struct sockaddr *)sockaddr)->sa_family != AF_INET6
#endif
        ) {
#ifdef INET6
        rb_raise(rb_eArgError, "not an AF_INET/AF_INET6 sockaddr");
#else
        rb_raise(rb_eArgError, "not an AF_INET sockaddr");
#endif
    }
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
    char *sun_path;
    VALUE addr;

    MEMZERO(&sockaddr, struct sockaddr_un, 1);
    sockaddr.sun_family = AF_UNIX;
    sun_path = StringValueCStr(path);
    if (sizeof(sockaddr.sun_path) <= strlen(sun_path)) {
        rb_raise(rb_eArgError, "too long unix socket path (max: %dbytes)",
            (int)sizeof(sockaddr.sun_path)-1);
    }
    strncpy(sockaddr.sun_path, sun_path, sizeof(sockaddr.sun_path)-1);
    addr = rb_str_new((char*)&sockaddr, sizeof(sockaddr));
    OBJ_INFECT(addr, path);

    return addr;
}

static VALUE
sock_s_unpack_sockaddr_un(self, addr)
    VALUE self, addr;
{
    struct sockaddr_un * sockaddr;
    const char *sun_path;
    VALUE path;

    sockaddr = (struct sockaddr_un*)StringValuePtr(addr);
    if (RSTRING_LEN(addr) < 
        (char*)&((struct sockaddr *)sockaddr)->sa_family +
        sizeof(((struct sockaddr *)sockaddr)->sa_family) -
        (char*)sockaddr)
        rb_raise(rb_eArgError, "too short sockaddr");
    if (((struct sockaddr *)sockaddr)->sa_family != AF_UNIX) {
        rb_raise(rb_eArgError, "not an AF_UNIX sockaddr");
    }
    if (sizeof(struct sockaddr_un) < RSTRING(addr)->len) {
        rb_raise(rb_eTypeError, "too long sockaddr_un - %ld longer than %d",
		 RSTRING(addr)->len, sizeof(struct sockaddr_un));
    }
    sun_path = unixpath(sockaddr, RSTRING(addr)->len);
    if (sizeof(struct sockaddr_un) == RSTRING(addr)->len &&
        sun_path == sockaddr->sun_path &&
        sun_path + strlen(sun_path) == RSTRING(addr)->ptr + RSTRING(addr)->len) {
        rb_raise(rb_eArgError, "sockaddr_un.sun_path not NUL terminated");
    }
    path = rb_str_new2(sun_path);
    OBJ_INFECT(path, addr);
    return path;
}
#endif

static VALUE mConst;

static void
sock_define_const(name, value)
    const char *name;
    int value;
{
    rb_define_const(rb_cSocket, name, INT2FIX(value));
    rb_define_const(mConst, name, INT2FIX(value));
}

/*
 * Class +Socket+ provides access to the underlying operating system
 * socket implementations. It can be used to provide more operating system
 * specific functionality than the protocol-specific socket classes but at the
 * expense of greater complexity. In particular, the class handles addresses
 * using +struct sockaddr+ structures packed into Ruby strings, which can be
 * a joy to manipulate.
 * 
 * === Exception Handling
 * Ruby's implementation of +Socket+ causes an exception to be raised
 * based on the error generated by the system dependent implementation.
 * This is why the methods are documented in a way that isolate
 * Unix-based system exceptions from Windows based exceptions. If more
 * information on particular exception is needed please refer to the 
 * Unix manual pages or the Windows WinSock reference.
 * 
 * 
 * === Documentation by
 * * Zach Dennis
 * * Sam Roberts
 * * <em>Programming Ruby</em> from The Pragmatic Bookshelf.  
 * 
 * Much material in this documentation is taken with permission from  
 * <em>Programming Ruby</em> from The Pragmatic Bookshelf.  
 */
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
    rb_define_method(rb_cBasicSocket, "recv_nonblock", bsock_recv_nonblock, -1);

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
    rb_define_method(rb_cTCPServer, "accept_nonblock", tcp_accept_nonblock, 0);
    rb_define_method(rb_cTCPServer, "sysaccept", tcp_sysaccept, 0);
    rb_define_method(rb_cTCPServer, "initialize", tcp_svr_init, -1);
    rb_define_method(rb_cTCPServer, "listen", sock_listen, 1);

    rb_cUDPSocket = rb_define_class("UDPSocket", rb_cIPSocket);
    rb_define_global_const("UDPsocket", rb_cUDPSocket);
    rb_define_method(rb_cUDPSocket, "initialize", udp_init, -1);
    rb_define_method(rb_cUDPSocket, "connect", udp_connect, 2);
    rb_define_method(rb_cUDPSocket, "bind", udp_bind, 2);
    rb_define_method(rb_cUDPSocket, "send", udp_send, -1);
    rb_define_method(rb_cUDPSocket, "recvfrom_nonblock", udp_recvfrom_nonblock, -1);

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
    rb_define_method(rb_cUNIXServer, "accept_nonblock", unix_accept_nonblock, 0);
    rb_define_method(rb_cUNIXServer, "sysaccept", unix_sysaccept, 0);
    rb_define_method(rb_cUNIXServer, "listen", sock_listen, 1);
#endif

    rb_cSocket = rb_define_class("Socket", rb_cBasicSocket);

    rb_define_method(rb_cSocket, "initialize", sock_initialize, 3);
    rb_define_method(rb_cSocket, "connect", sock_connect, 1);
    rb_define_method(rb_cSocket, "connect_nonblock", sock_connect_nonblock, 1);
    rb_define_method(rb_cSocket, "bind", sock_bind, 1);
    rb_define_method(rb_cSocket, "listen", sock_listen, 1);
    rb_define_method(rb_cSocket, "accept", sock_accept, 0);
    rb_define_method(rb_cSocket, "accept_nonblock", sock_accept_nonblock, 0);
    rb_define_method(rb_cSocket, "sysaccept", sock_sysaccept, 0);

    rb_define_method(rb_cSocket, "recvfrom", sock_recvfrom, -1);
    rb_define_method(rb_cSocket, "recvfrom_nonblock", sock_recvfrom_nonblock, -1);

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
#ifdef AF_LOCAL
    sock_define_const("AF_LOCAL", AF_LOCAL);
#endif
#ifdef PF_LOCAL
    sock_define_const("PF_LOCAL", PF_LOCAL);
#endif
#ifdef AF_IMPLINK
    sock_define_const("AF_IMPLINK", AF_IMPLINK);
#endif
#ifdef PF_IMPLINK
    sock_define_const("PF_IMPLINK", PF_IMPLINK);
#endif
#ifdef AF_PUP
    sock_define_const("AF_PUP", AF_PUP);
#endif
#ifdef PF_PUP
    sock_define_const("PF_PUP", PF_PUP);
#endif
#ifdef AF_CHAOS
    sock_define_const("AF_CHAOS", AF_CHAOS);
#endif
#ifdef PF_CHAOS
    sock_define_const("PF_CHAOS", PF_CHAOS);
#endif
#ifdef AF_NS
    sock_define_const("AF_NS", AF_NS);
#endif
#ifdef PF_NS
    sock_define_const("PF_NS", PF_NS);
#endif
#ifdef AF_ISO
    sock_define_const("AF_ISO", AF_ISO);
#endif
#ifdef PF_ISO
    sock_define_const("PF_ISO", PF_ISO);
#endif
#ifdef AF_OSI
    sock_define_const("AF_OSI", AF_OSI);
#endif
#ifdef PF_OSI
    sock_define_const("PF_OSI", PF_OSI);
#endif
#ifdef AF_ECMA
    sock_define_const("AF_ECMA", AF_ECMA);
#endif
#ifdef PF_ECMA
    sock_define_const("PF_ECMA", PF_ECMA);
#endif
#ifdef AF_DATAKIT
    sock_define_const("AF_DATAKIT", AF_DATAKIT);
#endif
#ifdef PF_DATAKIT
    sock_define_const("PF_DATAKIT", PF_DATAKIT);
#endif
#ifdef AF_CCITT
    sock_define_const("AF_CCITT", AF_CCITT);
#endif
#ifdef PF_CCITT
    sock_define_const("PF_CCITT", PF_CCITT);
#endif
#ifdef AF_SNA
    sock_define_const("AF_SNA", AF_SNA);
#endif
#ifdef PF_SNA
    sock_define_const("PF_SNA", PF_SNA);
#endif
#ifdef AF_DEC
    sock_define_const("AF_DEC", AF_DEC);
#endif
#ifdef PF_DEC
    sock_define_const("PF_DEC", PF_DEC);
#endif
#ifdef AF_DLI
    sock_define_const("AF_DLI", AF_DLI);
#endif
#ifdef PF_DLI
    sock_define_const("PF_DLI", PF_DLI);
#endif
#ifdef AF_LAT
    sock_define_const("AF_LAT", AF_LAT);
#endif
#ifdef PF_LAT
    sock_define_const("PF_LAT", PF_LAT);
#endif
#ifdef AF_HYLINK
    sock_define_const("AF_HYLINK", AF_HYLINK);
#endif
#ifdef PF_HYLINK
    sock_define_const("PF_HYLINK", PF_HYLINK);
#endif
#ifdef AF_ROUTE
    sock_define_const("AF_ROUTE", AF_ROUTE);
#endif
#ifdef PF_ROUTE
    sock_define_const("PF_ROUTE", PF_ROUTE);
#endif
#ifdef AF_LINK
    sock_define_const("AF_LINK", AF_LINK);
#endif
#ifdef PF_LINK
    sock_define_const("PF_LINK", PF_LINK);
#endif
#ifdef AF_COIP
    sock_define_const("AF_COIP", AF_COIP);
#endif
#ifdef PF_COIP
    sock_define_const("PF_COIP", PF_COIP);
#endif
#ifdef AF_CNT
    sock_define_const("AF_CNT", AF_CNT);
#endif
#ifdef PF_CNT
    sock_define_const("PF_CNT", PF_CNT);
#endif
#ifdef AF_SIP
    sock_define_const("AF_SIP", AF_SIP);
#endif
#ifdef PF_SIP
    sock_define_const("PF_SIP", PF_SIP);
#endif
#ifdef AF_NDRV
    sock_define_const("AF_NDRV", AF_NDRV);
#endif
#ifdef PF_NDRV
    sock_define_const("PF_NDRV", PF_NDRV);
#endif
#ifdef AF_ISDN
    sock_define_const("AF_ISDN", AF_ISDN);
#endif
#ifdef PF_ISDN
    sock_define_const("PF_ISDN", PF_ISDN);
#endif
#ifdef AF_NATM
    sock_define_const("AF_NATM", AF_NATM);
#endif
#ifdef PF_NATM
    sock_define_const("PF_NATM", PF_NATM);
#endif
#ifdef AF_SYSTEM
    sock_define_const("AF_SYSTEM", AF_SYSTEM);
#endif
#ifdef PF_SYSTEM
    sock_define_const("PF_SYSTEM", PF_SYSTEM);
#endif
#ifdef AF_NETBIOS
    sock_define_const("AF_NETBIOS", AF_NETBIOS);
#endif
#ifdef PF_NETBIOS
    sock_define_const("PF_NETBIOS", PF_NETBIOS);
#endif
#ifdef AF_PPP
    sock_define_const("AF_PPP", AF_PPP);
#endif
#ifdef PF_PPP
    sock_define_const("PF_PPP", PF_PPP);
#endif
#ifdef AF_ATM
    sock_define_const("AF_ATM", AF_ATM);
#endif
#ifdef PF_ATM
    sock_define_const("PF_ATM", PF_ATM);
#endif
#ifdef AF_NETGRAPH
    sock_define_const("AF_NETGRAPH", AF_NETGRAPH);
#endif
#ifdef PF_NETGRAPH
    sock_define_const("PF_NETGRAPH", PF_NETGRAPH);
#endif
#ifdef AF_MAX
    sock_define_const("AF_MAX", AF_MAX);
#endif
#ifdef PF_MAX
    sock_define_const("PF_MAX", PF_MAX);
#endif
#ifdef AF_E164
    sock_define_const("AF_E164", AF_E164);
#endif
#ifdef PF_XTP
    sock_define_const("PF_XTP", PF_XTP);
#endif
#ifdef PF_RTIP
    sock_define_const("PF_RTIP", PF_RTIP);
#endif
#ifdef PF_PIP
    sock_define_const("PF_PIP", PF_PIP);
#endif
#ifdef PF_KEY
    sock_define_const("PF_KEY", PF_KEY);
#endif

    sock_define_const("MSG_OOB", MSG_OOB);
#ifdef MSG_PEEK
    sock_define_const("MSG_PEEK", MSG_PEEK);
#endif
#ifdef MSG_DONTROUTE
    sock_define_const("MSG_DONTROUTE", MSG_DONTROUTE);
#endif
#ifdef MSG_EOR
    sock_define_const("MSG_EOR", MSG_EOR);
#endif
#ifdef MSG_TRUNC
    sock_define_const("MSG_TRUNC", MSG_TRUNC);
#endif
#ifdef MSG_CTRUNC
    sock_define_const("MSG_CTRUNC", MSG_CTRUNC);
#endif
#ifdef MSG_WAITALL
    sock_define_const("MSG_WAITALL", MSG_WAITALL);
#endif
#ifdef MSG_DONTWAIT
    sock_define_const("MSG_DONTWAIT", MSG_DONTWAIT);
#endif
#ifdef MSG_EOF
    sock_define_const("MSG_EOF", MSG_EOF);
#endif
#ifdef MSG_FLUSH
    sock_define_const("MSG_FLUSH", MSG_FLUSH);
#endif
#ifdef MSG_HOLD
    sock_define_const("MSG_HOLD", MSG_HOLD);
#endif
#ifdef MSG_SEND
    sock_define_const("MSG_SEND", MSG_SEND);
#endif
#ifdef MSG_HAVEMORE
    sock_define_const("MSG_HAVEMORE", MSG_HAVEMORE);
#endif
#ifdef MSG_RCVMORE
    sock_define_const("MSG_RCVMORE", MSG_RCVMORE);
#endif
#ifdef MSG_COMPAT
    sock_define_const("MSG_COMPAT", MSG_COMPAT);
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
#ifdef IPPROTO_AH
    sock_define_const("IPPROTO_AH", IPPROTO_AH);
#endif
#ifdef IPPROTO_DSTOPTS
    sock_define_const("IPPROTO_DSTOPTS", IPPROTO_DSTOPTS);
#endif
#ifdef IPPROTO_ESP
    sock_define_const("IPPROTO_ESP", IPPROTO_ESP);
#endif
#ifdef IPPROTO_FRAGMENT
    sock_define_const("IPPROTO_FRAGMENT", IPPROTO_FRAGMENT);
#endif
#ifdef IPPROTO_HOPOPTS
    sock_define_const("IPPROTO_HOPOPTS", IPPROTO_HOPOPTS);
#endif
#ifdef IPPROTO_ICMPV6
    sock_define_const("IPPROTO_ICMPV6", IPPROTO_ICMPV6);
#endif
#ifdef IPPROTO_IPV6
    sock_define_const("IPPROTO_IPV6", IPPROTO_IPV6);
#endif
#ifdef IPPROTO_NONE
    sock_define_const("IPPROTO_NONE", IPPROTO_NONE);
#endif
#ifdef IPPROTO_ROUTING
    sock_define_const("IPPROTO_ROUTING", IPPROTO_ROUTING);
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
#ifdef SO_REUSEPORT
    sock_define_const("SO_REUSEPORT", SO_REUSEPORT);
#endif
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
#ifdef SO_ACCEPTCONN
    sock_define_const("SO_ACCEPTCONN", SO_ACCEPTCONN);
#endif
#ifdef SO_USELOOPBACK
    sock_define_const("SO_USELOOPBACK", SO_USELOOPBACK);
#endif
#ifdef SO_ACCEPTFILTER
    sock_define_const("SO_ACCEPTFILTER", SO_ACCEPTFILTER);
#endif
#ifdef SO_DONTTRUNC
    sock_define_const("SO_DONTTRUNC", SO_DONTTRUNC);
#endif
#ifdef SO_WANTMORE
    sock_define_const("SO_WANTMORE", SO_WANTMORE);
#endif
#ifdef SO_WANTOOBFLAG
    sock_define_const("SO_WANTOOBFLAG", SO_WANTOOBFLAG);
#endif
#ifdef SO_NREAD
    sock_define_const("SO_NREAD", SO_NREAD);
#endif
#ifdef SO_NKE
    sock_define_const("SO_NKE", SO_NKE);
#endif
#ifdef SO_NOSIGPIPE
    sock_define_const("SO_NOSIGPIPE", SO_NOSIGPIPE);
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
#ifdef EAI_OVERFLOW
    sock_define_const("EAI_OVERFLOW", EAI_OVERFLOW);
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
#ifdef AI_NUMERICSERV
    sock_define_const("AI_NUMERICSERV", AI_NUMERICSERV);
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
#ifdef IPV6_JOIN_GROUP
    sock_define_const("IPV6_JOIN_GROUP", IPV6_JOIN_GROUP);
#endif
#ifdef IPV6_LEAVE_GROUP
    sock_define_const("IPV6_LEAVE_GROUP", IPV6_LEAVE_GROUP);
#endif
#ifdef IPV6_MULTICAST_HOPS
    sock_define_const("IPV6_MULTICAST_HOPS", IPV6_MULTICAST_HOPS);
#endif
#ifdef IPV6_MULTICAST_IF
    sock_define_const("IPV6_MULTICAST_IF", IPV6_MULTICAST_IF);
#endif
#ifdef IPV6_MULTICAST_LOOP
    sock_define_const("IPV6_MULTICAST_LOOP", IPV6_MULTICAST_LOOP);
#endif
#ifdef IPV6_UNICAST_HOPS
    sock_define_const("IPV6_UNICAST_HOPS", IPV6_UNICAST_HOPS);
#endif
#ifdef IPV6_V6ONLY
    sock_define_const("IPV6_V6ONLY", IPV6_V6ONLY);
#endif
#ifdef IPV6_CHECKSUM
    sock_define_const("IPV6_CHECKSUM", IPV6_CHECKSUM);
#endif
#ifdef IPV6_DONTFRAG
    sock_define_const("IPV6_DONTFRAG", IPV6_DONTFRAG);
#endif
#ifdef IPV6_DSTOPTS
    sock_define_const("IPV6_DSTOPTS", IPV6_DSTOPTS);
#endif
#ifdef IPV6_HOPLIMIT
    sock_define_const("IPV6_HOPLIMIT", IPV6_HOPLIMIT);
#endif
#ifdef IPV6_HOPOPTS
    sock_define_const("IPV6_HOPOPTS", IPV6_HOPOPTS);
#endif
#ifdef IPV6_NEXTHOP
    sock_define_const("IPV6_NEXTHOP", IPV6_NEXTHOP);
#endif
#ifdef IPV6_PATHMTU
    sock_define_const("IPV6_PATHMTU", IPV6_PATHMTU);
#endif
#ifdef IPV6_PKTINFO
    sock_define_const("IPV6_PKTINFO", IPV6_PKTINFO);
#endif
#ifdef IPV6_RECVDSTOPTS
    sock_define_const("IPV6_RECVDSTOPTS", IPV6_RECVDSTOPTS);
#endif
#ifdef IPV6_RECVHOPLIMIT
    sock_define_const("IPV6_RECVHOPLIMIT", IPV6_RECVHOPLIMIT);
#endif
#ifdef IPV6_RECVHOPOPTS
    sock_define_const("IPV6_RECVHOPOPTS", IPV6_RECVHOPOPTS);
#endif
#ifdef IPV6_RECVPKTINFO
    sock_define_const("IPV6_RECVPKTINFO", IPV6_RECVPKTINFO);
#endif
#ifdef IPV6_RECVRTHDR
    sock_define_const("IPV6_RECVRTHDR", IPV6_RECVRTHDR);
#endif
#ifdef IPV6_RECVTCLASS
    sock_define_const("IPV6_RECVTCLASS", IPV6_RECVTCLASS);
#endif
#ifdef IPV6_RTHDR
    sock_define_const("IPV6_RTHDR", IPV6_RTHDR);
#endif
#ifdef IPV6_RTHDRDSTOPTS
    sock_define_const("IPV6_RTHDRDSTOPTS", IPV6_RTHDRDSTOPTS);
#endif
#ifdef IPV6_RTHDR_TYPE_0
    sock_define_const("IPV6_RTHDR_TYPE_0", IPV6_RTHDR_TYPE_0);
#endif
#ifdef IPV6_RECVPATHMTU
    sock_define_const("IPV6_RECVPATHMTU", IPV6_RECVPATHMTU);
#endif
#ifdef IPV6_TCLASS
    sock_define_const("IPV6_TCLASS", IPV6_TCLASS);
#endif
#ifdef IPV6_USE_MIN_MTU
    sock_define_const("IPV6_USE_MIN_MTU", IPV6_USE_MIN_MTU);
#endif
#ifdef INET_ADDRSTRLEN
    sock_define_const("INET_ADDRSTRLEN", INET_ADDRSTRLEN);
#endif
#ifdef INET6_ADDRSTRLEN
    sock_define_const("INET6_ADDRSTRLEN", INET6_ADDRSTRLEN);
#endif
}
