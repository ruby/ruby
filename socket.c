/************************************************

  socket.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:51 $
  created at: Thu Mar 31 12:21:29 JST 1994

************************************************/

#include "ruby.h"
#ifdef HAVE_SOCKET
#include "io.h"
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <errno.h>
#include <sys/un.h>

extern VALUE C_IO;
VALUE C_BasicSocket;
VALUE C_TCPsocket;
VALUE C_TCPserver;
VALUE C_UNIXsocket;
VALUE C_UNIXserver;
VALUE C_Socket;

FILE *rb_fdopen();
char *strdup();

static VALUE
sock_new(class, fd)
    VALUE class;
    int fd;
{
    VALUE sock = obj_alloc(class);
    OpenFile *fp;

    GC_LINK;
    GC_PRO(sock);
    MakeOpenFile(sock, fp);
    fp->f = rb_fdopen(fd, "r");
    setbuf(fp->f, NULL);
    fp->f2 = rb_fdopen(fd, "w");
    fp->mode = FMODE_READWRITE|FMODE_SYNC;
    GC_UNLINK;

    return sock;
}

static VALUE
Fbsock_shutdown(sock, args)
    VALUE sock, args;
{
    VALUE howto;
    int how;
    OpenFile *fptr;

    rb_scan_args(args, "01", &howto);
    if (howto == Qnil)
	how = 2;
    else {
	how = NUM2INT(howto);
	if (how < 0 && how > 2) how = 2;
    }
    GetOpenFile(sock, fptr);
    if (shutdown(fileno(fptr->f), how) == -1)
	rb_sys_fail(Qnil);
    return sock;
}

static VALUE
Fbsock_setopt(sock, lev, optname, val)
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
    return sock;
}

static VALUE
Fbsock_getopt(sock, lev, optname)
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
Fbsock_getsockname(sock)
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
Fbsock_getpeername(sock)
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
	servport = strtol(RSTRING(serv)->ptr, Qnil, 0);
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
Ftcp_sock_open(class, host, serv)
    VALUE class, host, serv;
{
    Check_Type(host, T_STRING);
    return open_inet(class, host, serv, 0);
}

static VALUE
Ftcp_svr_open(class, args)
    VALUE class, args;
{
    VALUE arg1, arg2;

    if (rb_scan_args(args, "11", &arg1, &arg2) == 2)
	return open_inet(class, arg1, arg2, 1);
    else
	return open_inet(class, Qnil, arg1, 1);
}

static VALUE
sock_accept(class, fd, sockaddr, len)
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
Ftcp_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in from;
    int fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_in);
    return sock_accept(C_TCPsocket, fileno(fptr->f),
		       (struct sockaddr*)&from, &fromlen);
}

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

    GC_LINK;
    GC_PRO3(sock, sock_new(class, fd));
    GetOpenFile(sock, fptr);
    fptr->path = strdup(path->ptr);
    GC_UNLINK;

    return sock;
}

static VALUE
tcp_addr(sockaddr)
    struct sockaddr_in *sockaddr;
{
    VALUE family, port, addr;
    VALUE ary;
    struct hostent *hostent;

    GC_LINK;
    GC_PRO3(family, str_new2("AF_INET"));
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
    GC_PRO(addr);
    port = INT2FIX(sockaddr->sin_port);
    ary = ary_new3(3, family, port, addr);
    GC_UNLINK;
    return ary;
}

static VALUE
Ftcp_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);
    
    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return tcp_addr(&addr);
}

static VALUE
Ftcp_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_in addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);
    
    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return tcp_addr(&addr);
}

static VALUE
Funix_sock_open(sock, path)
    VALUE sock, path;
{
    return open_unix(sock, path, 0);
}

static VALUE
Funix_path(sock)
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
Funix_svr_open(class, path)
    VALUE class, path;
{
    return open_unix(class, path, 1);
}

static VALUE
Funix_accept(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un from;
    int fromlen;

    GetOpenFile(sock, fptr);
    fromlen = sizeof(struct sockaddr_un);
    return sock_accept(C_UNIXsocket, fileno(fptr->f),
		       (struct sockaddr*)&from, &fromlen);
}

static VALUE
unix_addr(sockaddr)
    struct sockaddr_un *sockaddr;
{
    VALUE family, path;
    VALUE ary;

    GC_LINK;
    GC_PRO3(family, str_new2("AF_UNIX"));
    GC_PRO3(path, str_new2(sockaddr->sun_path));
    ary = assoc_new(family, path);
    GC_UNLINK;
    return ary;
}

static VALUE
Funix_addr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);
    
    if (getsockname(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return unix_addr(&addr);
}

static VALUE
Funix_peeraddr(sock)
    VALUE sock;
{
    OpenFile *fptr;
    struct sockaddr_un addr;
    int len = sizeof addr;

    GetOpenFile(sock, fptr);
    
    if (getpeername(fileno(fptr->f), (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return unix_addr(&addr);
}

static void
setup_domain_and_type(domain, dv, type, tv)
    VALUE domain, type;
    int *dv, *tv;
{
    char *ptr;

    if (TYPE(domain) == T_STRING) {
	ptr = RSTRING(domain)->ptr;
	if (strcmp(ptr, "PF_UNIX") == 0)
	    *dv = PF_UNIX;
	else if (strcmp(ptr, "PF_INET") == 0)
	    *dv = PF_INET;
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
Fsock_open(class, domain, type, protocol)
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
Fsock_socketpair(class, domain, type, protocol)
    VALUE class, domain, type, protocol;
{
    int fd;
    int d, t, sp[2];
    VALUE sock1, sock2, pair;

    setup_domain_and_type(domain, &d, type, &t);
    if (socketpair(d, t, NUM2INT(protocol), sp) < 0)
	rb_sys_fail("socketpair(2)");

    GC_LINK;
    GC_PRO3(sock1, sock_new(class, sp[0]));
    GC_PRO3(sock2, sock_new(class, sp[1]));
    pair = assoc_new(sock1, sock2);
    GC_UNLINK;

    return pair;
}

static VALUE
Fsock_connect(sock, addr)
    VALUE sock;
    struct RString *addr;
{
    OpenFile *fptr;

    Check_Type(addr, T_STRING);
    str_modify(addr);

    GetOpenFile(sock, fptr);
    if (connect(fileno(fptr->f), (struct sockaddr*)addr->ptr, addr->len) < 0)
	rb_sys_fail("connect(2)");
    return sock;
}

static VALUE
Fsock_bind(sock, addr)
    VALUE sock;
    struct RString *addr;
{
    OpenFile *fptr;

    Check_Type(addr, T_STRING);
    str_modify(addr);

    GetOpenFile(sock, fptr);
    if (bind(fileno(fptr->f), (struct sockaddr*)addr->ptr, addr->len) < 0)
	rb_sys_fail("bind(2)");
    return sock;
}

static VALUE
Fsock_listen(sock, log)
   VALUE sock, log;
{
    OpenFile *fptr;

    GetOpenFile(sock, fptr);
    if (listen(fileno(fptr->f), NUM2INT(log)) < 0)
	rb_sys_fail("listen(2)");
    return sock;
}

static VALUE
Fsock_accept(sock)
   VALUE sock;
{
    OpenFile *fptr;
    VALUE addr, sock2;
    int fd;
    char buf[1024];
    int len = sizeof buf;

    GetOpenFile(sock, fptr);
    if ((fd = accept(fileno(fptr->f), (struct sockaddr*)buf, &len)) < 0)
	rb_sys_fail("listen(2)");

    return sock_new(C_Socket, fd);
}

static VALUE
Fsock_send(sock, args)
    VALUE sock, args;
{
    struct RString *msg, *to;
    VALUE flags;
    OpenFile *fptr;
    FILE *f;
    int fd, n;

    rb_scan_args(args, "21", &msg, &flags, &to);

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
Fsock_recv(sock, len, flags)
    VALUE sock, len, flags;
{
    OpenFile *fptr;
    FILE f;
    struct RString *str;
    char buf[1024];
    int fd, alen = sizeof buf;
    VALUE addr, result;

    GC_LINK;
    GC_PRO3(str, (struct RString*)str_new(0, NUM2INT(len)));

    GetOpenFile(sock, fptr);
    fd = fileno(fptr->f);
    if (recvfrom(fd, str->ptr, str->len, NUM2INT(flags), 
		 (struct sockaddr*)buf, &alen) < 0) {
	rb_sys_fail("recv(2)");
    }
    GC_PRO3(addr, str_new(buf, alen));
    result = assoc_new(str, addr);
    GC_UNLINK;

    return result;
}

Init_Socket ()
{
    C_BasicSocket = rb_define_class("BasicSocket", C_IO);
    rb_undef_method(C_BasicSocket, "new");
    rb_define_method(C_BasicSocket, "shutdown", Fbsock_shutdown, -2);
    rb_define_method(C_BasicSocket, "setopt", Fbsock_setopt, 3);
    rb_define_method(C_BasicSocket, "getopt", Fbsock_getopt, 2);
    rb_define_method(C_BasicSocket, "getsockname", Fbsock_getsockname, 0);
    rb_define_method(C_BasicSocket, "getpeername", Fbsock_getpeername, 0);

    C_TCPsocket = rb_define_class("TCPsocket", C_BasicSocket);
    rb_define_single_method(C_TCPsocket, "open", Ftcp_sock_open, 2);
    rb_define_alias(C_TCPsocket, "new", "open");
    rb_define_method(C_TCPsocket, "addr", Ftcp_addr, 0);
    rb_define_method(C_TCPsocket, "peeraddr", Ftcp_peeraddr, 0);

    C_TCPserver = rb_define_class("TCPserver", C_TCPsocket);
    rb_define_single_method(C_TCPserver, "open", Ftcp_svr_open, -2);
    rb_define_alias(C_TCPserver, "new", "open");
    rb_define_method(C_TCPserver, "accept", Ftcp_accept, 0);

    C_UNIXsocket = rb_define_class("UNIXsocket", C_BasicSocket);
    rb_define_single_method(C_UNIXsocket, "open", Funix_sock_open, 1);
    rb_define_alias(C_UNIXsocket, "new", "open");
    rb_define_method(C_UNIXsocket, "path", Funix_path, 0);
    rb_define_method(C_UNIXsocket, "addr", Funix_addr, 0);
    rb_define_method(C_UNIXsocket, "peeraddr", Funix_peeraddr, 0);

    C_UNIXserver = rb_define_class("UNIXserver", C_UNIXsocket);
    rb_define_single_method(C_UNIXserver, "open", Funix_svr_open, 1);
    rb_define_alias(C_UNIXserver, "new", "open");
    rb_define_single_method(C_UNIXserver, "new", Funix_svr_open, 1);
    rb_define_method(C_UNIXserver, "accept", Funix_accept, 0);

    C_Socket = rb_define_class("Socket", C_BasicSocket);
    rb_define_single_method(C_Socket, "open", Fsock_open, 3);
    rb_define_alias(C_UNIXserver, "new", "open");

    rb_define_method(C_Socket, "connect", Fsock_connect, 1);
    rb_define_method(C_Socket, "bind", Fsock_bind, 1);
    rb_define_method(C_Socket, "listen", Fsock_listen, 1);
    rb_define_method(C_Socket, "accept", Fsock_accept, 0);

    rb_define_method(C_Socket, "send", Fsock_send, -2);
    rb_define_method(C_Socket, "recv", Fsock_recv, 2);

    rb_define_single_method(C_Socket, "socketpair", Fsock_socketpair, 3);
}
#endif /* HAVE_SOCKET */
