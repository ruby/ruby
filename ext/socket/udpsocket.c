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
udp_connect_internal(struct udp_arg *arg)
{
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
    arg.res = rsock_addrinfo(host, port, sock, SOCK_DGRAM, 0);
    ret = rb_ensure(udp_connect_internal, (VALUE)&arg,
		    rsock_freeaddrinfo, (VALUE)arg.res);
    if (!ret) rsock_sys_fail_host_port("connect(2)", host, port);
    return INT2FIX(0);
}

static VALUE
udp_bind_internal(struct udp_arg *arg)
{
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
    arg.res = rsock_addrinfo(host, port, sock, SOCK_DGRAM, 0);
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
udp_send_internal(struct udp_send_arg *arg)
{
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
    arg.res = rsock_addrinfo(host, port, sock, SOCK_DGRAM, 0);
    ret = rb_ensure(udp_send_internal, (VALUE)&arg,
		    rsock_freeaddrinfo, (VALUE)arg.res);
    if (!ret) rsock_sys_fail_host_port("sendto(2)", host, port);
    return ret;
}

/*
 * call-seq:
 *   udpsocket.recvfrom_nonblock(maxlen [, flags [, options]]) => [mesg, sender_inet_addr]
 *
 * Receives up to _maxlen_ bytes from +udpsocket+ using recvfrom(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * If _maxlen_ is omitted, its default value is 65536.
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
 * * +options+ - keyword hash, supporting `exception: false`
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
 * 	begin # emulate blocking recvfrom
 * 	  p s2.recvfrom_nonblock(10)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]
 * 	rescue IO::WaitReadable
 * 	  IO.select([s2])
 * 	  retry
 * 	end
 *
 * Refer to Socket#recvfrom for the exceptions that may be thrown if the call
 * to _recvfrom_nonblock_ fails.
 *
 * UDPSocket#recvfrom_nonblock may raise any error corresponding to recvfrom(2) failure,
 * including Errno::EWOULDBLOCK.
 *
 * If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
 * it is extended by IO::WaitReadable.
 * So IO::WaitReadable can be used to rescue the exceptions for retrying recvfrom_nonblock.
 *
 * By specifying `exception: false`, the options hash allows you to indicate
 * that recvmsg_nonblock should not raise an IO::WaitWritable exception, but
 * return the symbol :wait_writable instead.
 *
 * === See
 * * Socket#recvfrom
 */
static VALUE
udp_recvfrom_nonblock(int argc, VALUE *argv, VALUE sock)
{
    return rsock_s_recvfrom_nonblock(sock, argc, argv, RECV_IP);
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
    rb_define_method(rb_cUDPSocket, "recvfrom_nonblock", udp_recvfrom_nonblock, -1);
}
