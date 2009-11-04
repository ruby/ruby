/************************************************

  ipsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

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
inetsock_cleanup(struct inetsock_arg *arg)
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
init_inetsock_internal(struct inetsock_arg *arg)
{
    int type = arg->type;
    struct addrinfo *res;
    int fd, status = 0;
    const char *syscall = 0;

    arg->remote.res = rsock_addrinfo(arg->remote.host, arg->remote.serv, SOCK_STREAM,
				    (type == INET_SERVER) ? AI_PASSIVE : 0);
    /*
     * Maybe also accept a local address
     */

    if (type != INET_SERVER && (!NIL_P(arg->local.host) || !NIL_P(arg->local.serv))) {
	arg->local.res = rsock_addrinfo(arg->local.host, arg->local.serv, SOCK_STREAM, 0);
    }

    arg->fd = fd = -1;
    for (res = arg->remote.res; res; res = res->ai_next) {
#if !defined(INET6) && defined(AF_INET6)
	if (res->ai_family == AF_INET6)
	    continue;
#endif
	status = rsock_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
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
		status = rsock_connect(fd, res->ai_addr, res->ai_addrlen,
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
    return rsock_init_sock(arg->sock, fd);
}

VALUE
rsock_init_inetsock(VALUE sock, VALUE remote_host, VALUE remote_serv,
	            VALUE local_host, VALUE local_serv, int type)
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
 *   ipsocket.addr => [address_family, port, hostname, numeric_address] 
 *
 * Returns the local address as an array which contains
 * address_family, port, hostname and numeric_address. 
 *
 * hostname is obtained from numeric_address using reverse lookup.
 * If ipsocket.do_not_reverse_lookup is true,
 * hostname is same as numeric_address.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.addr #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *   }
 *
 */
static VALUE
ip_addr(VALUE sock)
{
    rb_io_t *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getsockname(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return rsock_ipaddr((struct sockaddr*)&addr, fptr->mode & FMODE_NOREVLOOKUP);
}

/*
 * call-seq:
 *   ipsocket.peeraddr => [address_family, port, hostname, numeric_address] 
 *
 * Returns the remote address as an array which contains
 * address_family, port, hostname and numeric_address. 
 * It is defined for connection oriented socket such as TCPSocket.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.peeraddr #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *   }
 *
 */
static VALUE
ip_peeraddr(VALUE sock)
{
    rb_io_t *fptr;
    struct sockaddr_storage addr;
    socklen_t len = sizeof addr;

    GetOpenFile(sock, fptr);

    if (getpeername(fptr->fd, (struct sockaddr*)&addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return rsock_ipaddr((struct sockaddr*)&addr, fptr->mode & FMODE_NOREVLOOKUP);
}

/*
 * call-seq:
 *   ipsocket.recvfrom(maxlen)        => [mesg, ipaddr]
 *   ipsocket.recvfrom(maxlen, flags) => [mesg, ipaddr]
 *
 * Receives a message and return the message as a string and
 * an address which the message come from.
 *
 * _maxlen_ is the maximum number of bytes to receive.
 *
 * _flags_ should be a bitwise OR of Socket::MSG_* constants.
 *
 * ipaddr is same as IPSocket#{peeraddr,addr}.
 *
 *   u1 = UDPSocket.new
 *   u1.bind("127.0.0.1", 4913)
 *   u2 = UDPSocket.new
 *   u2.send "uuuu", 0, "127.0.0.1", 4913
 *   p u1.recvfrom(10) #=> ["uuuu", ["AF_INET", 33230, "localhost", "127.0.0.1"]]
 *   
 */
static VALUE
ip_recvfrom(int argc, VALUE *argv, VALUE sock)
{
    return rsock_s_recvfrom(sock, argc, argv, RECV_IP);
}

/*
 * call-seq:
 *   IPSocket.getaddress(host)        => ipaddress
 *
 * Lookups IP address of _host_.
 *
 *   IPSocket.getaddress("localhost")     #=> "127.0.0.1"
 *   IPSocket.getaddress("ip6-localhost") #=> "::1"
 *
 */
static VALUE
ip_s_getaddress(VALUE obj, VALUE host)
{
    struct sockaddr_storage addr;
    struct addrinfo *res = rsock_addrinfo(host, Qnil, SOCK_STREAM, 0);

    /* just take the first one */
    memcpy(&addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    return rsock_make_ipaddr((struct sockaddr*)&addr);
}

/*
 * IPSocket class
 */
void
Init_ipsocket(void)
{
    rb_cIPSocket = rb_define_class("IPSocket", rb_cBasicSocket);
    rb_define_method(rb_cIPSocket, "addr", ip_addr, 0);
    rb_define_method(rb_cIPSocket, "peeraddr", ip_peeraddr, 0);
    rb_define_method(rb_cIPSocket, "recvfrom", ip_recvfrom, -1);
    rb_define_singleton_method(rb_cIPSocket, "getaddress", ip_s_getaddress, 1);
    rb_undef_method(rb_cIPSocket, "getpeereid");

}
