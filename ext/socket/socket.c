/************************************************

  socket.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:55 $
  created at: Thu Mar 31 12:21:29 JST 1994

************************************************/

#include "ruby.h"
#include "io.h"
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <errno.h>
#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#else
#undef AF_UNIX
#endif

extern VALUE cIO;
VALUE cBasicSocket;
VALUE cTCPsocket;
VALUE cTCPserver;
#ifdef AF_UNIX
VALUE cUNIXsocket;
VALUE cUNIXserver;
#endif
VALUE cSocket;

FILE *rb_fdopen();
char *strdup();

#ifdef NT
static void
sock_finalize(fptr)
    OpenFile *fptr;
{
    SOCKET s = fileno(fptr->f);
    free(fptr->f);
    free(fptr->f2);
    closesocket(s);
}
#endif

static VALUE
sock_new(class, fd)
    VALUE class;
    int fd;
{
    VALUE sock = obj_alloc(class);
    OpenFile *fp;

    MakeOpenFile(sock, fp);
#ifdef NT
    fp->finalize = sock_finalize;
#endif
    fp->f = rb_fdopen(fd, "r");
    setbuf(fp->f, NULL);
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE|FMODE_SYNC;

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

    rb_scan_args(argc, argv, "01", &howto);
    if (howto == Qnil)
	how = 2;
    else {
	how = NUM2INT(howto);
	if (how < 0 && how > 2) how = 2;
    }
    GetOpenFile(sock, fptr);
    if (shutdown(fileno(fptr->f), how) == -1)
	rb_sys_fail(Qnil);

    return INT2FIX(0);
}

static VALUE
bsock_setopt(sock, lev, optname, val)
    VALUE sock, lev, optname;
    struct RString *val;
{
    int level, option;
    OpenFile *fptr;

    level = NUM2INT(lev);
    option = NUM2INT(optname);
    Check_Type(val, T_STRING);

    GetOpenFile(sock, fptr);
    if (setsockopt(fileno(fptr->f), level, option, val->ptr, val->len) < 0)
	rb_sys_fail(fptr->path);

    return INT2FIX(0);
}

static VALUE
bsock_getopt(sock, lev, optname)
    VALUE sock, lev, optname;
{
    int level, option, len;
    struct RString *val;
    OpenFile *fptr;

    level = NUM2INT(lev);
    option = NUM2INT(optname);
    len = 256;
    val = (struct RString*)str_new(0, len);
    Check_Type(val, T_STRING);

    GetOpenFile(sock, fptr);
    if (getsockopt(fileno(fptr->f), level, option, val->ptr, &len) < 0)
	rb_sys_fail(fptr->path);
    val->len = len;
    return (VALUE)val;
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
    return str_new(buf, len);
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
    return str_new(buf, len);
}

static VALUE
open_inet(class, h, serv, server)
    VALUE class, h, serv;
    int server;
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
    VALUE sock;

    if (h) {
	Check_Type(h, T_STRING);
	host = RSTRING(h)->ptr;
	hostent = gethostbyname(host);
	if (hostent == NULL) {
	    hostaddr = inet_addr(host);
	    if (hostaddr == -1) {
		if (server && !strlen(host))
		    hostaddr = INADDR_ANY;
		else
		    rb_sys_fail(host);
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
    Check_Type(serv, T_STRING);
    servent = getservbyname(RSTRING(serv)->ptr, "tcp");
    if (servent == NULL) {
	servport = strtoul(RSTRING(serv)->ptr, Qnil, 0);
	if (servport == -1) Fail("no such servce %s", RSTRING(serv)->ptr);
      setup_servent:
	_servent.s_port = servport;
	_servent.s_proto = "tcp";
	servent = &_servent;
    }
    protoent = getprotobyname(servent->s_proto);
    if (protoent == NULL) Fail("no such proto %s", servent->s_proto);

    fd = socket(PF_INET, SOCK_STREAM, protoent->p_proto);

    sockaddr.sin_family = AF_INET;
    if (h == Qnil) {
	sockaddr.sin_addr.s_addr = INADDR_ANY;
    }
    else {
	memcpy((char *)&(sockaddr.sin_addr.s_addr),
	       (char *) hostent->h_addr_list[0],
	       (size_t) hostent->h_length);
    }
    sockaddr.sin_port = servent->s_port;

    if (server) {
	status = bind(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	syscall = "bind(2)";
    }
    else {
        status = connect(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	syscall = "connect(2)";
    }

    if (status < 0) {
	close (fd);
	rb_sys_fail(syscall);
    }
    if (server) listen(fd, 5);

    /* create new instance */
    sock = sock_new(class, fd);

    return sock;
}

static VALUE
tcp_s_sock_open(class, host, serv)
    VALUE class, host, serv;
{
    Check_Type(host, T_STRING);
    return open_inet(class, host, serv, 0);
}

static VALUE
tcp_svr_s_open(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2)
	return open_inet(class, arg1, arg2, 1);
    else
	return open_inet(class, Qnil, arg1, 1);
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
    fd2 = accept(fd, sockaddr, len);
    if (fd2 < 0) {
	if (errno == EINTR) goto retry;
	rb_sys_fail(Qnil);
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
    return s_accept(cTCPsocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

#ifdef AF_UNIX
static VALUE
open_unix(class, path, server)
    VALUE class;
    struct RString *path;
    int server;
{
    struct sockaddr_un sockaddr;
    int fd, status;
    char *syscall;
    VALUE sock;
    OpenFile *fptr;

    Check_Type(path, T_STRING);
    fd = socket(PF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) rb_sys_fail("socket(2)");

    sockaddr.sun_family = AF_UNIX;
    strncpy(sockaddr.sun_path, path->ptr, sizeof(sockaddr.sun_path)-1);
    sockaddr.sun_path[sizeof(sockaddr.sun_path)-1] = '\0';

    if (server) {
        status = bind(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	syscall = "bind(2)";
    }
    else {
        status = connect(fd, (struct sockaddr*)&sockaddr, sizeof(sockaddr));
	syscall = "connect(2)";
    }

    if (status < 0) {
	close (fd);
	rb_sys_fail(syscall);
    }

    if (server) listen(fd, 5);

    sock = sock_new(class, fd);
    GetOpenFile(sock, fptr);
    fptr->path = strdup(path->ptr);

    return sock;
}
#endif

static VALUE
tcpaddr(sockaddr)
    struct sockaddr_in *sockaddr;
{
    VALUE family, port, addr;
    VALUE ary;
    struct hostent *hostent;

    family = str_new2("AF_INET");
    hostent = gethostbyaddr((char*)&sockaddr->sin_addr.s_addr,
			    sizeof(sockaddr->sin_addr),
			    AF_INET);
    if (hostent) {
	addr = str_new2(hostent->h_name);
    }
    else {
	char buf[16];
	char *a = (char*)&sockaddr->sin_addr;
	sprintf(buf, "%d.%d.%d.%d", a[0], a[1], a[2], a[3]);
	addr = str_new2(buf);
    }
    port = INT2FIX(sockaddr->sin_port);
    ary = ary_new3(3, family, port, addr);

    return ary;
}

static VALUE
tcp_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return tcpaddr(&addr);
}

static VALUE
tcp_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return tcpaddr(&addr);
}

#ifdef AF_UNIX
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
    if (fptr->path == Qnil) {
	struct sockaddr_un addr;
	int len = sizeof(addr);
	if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	    rb_sys_fail(Qnil);
	fptr->path = strdup(addr.sun_path);
    }
    return str_new2(fptr->path);
}

static VALUE
unix_svr_s_open(class, path)
    VALUE class, path;
{
    return open_unix(class, path, 1);
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
    return s_accept(cUNIXsocket, fileno(fptr->f),
		    (struct sockaddr*)&from, &fromlen);
}

static VALUE
unixaddr(sockaddr)
    struct sockaddr_un *sockaddr;
{
    return assoc_new(str_new2("AF_UNIX"),str_new2(sockaddr->sun_path));
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
	if (strcmp(ptr, "PF_INET") == 0)
	    *dv = PF_INET;
#ifdef PF_UNIX
	else if (strcmp(ptr, "PF_UNIX") == 0)
	    *dv = PF_UNIX;
#endif
#ifdef PF_IMPLINK
	else if (strcmp(ptr, "PF_IMPLINK") == 0)
	    *dv = PF_IMPLINK;
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
	    Fail("Unknown socket domain %s", ptr);
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
	    Fail("Unknown socket type %s", ptr);
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
    if (fd < 0) rb_sys_fail("socke(2)");
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
    int fd;
    int d, t, sp[2];

    setup_domain_and_type(domain, &d, type, &t);
    if (socketpair(d, t, NUM2INT(protocol), sp) < 0)
	rb_sys_fail("socketpair(2)");

    return assoc_new(sock_new(class, sp[0]), sock_new(class, sp[1]));
}

static VALUE
sock_connect(sock, addr)
    VALUE sock;
    struct RString *addr;
{
    OpenFile *fptr;

    Check_Type(addr, T_STRING);
    str_modify(addr);

    GetOpenFile(sock, fptr);
    if (connect(fileno(fptr->f), (struct sockaddr*)addr->ptr, addr->len) < 0)
	rb_sys_fail("connect(2)");

    return INT2FIX(0);
}

static VALUE
sock_bind(sock, addr)
    VALUE sock;
    struct RString *addr;
{
    OpenFile *fptr;

    Check_Type(addr, T_STRING);
    str_modify(addr);

    GetOpenFile(sock, fptr);
    if (bind(fileno(fptr->f), (struct sockaddr*)addr->ptr, addr->len) < 0)
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
sock_accept(sock)
   VALUE sock;
{
    OpenFile *fptr;
    VALUE addr, sock2;
    char buf[1024];
    int len = sizeof buf;

    GetOpenFile(sock, fptr);
    sock2 = s_accept(cSocket,fileno(fptr->f),(struct sockaddr*)buf,&len);

    return assoc_new(sock2, str_new(buf, len));
}

static VALUE
sock_send(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    struct RString *msg, *to;
    VALUE flags;
    OpenFile *fptr;
    FILE *f;
    int fd, n;

    rb_scan_args(argc, argv, "21", &msg, &flags, &to);

    Check_Type(msg, T_STRING);

    GetOpenFile(sock, fptr);
    f = fptr->f2?fptr->f2:fptr->f;
    fd = fileno(f);
    if (to) {
	Check_Type(to, T_STRING);
	n = sendto(fd, msg->ptr, msg->len, NUM2INT(flags),
		   (struct sockaddr*)to->ptr, to->len);
    }
    else {
	n = send(fd, msg->ptr, msg->len, NUM2INT(flags));
    }
    if (n < 0) {
	rb_sys_fail("send(2)");
    }
    return INT2FIX(n);
}

static VALUE
s_recv(sock, argc, argv, from)
    VALUE sock;
    int argc;
    VALUE *argv;
    int from;
{
    OpenFile *fptr;
    FILE f;
    struct RString *str;
    char buf[1024];
    int fd, alen = sizeof buf;
    VALUE len, flg;
    int flags;

    rb_scan_args(argc, argv, "11", &len, &flg);

    if (flg == Qnil) flags = 0;
    else             flags = NUM2INT(flg);

    str = (struct RString*)str_new(0, NUM2INT(len));

    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
    if ((str->len = recvfrom(fd, str->ptr, str->len, flags,
			     (struct sockaddr*)buf, &alen)) < 0) {
	rb_sys_fail("recvfrom(2)");
    }

    if (from)
	return assoc_new(str, str_new(buf, alen));
    else
	return (VALUE)str;
}

static VALUE
sock_recv(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recv(sock, argc, argv, 0);
}

static VALUE
sock_recvfrom(argc, argv, sock)
    int argc;
    VALUE *argv;
    VALUE sock;
{
    return s_recv(sock, argc, argv, 1);
}

Init_socket ()
{
    cBasicSocket = rb_define_class("BasicSocket", cIO);
    rb_undef_method(cBasicSocket, "new");
    rb_define_method(cBasicSocket, "shutdown", bsock_shutdown, -1);
    rb_define_method(cBasicSocket, "setopt", bsock_setopt, 3);
    rb_define_method(cBasicSocket, "getopt", bsock_getopt, 2);
    rb_define_method(cBasicSocket, "getsockname", bsock_getsockname, 0);
    rb_define_method(cBasicSocket, "getpeername", bsock_getpeername, 0);

    cTCPsocket = rb_define_class("TCPsocket", cBasicSocket);
    rb_define_singleton_method(cTCPsocket, "open", tcp_s_sock_open, 2);
    rb_define_singleton_method(cTCPsocket, "new", tcp_s_sock_open, 2);
    rb_define_method(cTCPsocket, "addr", tcp_addr, 0);
    rb_define_method(cTCPsocket, "peeraddr", tcp_peeraddr, 0);

    cTCPserver = rb_define_class("TCPserver", cTCPsocket);
    rb_define_singleton_method(cTCPserver, "open", tcp_svr_s_open, -1);
    rb_define_singleton_method(cTCPserver, "new", tcp_svr_s_open, -1);
    rb_define_method(cTCPserver, "accept", tcp_accept, 0);

#ifdef AF_UNIX
    cUNIXsocket = rb_define_class("UNIXsocket", cBasicSocket);
    rb_define_singleton_method(cUNIXsocket, "open", unix_s_sock_open, 1);
    rb_define_singleton_method(cUNIXsocket, "new", unix_s_sock_open, 1);
    rb_define_method(cUNIXsocket, "path", unix_path, 0);
    rb_define_method(cUNIXsocket, "addr", unix_addr, 0);
    rb_define_method(cUNIXsocket, "peeraddr", unix_peeraddr, 0);

    cUNIXserver = rb_define_class("UNIXserver", cUNIXsocket);
    rb_define_singleton_method(cUNIXserver, "open", unix_svr_s_open, 1);
    rb_define_singleton_method(cUNIXserver, "new", unix_svr_s_open, 1);
    rb_define_method(cUNIXserver, "accept", unix_accept, 0);
#endif

    cSocket = rb_define_class("Socket", cBasicSocket);
    rb_define_singleton_method(cSocket, "open", sock_s_open, 3);
    rb_define_singleton_method(cSocket, "new", sock_s_open, 3);
    rb_define_singleton_method(cSocket, "for_fd", sock_s_for_fd, 1);

    rb_define_method(cSocket, "connect", sock_connect, 1);
    rb_define_method(cSocket, "bind", sock_bind, 1);
    rb_define_method(cSocket, "listen", sock_listen, 1);
    rb_define_method(cSocket, "accept", sock_accept, 0);

    rb_define_method(cSocket, "send", sock_send, -1);
    rb_define_method(cSocket, "recv", sock_recv, -1);
    rb_define_method(cSocket, "recvfrom", sock_recv, -1);

    rb_define_singleton_method(cSocket, "socketpair", sock_s_socketpair, 3);
}
