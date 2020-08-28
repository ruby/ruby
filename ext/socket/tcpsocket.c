/************************************************

  tcpsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

/*
 * call-seq:
 *    TCPSocket.new(remote_host, remote_port, local_host=nil, local_port=nil)
 *
 * Opens a TCP connection to +remote_host+ on +remote_port+.  If +local_host+
 * and +local_port+ are specified, then those parameters are used on the local
 * end to establish the connection.
 */
static VALUE
tcp_init(int argc, VALUE *argv, VALUE sock)
{
    VALUE remote_host, remote_serv;
    VALUE local_host, local_serv;
    VALUE opt;
    static ID keyword_ids[1];
    VALUE kwargs[1];
    VALUE resolv_timeout = Qnil;

    if (!keyword_ids[0]) {
	CONST_ID(keyword_ids[0], "resolv_timeout");
    }

    rb_scan_args(argc, argv, "22:", &remote_host, &remote_serv,
			&local_host, &local_serv, &opt);

    if (!NIL_P(opt)) {
	rb_get_kwargs(opt, keyword_ids, 0, 1, kwargs);
	if (kwargs[0] != Qundef) {
	    resolv_timeout = kwargs[0];
	}
    }

    return rsock_init_inetsock(sock, remote_host, remote_serv,
			       local_host, local_serv, INET_CLIENT,
			       resolv_timeout);
}

static VALUE
tcp_sockaddr(struct sockaddr *addr, socklen_t len)
{
    return rsock_make_ipaddr(addr, len);
}

/*
 * call-seq:
 *   TCPSocket.gethostbyname(hostname) => [official_hostname, alias_hostnames, address_family, *address_list]
 *
 * Use Addrinfo.getaddrinfo instead.
 * This method is deprecated for the following reasons:
 *
 * - The 3rd element of the result is the address family of the first address.
 *   The address families of the rest of the addresses are not returned.
 * - gethostbyname() may take a long time and it may block other threads.
 *   (GVL cannot be released since gethostbyname() is not thread safe.)
 * - This method uses gethostbyname() function already removed from POSIX.
 *
 * This method lookups host information by _hostname_.
 *
 *   TCPSocket.gethostbyname("localhost")
 *   #=> ["localhost", ["hal"], 2, "127.0.0.1"]
 *
 */
static VALUE
tcp_s_gethostbyname(VALUE obj, VALUE host)
{
    rb_warn("TCPSocket.gethostbyname is deprecated; use Addrinfo.getaddrinfo instead.");
    struct rb_addrinfo *res =
	rsock_addrinfo(host, Qnil, AF_UNSPEC, SOCK_STREAM, AI_CANONNAME);
    return rsock_make_hostent(host, res, tcp_sockaddr);
}

void
rsock_init_tcpsocket(void)
{
    /*
     * Document-class: TCPSocket < IPSocket
     *
     * TCPSocket represents a TCP/IP client socket.
     *
     * A simple client may look like:
     *
     *   require 'socket'
     *
     *   s = TCPSocket.new 'localhost', 2000
     *
     *   while line = s.gets # Read lines from socket
     *     puts line         # and print them
     *   end
     *
     *   s.close             # close socket when done
     *
     */
    rb_cTCPSocket = rb_define_class("TCPSocket", rb_cIPSocket);
    rb_define_singleton_method(rb_cTCPSocket, "gethostbyname", tcp_s_gethostbyname, 1);
    rb_define_method(rb_cTCPSocket, "initialize", tcp_init, -1);
}
