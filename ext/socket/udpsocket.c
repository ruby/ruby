/************************************************

  udpsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

/*
 * call-seq:
 *   UDPSocket.new([address_family]) => socket
 *
 * Creates a new UDPSocket object.
 *
 * _address_family_ should be an integer, a string or a symbol:
 * Socket::AF_INET, "AF_INET", :INET, etc.
 *
 *   require 'socket'
 *
 *   UDPSocket.new                   #=> #<UDPSocket:fd 3>
 *   UDPSocket.new(Socket::AF_INET6) #=> #<UDPSocket:fd 4>
 *
 */
static VALUE
udp_init(int argc, VALUE *argv, VALUE sock)
{
    VALUE arg;
    int family = AF_INET;
    int fd;

    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
	family = rsock_family_arg(arg);
    }
    fd = rsock_socket(family, SOCK_DGRAM, 0);
    if (fd < 0) {
	rb_sys_fail("socket(2) - udp");
    }

    return rsock_init_sock(sock, fd);
}

struct udp_arg
{
    struct rb_addrinfo *res;
    rb_io_t *fptr;
};

static VALUE
udp_connect_internal(VALUE v)
{
    struct udp_arg *arg = (void *)v;
    rb_io_t *fptr;
    int fd;
    struct addrinfo *res;

    rb_io_check_closed(fptr = arg->fptr);
    fd = fptr->fd;
    for (res = arg->res->ai; res; res = res->ai_next) {
	if (rsock_connect(fd, res->ai_addr, res->ai_addrlen, 0) >= 0) {
	    return Qtrue;
	}
    }
    return Qfalse;
}

/*
 * call-seq:
 *   udpsocket.connect(host, port) => 0
 *
 * Connects _udpsocket_ to _host_:_port_.
 *
 * This makes possible to send without destination address.
 *
 *   u1 = UDPSocket.new
 *   u1.bind("127.0.0.1", 4913)
 *   u2 = UDPSocket.new
 *   u2.connect("127.0.0.1", 4913)
 *   u2.send "uuuu", 0
 *   p u1.recvfrom(10) #=> ["uuuu", ["AF_INET", 33230, "localhost", "127.0.0.1"]]
 *
 */
static VALUE
udp_connect(VALUE sock, VALUE host, VALUE port)
{
    struct udp_arg arg;
    VALUE ret;

    GetOpenFile(sock, arg.fptr);
    arg.res = rsock_addrinfo(host, port, rsock_fd_family(arg.fptr->fd), SOCK_DGRAM, 0);
    ret = rb_ensure(udp_connect_internal, (VALUE)&arg,
		    rsock_freeaddrinfo, (VALUE)arg.res);
    if (!ret) rsock_sys_fail_host_port("connect(2)", host, port);
    return INT2FIX(0);
}

static VALUE
udp_bind_internal(VALUE v)
{
    struct udp_arg *arg = (void *)v;
    rb_io_t *fptr;
    int fd;
    struct addrinfo *res;

    rb_io_check_closed(fptr = arg->fptr);
    fd = fptr->fd;
    for (res = arg->res->ai; res; res = res->ai_next) {
	if (bind(fd, res->ai_addr, res->ai_addrlen) < 0) {
	    continue;
	}
	return Qtrue;
    }
    return Qfalse;
}

/*
 * call-seq:
 *   udpsocket.bind(host, port) #=> 0
 *
 * Binds _udpsocket_ to _host_:_port_.
 *
 *   u1 = UDPSocket.new
 *   u1.bind("127.0.0.1", 4913)
 *   u1.send "message-to-self", 0, "127.0.0.1", 4913
 *   p u1.recvfrom(10) #=> ["message-to", ["AF_INET", 4913, "localhost", "127.0.0.1"]]
 *
 */
static VALUE
udp_bind(VALUE sock, VALUE host, VALUE port)
{
    struct udp_arg arg;
    VALUE ret;

    GetOpenFile(sock, arg.fptr);
    arg.res = rsock_addrinfo(host, port, rsock_fd_family(arg.fptr->fd), SOCK_DGRAM, 0);
    ret = rb_ensure(udp_bind_internal, (VALUE)&arg,
		    rsock_freeaddrinfo, (VALUE)arg.res);
    if (!ret) rsock_sys_fail_host_port("bind(2)", host, port);
    return INT2FIX(0);
}

struct udp_send_arg {
    struct rb_addrinfo *res;
    rb_io_t *fptr;
    struct rsock_send_arg sarg;
};

static VALUE
udp_send_internal(VALUE v)
{
    struct udp_send_arg *arg = (void *)v;
    rb_io_t *fptr;
    int n;
    struct addrinfo *res;

    rb_io_check_closed(fptr = arg->fptr);
    for (res = arg->res->ai; res; res = res->ai_next) {
      retry:
	arg->sarg.fd = fptr->fd;
	arg->sarg.to = res->ai_addr;
	arg->sarg.tolen = res->ai_addrlen;
	rsock_maybe_fd_writable(arg->sarg.fd);
	n = (int)BLOCKING_REGION_FD(rsock_sendto_blocking, &arg->sarg);
	if (n >= 0) {
	    return INT2FIX(n);
	}
	if (rb_io_wait_writable(fptr->fd)) {
	    goto retry;
	}
    }
    return Qfalse;
}

/*
 * call-seq:
 *   udpsocket.send(mesg, flags, host, port)  => numbytes_sent
 *   udpsocket.send(mesg, flags, sockaddr_to) => numbytes_sent
 *   udpsocket.send(mesg, flags)              => numbytes_sent
 *
 * Sends _mesg_ via _udpsocket_.
 *
 * _flags_ should be a bitwise OR of Socket::MSG_* constants.
 *
 *   u1 = UDPSocket.new
 *   u1.bind("127.0.0.1", 4913)
 *
 *   u2 = UDPSocket.new
 *   u2.send "hi", 0, "127.0.0.1", 4913
 *
 *   mesg, addr = u1.recvfrom(10)
 *   u1.send mesg, 0, addr[3], addr[1]
 *
 *   p u2.recv(100) #=> "hi"
 *
 */
static VALUE
udp_send(int argc, VALUE *argv, VALUE sock)
{
    VALUE flags, host, port;
    struct udp_send_arg arg;
    VALUE ret;

    if (argc == 2 || argc == 3) {
	return rsock_bsock_send(argc, argv, sock);
    }
    rb_scan_args(argc, argv, "4", &arg.sarg.mesg, &flags, &host, &port);

    StringValue(arg.sarg.mesg);
    GetOpenFile(sock, arg.fptr);
    arg.sarg.fd = arg.fptr->fd;
    arg.sarg.flags = NUM2INT(flags);
    arg.res = rsock_addrinfo(host, port, rsock_fd_family(arg.fptr->fd), SOCK_DGRAM, 0);
    ret = rb_ensure(udp_send_internal, (VALUE)&arg,
		    rsock_freeaddrinfo, (VALUE)arg.res);
    if (!ret) rsock_sys_fail_host_port("sendto(2)", host, port);
    return ret;
}

/* :nodoc: */
static VALUE
udp_recvfrom_nonblock(VALUE sock, VALUE len, VALUE flg, VALUE str, VALUE ex)
{
    return rsock_s_recvfrom_nonblock(sock, len, flg, str, ex, RECV_IP);
}

void
rsock_init_udpsocket(void)
{
    /*
     * Document-class: UDPSocket < IPSocket
     *
     * UDPSocket represents a UDP/IP socket.
     *
     */
    rb_cUDPSocket = rb_define_class("UDPSocket", rb_cIPSocket);
    rb_define_method(rb_cUDPSocket, "initialize", udp_init, -1);
    rb_define_method(rb_cUDPSocket, "connect", udp_connect, 2);
    rb_define_method(rb_cUDPSocket, "bind", udp_bind, 2);
    rb_define_method(rb_cUDPSocket, "send", udp_send, -1);

    /* for ext/socket/lib/socket.rb use only: */
    rb_define_private_method(rb_cUDPSocket,
			     "__recvfrom_nonblock", udp_recvfrom_nonblock, 4);
}
