/************************************************

  socket.c -

  $Author$
  $Date$
  created at: Thu Mar 31 12:21:29 JST 1994

************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include <stdio.h>
#include <sys/types.h>
#ifndef NT
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#endif
#include <errno.h>
#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#endif

#ifdef USE_CWGUSI
extern int fileno(FILE *stream); /* <unix.mac.h> */
extern int rb_thread_select(int, fd_set*, fd_set*, fd_set*, struct timeval*); /* thread.c */
# include <sys/errno.h>
# include <GUSI.h>
#endif

#if defined(USE_THREAD) && defined(HAVE_FCNTL)
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

VALUE rb_cBasicSocket;
VALUE rb_cIPsocket;
VALUE rb_cTCPsocket;
VALUE rb_cTCPserver;
VALUE rb_cUDPsocket;
#ifdef AF_UNIX
VALUE rb_cUNIXsocket;
VALUE rb_cUNIXserver;
#endif
VALUE rb_cSocket;

static VALUE rb_eSocket;

#ifdef SOCKS
VALUE rb_cSOCKSsocket;
void SOCKSinit();
int Rconnect();
#endif

char *strdup();

#define INET_CLIENT 0
#define INET_SERVER 1
#define INET_SOCKS  2

#ifdef NT
static void
sock_finalize(fptr)
    OpenFile *fptr;
{
    SOCKET s;

    if (!fptr->f) return;
    s = fileno(fptr->f);
    free(fptr->f);
    if (fptr->f2) free(fptr->f2);
    closesocket(s);
}
#endif

static VALUE
sock_new(class, fd)
    VALUE class;
    int fd;
{
    OpenFile *fp;
    NEWOBJ(sock, struct RFile);
    OBJSETUP(sock, class, T_FILE);

    rb_secure(4);
    MakeOpenFile(sock, fp);
    fp->f = rb_fdopen(fd, "r");
#ifdef NT
    fp->finalize = sock_finalize;
#endif
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE;
    rb_io_unbuffered(fp);
    rb_obj_call_init((VALUE)sock);

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

    rb_secure(4);
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

    rb_secure(4);
    GetOpenFile(sock, fptr);
    if (fptr->f2 == 0) {
	return rb_io_close(sock);
    }
    if (shutdown(fileno(fptr->f), 0) == -1)
	rb_sys_fail(0);
    fptr->mode &= ~FMODE_READABLE;
#ifdef NT
    free(fptr->f);
#else
    fclose(fptr->f);
#endif
    fptr->f = fptr->f2;
    fptr->f2 = 0;

    return Qnil;
}

static VALUE
bsock_close_write(sock)
    VALUE sock;
{
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(sock, fptr);
    if (fptr->f2 == 0) {
	return rb_io_close(sock);
    }
    if (shutdown(fileno(fptr->f), 1) == -1)
	rb_sys_fail(0);
    fptr->mode &= ~FMODE_WRITABLE;
#ifdef NT
    free(fptr->f2);
#else
    fclose(fptr->f2);
#endif
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
    int level, option, len;
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
    int len = sizeof buf;
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
    int len = sizeof buf;
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
#ifdef USE_THREAD
    rb_thread_fd_writable(fd);
#endif
    m = rb_str2cstr(msg, &mlen);
    if (RTEST(to)) {
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
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
	    goto retry;
	}
	rb_sys_fail("send(2)");
    }
    return INT2FIX(n);
}

static VALUE ipaddr _((struct sockaddr_in*));
#ifdef HAVE_SYS_UN_H
static VALUE unixaddr _((struct sockaddr_un*));
#endif

enum sock_recv_type {
    RECV_RECV,			/* BasicSocket#recv(no from) */
    RECV_TCP,			/* TCPsocket#recvfrom */
    RECV_UDP,			/* UDPsocket#recvfrom */
    RECV_UNIX,			/* UNIXsocket#recvfrom */
    RECV_SOCKET,		/* Socket#recvfrom */
};

static VALUE
s_recv(sock, argc, argv, from)
    VALUE sock;
    int argc;
    VALUE *argv;
    enum sock_recv_type from;
{
    OpenFile *fptr;
    VALUE str;
    char buf[1024];
    int fd, alen = sizeof buf;
    VALUE len, flg;
    int flags;

    rb_scan_args(argc, argv, "11", &len, &flg);

    if (flg == Qnil) flags = 0;
    else             flags = NUM2INT(flg);

    str = rb_str_new(0, NUM2INT(len));

    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
#ifdef USE_THREAD
    rb_thread_wait_fd(fd);
#endif
    TRAP_BEG;
  retry:
    RSTRING(str)->len = recvfrom(fd, RSTRING(str)->ptr, RSTRING(str)->len, flags,
				 (struct sockaddr*)buf, &alen);
    TRAP_END;

    if (RSTRING(str)->len < 0) {
	switch (errno) {
	  case EINTR:
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
	    goto retry;
	}
	rb_sys_fail("recvfrom(2)");
    }
    rb_str_taint(str);
    switch (from) {
      case RECV_RECV:
	return (VALUE)str;
      case RECV_TCP:
	if (alen != sizeof(struct sockaddr_in)) {
	    rb_raise(rb_eTypeError, "sockaddr size differs - should not happen");
	}
	return rb_assoc_new(str, ipaddr((struct sockaddr_in *)buf));
      case RECV_UDP:
        {
	    VALUE addr = ipaddr((struct sockaddr_in *)buf);

	    return rb_assoc_new(str, rb_assoc_new(RARRAY(addr)->ptr[2],
						  RARRAY(addr)->ptr[1]));
	}
#ifdef HAVE_SYS_UN_H
      case RECV_UNIX:
	return rb_assoc_new(str, unixaddr((struct sockaddr_un *)buf));
#endif
      case RECV_SOCKET:
	return rb_assoc_new(str, rb_str_new(buf, alen));
    }
}

static VALUE
bsock_recv(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recv(sock, argc, argv, RECV_RECV);
}

static VALUE
mkipaddr(x)
    unsigned long x;
{
    char buf[16];

    x = ntohl(x);
    sprintf(buf, "%d.%d.%d.%d",
	    (int) (x>>24) & 0xff, (int) (x>>16) & 0xff,
	    (int) (x>> 8) & 0xff, (int) (x>> 0) & 0xff);
    return rb_str_new2(buf);
}

static VALUE
ipaddr(sockaddr)
    struct sockaddr_in *sockaddr;
{
    VALUE family, port, addr1, addr2;
    VALUE ary;
    struct hostent *hostent;

    family = rb_str_new2("AF_INET");
    hostent = gethostbyaddr((char*)&sockaddr->sin_addr.s_addr,
			    sizeof(sockaddr->sin_addr),
			    AF_INET);
    addr1 = 0;
    if (hostent) {
	addr1 = rb_str_new2(hostent->h_name);
    }
    addr2 = mkipaddr(sockaddr->sin_addr.s_addr);
    if (!addr1) addr1 = addr2;

    port = INT2FIX(ntohs(sockaddr->sin_port));
    ary = rb_ary_new3(4, family, port, addr1, addr2);

    return ary;
}

#ifndef HAVE_INET_ATON
static unsigned long
inet_aton(host, inp)
    char *host;
    struct in_addr *inp;
{
    int d1, d2, d3, d4;
    char ch;

    if (sscanf(host, "%d.%d.%d.%d%c", &d1, &d2, &d3, &d4, &ch) == 4 &&
	0 <= d1 && d1 <= 255 && 0 <= d2 && d2 <= 255 &&
	0 <= d3 && d3 <= 255 && 0 <= d4 && d4 <= 255) {
	inp->s_addr = htonl(
	    ((long) d1 << 24) | ((long) d2 << 16) |
	    ((long) d3 << 8) | ((long) d4 << 0));
	return 1;
    }
    return 0;
}
#endif

static void
setipaddr(name, addr)
    char *name;
    struct sockaddr_in *addr;
{
    struct hostent *hp;

    if (name[0] == 0) {
	addr->sin_addr.s_addr = INADDR_ANY;
    }
    else if (name[0] == '<' && strcmp(name, "<broadcast>") == 0) {
	addr->sin_addr.s_addr = INADDR_BROADCAST;
    }
    else if (inet_aton(name, &addr->sin_addr) != 0) {
	/* ok to set addr->sin_addr */
    }
    else {
	hp = gethostbyname(name);
	if (!hp) {
#ifdef HAVE_HSTRERROR
	    extern int h_errno;
	    rb_raise(rb_eSocket, (char *)hstrerror(h_errno));
#else
	    rb_raise(rb_eSocket, "host not found");
#endif
	}
	memcpy((char *) &addr->sin_addr, hp->h_addr, hp->h_length);
    }
}

#if defined(USE_THREAD) && defined(HAVE_FCNTL)
static int
thread_connect(fd, sockaddr, len, type)
    int fd;
    struct sockaddr *sockaddr;
    int len;
    int type;
{
    int status;
    int mode;
    fd_set fds;

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
    fcntl(fd, F_SETFL, mode|NONBLOCKING);
    for (;;) {
#ifdef SOCKS
	if (type == INET_SOCKS) {
	    status = Rconnect(fd, sockaddr, len);
	}
	else
#endif
	{
	    status = connect(fd, sockaddr, len);
	}
	if (status < 0) {
	    switch (errno) {
#ifdef EINPROGRESS
	      case EINPROGRESS:
#ifdef EAGAIN
	      case EAGAIN:
#endif
		FD_ZERO(&fds);
		FD_SET(fd, &fds);
		rb_thread_select(fd+1, 0, &fds, 0, 0);
		continue;
#endif

#ifdef EISCONN
	      case EISCONN:
#endif
#ifdef EALREADY
	      case EALREADY:
#endif
#if defined(EISCONN) || defined(EALREADY)
		status = 0;
		errno = 0;
		break;
#endif
	    }
	}
	mode &= ~NONBLOCKING;
	fcntl(fd, F_SETFL, mode);
	return status;
    }
}
#endif

static VALUE
open_inet(class, h, serv, type)
    VALUE class, h, serv;
    int type;
{
    char *host;
    struct hostent *hostent, _hostent;
    struct servent *servent, _servent;
    struct protoent *protoent;
    struct sockaddr_in sockaddr;
    int fd, status;
    int hostaddr, hostaddrPtr[2];
    int servport;
    char *syscall;

    if (h) {
	Check_SafeStr(h);
	host = RSTRING(h)->ptr;
	hostent = gethostbyname(host);
	if (hostent == NULL) {
	    inet_aton(host, &sockaddr.sin_addr);
	    hostaddr = sockaddr.sin_addr.s_addr;
	    if (hostaddr == -1) {
		if (type == INET_SERVER && !strlen(host))
		    hostaddr = INADDR_ANY;
		else {
#ifdef HAVE_HSTRERROR
		    extern int h_errno;
		    rb_raise(rb_eSocket, (char *)hstrerror(h_errno));
#else
		    rb_raise(rb_eSocket, "host not found");
#endif
		}
	    }
	    _hostent.h_addr_list = (char **)hostaddrPtr;
	    _hostent.h_addr_list[0] = (char *)&hostaddr;
	    _hostent.h_addr_list[1] = NULL;
	    _hostent.h_length = sizeof(hostaddr);
	    _hostent.h_addrtype = AF_INET;
	    hostent = &_hostent;
	}
    }
    servent = NULL;
    if (FIXNUM_P(serv)) {
	servport = FIX2UINT(serv);
	goto setup_servent;
    }
    servent = getservbyname(STR2CSTR(serv), "tcp");
    if (servent == NULL) {
	char *s = STR2CSTR(serv);
	char *end;

	servport = strtoul(s, &end, 0);
	if (*end != '\0') {
	    rb_raise(rb_eSocket, "no such servce %s", s);
	}
      setup_servent:
	_servent.s_port = htons(servport);
 	_servent.s_proto = "tcp";
	servent = &_servent;
    }
#ifdef __BEOS__
    fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
#else
    protoent = getprotobyname(servent->s_proto);
    if (protoent == NULL) {
	rb_raise(rb_eSocket, "no such proto %s", servent->s_proto);
    }

    fd = socket(AF_INET, SOCK_STREAM, protoent->p_proto);
#endif

    memset(&sockaddr, 0, sizeof(sockaddr));
    sockaddr.sin_family = AF_INET;
    if (h) {
	memcpy((char *)&(sockaddr.sin_addr.s_addr),
	       (char *) hostent->h_addr_list[0],
	       (size_t) hostent->h_length);
    }
    else {
	sockaddr.sin_addr.s_addr = INADDR_ANY;
    }
    sockaddr.sin_port = servent->s_port;

    if (type == INET_SERVER) {
	status = 1;
	setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,(char*)&status,sizeof(status));
	status = bind(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	syscall = "bind(2)";
    }
    else {
#if defined(USE_THREAD) && defined(HAVE_FCNTL)
        status = thread_connect(fd, (struct sockaddr*)&sockaddr,
			       sizeof(sockaddr), type);
#else
#ifdef SOCKS
	if (type == INET_SOCKS) {
	    status = Rconnect(fd, &sockaddr, sizeof(sockaddr));
	}
	else
#endif
	{
	    status = connect(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	}
#endif
	syscall = "connect(2)";
    }

    if (status < 0) {
	close(fd);
	rb_sys_fail(syscall);
    }
    if (type == INET_SERVER) listen(fd, 5);

    /* create new instance */
    return sock_new(class, fd);
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
#endif

static VALUE
tcp_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    struct sockaddr_in addr;
    struct hostent *h;
    char **pch;
    VALUE ary, names;

    setipaddr(STR2CSTR(host), &addr);
    h = gethostbyaddr((char *)&addr.sin_addr,
		      sizeof(addr.sin_addr),
		      AF_INET);

    if (h == NULL) {
#ifdef HAVE_HSTRERROR
	extern int h_errno;
	rb_raise(rb_eSocket, (char *)hstrerror(h_errno));
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
    rb_ary_push(ary, NUM2INT(h->h_addrtype));
#ifdef h_addr
    for (pch = h->h_addr_list; *pch; pch++) {
	memcpy((char *) &addr.sin_addr, *pch, h->h_length);
	rb_ary_push(ary, mkipaddr(addr.sin_addr.s_addr));
    }
#else
    memcpy((char *)&addr.sin_addr, h->h_addr, h->h_length);
    rb_ary_push(ary, mkipaddr(addr.sin_addr.s_addr));
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
    int *len;
{
    int fd2;

  retry:
#ifdef USE_THREAD
    rb_thread_wait_fd(fd);
#endif
    TRAP_BEG;
    fd2 = accept(fd, sockaddr, len);
    TRAP_END;
    if (fd2 < 0) {
	switch (errno) {
	  case EINTR:
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
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
    struct sockaddr_in from;
    int fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_in);
    return s_accept(rb_cTCPsocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

static VALUE
tcp_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recv(sock, argc, argv, RECV_TCP);
}

#ifdef HAVE_SYS_UN_H
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
    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) rb_sys_fail("socket(2)");

    memset(&sockaddr, 0, sizeof(sockaddr));
    sockaddr.sun_family = AF_UNIX;
    strncpy(sockaddr.sun_path, path->ptr, sizeof(sockaddr.sun_path)-1);
    sockaddr.sun_path[sizeof(sockaddr.sun_path)-1] = '\0';

    if (server) {
        status = bind(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
    }
    else {
        status = connect(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
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
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return ipaddr(&addr);
}

static VALUE
ip_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return ipaddr(&addr);
}

static VALUE
ip_s_getaddress(obj, host)
    VALUE obj, host;
{
    struct sockaddr_in addr;

    if (rb_obj_is_kind_of(host, rb_cInteger)) {
	int i = NUM2INT(host);
	addr.sin_addr.s_addr = htonl(i);
    }
    else {
	setipaddr(STR2CSTR(host), &addr);
    }

    return mkipaddr(addr.sin_addr.s_addr);
}

static VALUE
udp_s_open(class)
    VALUE class;
{
    return sock_new(class, socket(AF_INET, SOCK_DGRAM, 0));
}

static void
udp_addrsetup(host, port, addr)
    VALUE host, port;
    struct sockaddr_in *addr;
{
    memset(addr, 0, sizeof(struct sockaddr_in));
    addr->sin_family = AF_INET;
    if (NIL_P(host)) {
	addr->sin_addr.s_addr = INADDR_ANY;
    }
    else if (rb_obj_is_kind_of(host, rb_cInteger)) {
	int i = NUM2INT(host);
	addr->sin_addr.s_addr = htonl(i);
    }
    else {
	setipaddr(STR2CSTR(host), addr);
    }
    if (FIXNUM_P(port)) {
	addr->sin_port = htons(FIX2INT(port));
    }
    else {
	struct servent *servent;

	servent = getservbyname(STR2CSTR(port), "udp");
	if (servent) {
	    addr->sin_port = servent->s_port;
	}
	else {
	    char *s = STR2CSTR(port);
	    char *end;
	    int portno;

	    portno = strtoul(s, &end, 0);
	    if (*end != '\0') {
		rb_raise(rb_eSocket, "no such servce %s", s);
	    }
	    addr->sin_port = htons(port);
	}
    }
}

static VALUE
udp_connect(sock, host, port)
    VALUE sock, host, port;
{
    struct sockaddr_in addr;
    OpenFile *fptr;

    udp_addrsetup(host, port, &addr);
    GetOpenFile(sock, fptr);
  retry:
    if (connect(fileno(fptr->f), (struct sockaddr*)&addr, sizeof(addr))<0) {
	switch (errno) {
	  case EINTR:
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
	    goto retry;
	}
	rb_sys_fail("connect(2)");
    }

    return INT2FIX(0);
}

static VALUE
udp_bind(sock, host, port)
    VALUE sock, host, port;
{
    struct sockaddr_in addr;
    OpenFile *fptr;

    udp_addrsetup(host, port, &addr);
    GetOpenFile(sock, fptr);
    if (bind(fileno(fptr->f), (struct sockaddr*)&addr, sizeof(addr))<0) {
	rb_sys_fail("bind(2)");
    }
    return INT2FIX(0);
}

static VALUE
udp_send(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    VALUE mesg, flags, host, port;
    struct sockaddr_in addr;
    OpenFile *fptr;
    FILE *f;
    int n;
    char *m;
    int mlen;

    if (argc == 2) {
	return bsock_send(argc, argv, sock);
    }
    rb_scan_args(argc, argv, "4", &mesg, &flags, &host, &port);

    udp_addrsetup(host, port, &addr);
    GetOpenFile(sock, fptr);
    f = GetWriteFile(fptr);
    m = rb_str2cstr(mesg, &mlen);
  retry:
    n = sendto(fileno(f), m, mlen, NUM2INT(flags),
	       (struct sockaddr*)&addr, sizeof(addr));
    if (n < 0) {
	switch (errno) {
	  case EINTR:
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
	    goto retry;
	}
	rb_sys_fail("sendto(2)");
    }
    return INT2FIX(n);
}

static VALUE
udp_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recv(sock, argc, argv, RECV_UDP);
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
	int len = sizeof(addr);
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
    return s_recv(sock, argc, argv, RECV_UNIX);
}

static VALUE
unix_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un from;
    int fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return s_accept(rb_cUNIXsocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

static VALUE
unixaddr(sockaddr)
    struct sockaddr_un *sockaddr;
{
    return rb_assoc_new(rb_str_new2("AF_UNIX"),rb_str_new2(sockaddr->sun_path));
}

static VALUE
unix_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return unixaddr(&addr);
}

static VALUE
unix_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
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

    setup_domain_and_type(domain, &d, type, &t);
    fd = socket(d, t, NUM2INT(protocol));
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
#if !defined(NT) && !defined(__BEOS__)
    int d, t, sp[2];

    setup_domain_and_type(domain, &d, type, &t);
    if (socketpair(d, t, NUM2INT(protocol), sp) < 0)
	rb_sys_fail("socketpair(2)");

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

    Check_Type(addr, T_STRING);
    rb_str_modify(addr);

    GetOpenFile(sock, fptr);
  retry:
    if (connect(fileno(fptr->f), (struct sockaddr*)RSTRING(addr)->ptr, RSTRING(addr)->len) < 0) {
	switch (errno) {
	  case EINTR:
	  case EWOULDBLOCK:
#if EAGAIN != EWOULDBLOCK
	  case EAGAIN:
#endif
#ifdef USE_THREAD
	    rb_thread_schedule();
#endif
	    goto retry;
	}
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
    return s_recv(sock, argc, argv, RECV_SOCKET);
}

static VALUE
sock_accept(sock)
   VALUE sock;
{
    OpenFile *fptr;
    VALUE addr, sock2;
    char buf[1024];
    int len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept(rb_cSocket,fileno(fptr->f),(struct sockaddr*)buf,&len);

    return rb_assoc_new(sock2, rb_str_new(buf, len));
}

#ifdef HAVE_GETHOSTNAME
static VALUE
sock_gethostname(obj)
    VALUE obj;
{
    char buf[1024];

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
	rb_raise(rb_eSocket, (char *)hstrerror(h_errno));
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
    rb_ary_push(ary, NUM2INT(h->h_addrtype));
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
sock_s_gethostbyname(obj, host)
    VALUE obj, host;
{
    struct sockaddr_in addr;
    struct hostent *h;

    if (rb_obj_is_kind_of(host, rb_cInteger)) {
	int i = NUM2INT(host);
	addr.sin_addr.s_addr = htonl(i);
    }
    else {
	setipaddr(STR2CSTR(host), &addr);
    }
    h = gethostbyaddr((char *)&addr.sin_addr,
		      sizeof(addr.sin_addr),
		      AF_INET);

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

static VALUE mConst;

static void
sock_rb_define_const(name, value)
    char *name;
    int value;
{
    rb_define_const(rb_cSocket, name, INT2FIX(value));
    rb_define_const(mConst, name, INT2FIX(value));
}

Init_socket()
{
    rb_eSocket = rb_define_class("SocketError", rb_eStandardError);

    rb_cBasicSocket = rb_define_class("BasicSocket", rb_cIO);
    rb_undef_method(CLASS_OF(rb_cBasicSocket), "new");
    rb_undef_method(CLASS_OF(rb_cBasicSocket), "open");
    rb_define_method(rb_cBasicSocket, "close_read", bsock_close_read, 0);
    rb_define_method(rb_cBasicSocket, "close_write", bsock_close_write, 0);
    rb_define_method(rb_cBasicSocket, "shutdown", bsock_shutdown, -1);
    rb_define_method(rb_cBasicSocket, "setsockopt", bsock_setsockopt, 3);
    rb_define_method(rb_cBasicSocket, "getsockopt", bsock_getsockopt, 2);
    rb_define_method(rb_cBasicSocket, "getsockname", bsock_getsockname, 0);
    rb_define_method(rb_cBasicSocket, "getpeername", bsock_getpeername, 0);
    rb_define_method(rb_cBasicSocket, "send", bsock_send, -1);
    rb_define_method(rb_cBasicSocket, "recv", bsock_recv, -1);

    rb_cIPsocket = rb_define_class("IPsocket", rb_cBasicSocket);
    rb_define_method(rb_cIPsocket, "addr", ip_addr, 0);
    rb_define_method(rb_cIPsocket, "peeraddr", ip_peeraddr, 0);
    rb_define_singleton_method(rb_cIPsocket, "getaddress", ip_s_getaddress, 1);

    rb_cTCPsocket = rb_define_class("TCPsocket", rb_cIPsocket);
    rb_define_singleton_method(rb_cTCPsocket, "open", tcp_s_open, 2);
    rb_define_singleton_method(rb_cTCPsocket, "new", tcp_s_open, 2);
    rb_define_singleton_method(rb_cTCPsocket, "gethostbyname", tcp_s_gethostbyname, 1);
    rb_define_method(rb_cTCPsocket, "recvfrom", tcp_recvfrom, -1);

#ifdef SOCKS
    rb_cSOCKSsocket = rb_define_class("SOCKSsocket", rb_cTCPsocket);
    rb_define_singleton_method(rb_cSOCKSsocket, "open", socks_s_open, 2);
    rb_define_singleton_method(rb_cSOCKSsocket, "new", socks_s_open, 2);
#endif

    rb_cTCPserver = rb_define_class("TCPserver", rb_cTCPsocket);
    rb_define_singleton_method(rb_cTCPserver, "open", tcp_svr_s_open, -1);
    rb_define_singleton_method(rb_cTCPserver, "new", tcp_svr_s_open, -1);
    rb_define_method(rb_cTCPserver, "accept", tcp_accept, 0);

    rb_cUDPsocket = rb_define_class("UDPsocket", rb_cIPsocket);
    rb_define_singleton_method(rb_cUDPsocket, "open", udp_s_open, 0);
    rb_define_singleton_method(rb_cUDPsocket, "new", udp_s_open, 0);
    rb_define_method(rb_cUDPsocket, "connect", udp_connect, 2);
    rb_define_method(rb_cUDPsocket, "bind", udp_bind, 2);
    rb_define_method(rb_cUDPsocket, "send", udp_send, -1);
    rb_define_method(rb_cUDPsocket, "recvfrom", udp_recvfrom, -1);

#ifdef HAVE_SYS_UN_H
    rb_cUNIXsocket = rb_define_class("UNIXsocket", rb_cBasicSocket);
    rb_define_singleton_method(rb_cUNIXsocket, "open", unix_s_sock_open, 1);
    rb_define_singleton_method(rb_cUNIXsocket, "new", unix_s_sock_open, 1);
    rb_define_method(rb_cUNIXsocket, "path", unix_path, 0);
    rb_define_method(rb_cUNIXsocket, "addr", unix_addr, 0);
    rb_define_method(rb_cUNIXsocket, "peeraddr", unix_peeraddr, 0);
    rb_define_method(rb_cUNIXsocket, "recvfrom", unix_recvfrom, -1);

    rb_cUNIXserver = rb_define_class("UNIXserver", rb_cUNIXsocket);
    rb_define_singleton_method(rb_cUNIXserver, "open", unix_svr_s_open, 1);
    rb_define_singleton_method(rb_cUNIXserver, "new", unix_svr_s_open, 1);
    rb_define_method(rb_cUNIXserver, "accept", unix_accept, 0);
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

    /* constants */
    mConst = rb_define_module_under(rb_cSocket, "Constants");
    sock_rb_define_const("SOCK_STREAM", SOCK_STREAM);
    sock_rb_define_const("SOCK_DGRAM", SOCK_DGRAM);
#ifdef SOCK_RAW
    sock_rb_define_const("SOCK_RAW", SOCK_RAW);
#endif
#ifdef SOCK_RDM
    sock_rb_define_const("SOCK_RDM", SOCK_RDM);
#endif
#ifdef SOCK_SEQPACKET
    sock_rb_define_const("SOCK_SEQPACKET", SOCK_SEQPACKET);
#endif
#ifdef SOCK_PACKET
    sock_rb_define_const("SOCK_PACKET", SOCK_PACKET);
#endif

    sock_rb_define_const("AF_INET", AF_INET);
#ifdef PF_INET
    sock_rb_define_const("PF_INET", PF_INET);
#endif
#ifdef AF_UNIX
    sock_rb_define_const("AF_UNIX", AF_UNIX);
    sock_rb_define_const("PF_UNIX", PF_UNIX);
#endif
#ifdef AF_AX25
    sock_rb_define_const("AF_AX25", AF_AX25);
    sock_rb_define_const("PF_AX25", PF_AX25);
#endif
#ifdef AF_IPX
    sock_rb_define_const("AF_IPX", AF_IPX);
    sock_rb_define_const("PF_IPX", PF_IPX);
#endif
#ifdef AF_APPLETALK
    sock_rb_define_const("AF_APPLETALK", AF_APPLETALK);
    sock_rb_define_const("PF_APPLETALK", PF_APPLETALK);
#endif

    sock_rb_define_const("MSG_OOB", MSG_OOB);
#ifdef MSG_PEEK
    sock_rb_define_const("MSG_PEEK", MSG_PEEK);
#endif
#ifdef MSG_DONTROUTE
    sock_rb_define_const("MSG_DONTROUTE", MSG_DONTROUTE);
#endif

    sock_rb_define_const("SOL_SOCKET", SOL_SOCKET);
#ifdef SOL_IP
    sock_rb_define_const("SOL_IP", SOL_IP);
#endif
#ifdef SOL_IPX
    sock_rb_define_const("SOL_IPX", SOL_IPX);
#endif
#ifdef SOL_AX25
    sock_rb_define_const("SOL_AX25", SOL_AX25);
#endif
#ifdef SOL_ATALK
    sock_rb_define_const("SOL_ATALK", SOL_ATALK);
#endif
#ifdef SOL_TCP
    sock_rb_define_const("SOL_TCP", SOL_TCP);
#endif
#ifdef SOL_UDP
    sock_rb_define_const("SOL_UDP", SOL_UDP);
#endif

#ifdef SO_DEBUG
    sock_rb_define_const("SO_DEBUG", SO_DEBUG);
#endif
    sock_rb_define_const("SO_REUSEADDR", SO_REUSEADDR);
#ifdef SO_TYPE
    sock_rb_define_const("SO_TYPE", SO_TYPE);
#endif
#ifdef SO_ERROR
    sock_rb_define_const("SO_ERROR", SO_ERROR);
#endif
#ifdef SO_DONTROUTE
    sock_rb_define_const("SO_DONTROUTE", SO_DONTROUTE);
#endif
#ifdef SO_BROADCAST
    sock_rb_define_const("SO_BROADCAST", SO_BROADCAST);
#endif
#ifdef SO_SNDBUF
    sock_rb_define_const("SO_SNDBUF", SO_SNDBUF);
#endif
#ifdef SO_RCVBUF
    sock_rb_define_const("SO_RCVBUF", SO_RCVBUF);
#endif
#ifdef SO_KEEPALIVE
    sock_rb_define_const("SO_KEEPALIVE", SO_KEEPALIVE);
#endif
#ifdef SO_OOBINLINE
    sock_rb_define_const("SO_OOBINLINE", SO_OOBINLINE);
#endif
#ifdef SO_NO_CHECK
    sock_rb_define_const("SO_NO_CHECK", SO_NO_CHECK);
#endif
#ifdef SO_PRIORITY
    sock_rb_define_const("SO_PRIORITY", SO_PRIORITY);
#endif
#ifdef SO_LINGER
    sock_rb_define_const("SO_LINGER", SO_LINGER);
#endif

#ifdef SOPRI_INTERACTIVE
    sock_rb_define_const("SOPRI_INTERACTIVE", SOPRI_INTERACTIVE);
#endif
#ifdef SOPRI_NORMAL
    sock_rb_define_const("SOPRI_NORMAL", SOPRI_NORMAL);
#endif
#ifdef SOPRI_BACKGROUND
    sock_rb_define_const("SOPRI_BACKGROUND", SOPRI_BACKGROUND);
#endif

#ifdef IP_MULTICAST_IF
    sock_rb_define_const("IP_MULTICAST_IF", IP_MULTICAST_IF);
#endif
#ifdef IP_MULTICAST_TTL
    sock_rb_define_const("IP_MULTICAST_TTL", IP_MULTICAST_TTL);
#endif
#ifdef IP_MULTICAST_LOOP
    sock_rb_define_const("IP_MULTICAST_LOOP", IP_MULTICAST_LOOP);
#endif
#ifdef IP_ADD_MEMBERSHIP
    sock_rb_define_const("IP_ADD_MEMBERSHIP", IP_ADD_MEMBERSHIP);
#endif

#ifdef IP_DEFAULT_MULTICAST_TTL
    sock_rb_define_const("IP_DEFAULT_MULTICAST_TTL", IP_DEFAULT_MULTICAST_TTL);
#endif
#ifdef IP_DEFAULT_MULTICAST_LOOP
    sock_rb_define_const("IP_DEFAULT_MULTICAST_LOOP", IP_DEFAULT_MULTICAST_LOOP);
#endif
#ifdef IP_MAX_MEMBERSHIPS
    sock_rb_define_const("IP_MAX_MEMBERSHIPS", IP_MAX_MEMBERSHIPS);
#endif

#ifdef IPX_TYPE
    sock_rb_define_const("IPX_TYPE", IPX_TYPE);
#endif

#ifdef TCP_NODELAY
    sock_rb_define_const("TCP_NODELAY", TCP_NODELAY);
#endif
#ifdef TCP_MAXSEG
    sock_rb_define_const("TCP_MAXSEG", TCP_MAXSEG);
#endif
}
