/************************************************

  tcpserver.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

/*
 * call-seq:
 *   TCPServer.new([hostname,] port) => tcpserver
 *
 * Creates a new server socket bound to _port_.
 *
 * If _hostname_ is given, the socket is bound to it.
 *
 *   serv = TCPServer.new("127.0.0.1", 28561)
 *   s = serv.accept
 *   s.puts Time.now
 *   s.close
 *
 * Internally, TCPServer.new calls getaddrinfo() function to
 * obtain addresses.
 * If getaddrinfo() returns multiple addresses,
 * TCPServer.new tries to create a server socket for each address
 * and returns first one that is successful.
 *
 */
static VALUE
tcp_svr_init(int argc, VALUE *argv, VALUE sock)
{
    VALUE hostname, port;

    rb_scan_args(argc, argv, "011", &hostname, &port);
    return rsock_init_inetsock(sock, hostname, port, Qnil, Qnil, INET_SERVER);
}

/*
 * call-seq:
 *   tcpserver.accept => tcpsocket
 *
 * Accepts an incoming connection. It returns a new TCPSocket object.
 *
 *   TCPServer.open("127.0.0.1", 14641) {|serv|
 *     s = serv.accept
 *     s.puts Time.now
 *     s.close
 *   }
 *
 */
static VALUE
tcp_accept(VALUE sock)
{
    rb_io_t *fptr;
    union_sockaddr from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = (socklen_t)sizeof(from);
    return rsock_s_accept(rb_cTCPSocket, fptr->fd, &from.addr, &fromlen);
}

/*
 * call-seq:
 *   tcpserver.accept_nonblock([options]) => tcpsocket
 *
 * Accepts an incoming connection using accept(2) after
 * O_NONBLOCK is set for the underlying file descriptor.
 * It returns an accepted TCPSocket for the incoming connection.
 *
 * === Example
 * 	require 'socket'
 * 	serv = TCPServer.new(2202)
 * 	begin # emulate blocking accept
 * 	  sock = serv.accept_nonblock
 * 	rescue IO::WaitReadable, Errno::EINTR
 * 	  IO.select([serv])
 * 	  retry
 * 	end
 * 	# sock is an accepted socket.
 *
 * Refer to Socket#accept for the exceptions that may be thrown if the call
 * to TCPServer#accept_nonblock fails.
 *
 * TCPServer#accept_nonblock may raise any error corresponding to accept(2) failure,
 * including Errno::EWOULDBLOCK.
 *
 * If the exception is Errno::EWOULDBLOCK, Errno::AGAIN, Errno::ECONNABORTED, Errno::EPROTO,
 * it is extended by IO::WaitReadable.
 * So IO::WaitReadable can be used to rescue the exceptions for retrying accept_nonblock.
 *
 * By specifying `exception: false`, the options hash allows you to indicate
 * that accept_nonblock should not raise an IO::WaitReadable exception, but
 * return the symbol :wait_readable instead.
 *
 * === See
 * * TCPServer#accept
 * * Socket#accept
 */
static VALUE
tcp_accept_nonblock(int argc, VALUE *argv, VALUE sock)
{
    rb_io_t *fptr;
    union_sockaddr from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = (socklen_t)sizeof(from);
    return rsock_s_accept_nonblock(argc, argv, rb_cTCPSocket, fptr, &from.addr, &fromlen);
}

/*
 * call-seq:
 *   tcpserver.sysaccept => file_descriptor
 *
 * Returns a file descriptor of a accepted connection.
 *
 *   TCPServer.open("127.0.0.1", 28561) {|serv|
 *     fd = serv.sysaccept
 *     s = IO.for_fd(fd)
 *     s.puts Time.now
 *     s.close
 *   }
 *
 */
static VALUE
tcp_sysaccept(VALUE sock)
{
    rb_io_t *fptr;
    union_sockaddr from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = (socklen_t)sizeof(from);
    return rsock_s_accept(0, fptr->fd, &from.addr, &fromlen);
}

void
rsock_init_tcpserver(void)
{
    /*
     * Document-class: TCPServer < TCPSocket
     *
     * TCPServer represents a TCP/IP server socket.
     *
     * A simple TCP server may look like:
     *
     *   require 'socket'
     *
     *   server = TCPServer.new 2000 # Server bind to port 2000
     *   loop do
     *     client = server.accept    # Wait for a client to connect
     *     client.puts "Hello !"
     *     client.puts "Time is #{Time.now}"
     *     client.close
     *   end
     *
     * A more usable server (serving multiple clients):
     *
     *   require 'socket'
     *
     *   server = TCPServer.new 2000
     *   loop do
     *     Thread.start(server.accept) do |client|
     *       client.puts "Hello !"
     *       client.puts "Time is #{Time.now}"
     *       client.close
     *     end
     *   end
     *
     */
    rb_cTCPServer = rb_define_class("TCPServer", rb_cTCPSocket);
    rb_define_method(rb_cTCPServer, "accept", tcp_accept, 0);
    rb_define_method(rb_cTCPServer, "accept_nonblock", tcp_accept_nonblock, -1);
    rb_define_method(rb_cTCPServer, "sysaccept", tcp_sysaccept, 0);
    rb_define_method(rb_cTCPServer, "initialize", tcp_svr_init, -1);
    rb_define_method(rb_cTCPServer, "listen", rsock_sock_listen, 1); /* in socket.c */
}
