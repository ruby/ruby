/************************************************

  tcpsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

/*
 * call-seq:
 *    TCPSocket.new(remote_host, remote_port, local_host=nil, local_port=nil, resolv_timeout: nil, connect_timeout: nil, fast_fallback: true)
 *
 * Opens a TCP connection to +remote_host+ on +remote_port+.  If +local_host+
 * and +local_port+ are specified, then those parameters are used on the local
 * end to establish the connection.
 *
 * Starting from Ruby 3.4, this method operates according to the
 * Happy Eyeballs Version 2 ({RFC 8305}[https://datatracker.ietf.org/doc/html/rfc8305])
 * algorithm by default, except on Windows.
 *
 * For details on Happy Eyeballs Version 2,
 * see {Socket.tcp_fast_fallback=}[rdoc-ref:Socket.tcp_fast_fallback=].
 *
 * To make it behave the same as in Ruby 3.3 and earlier,
 * explicitly specify the option fast_fallback:false.
 * Or, setting Socket.tcp_fast_fallback=false will disable
 * Happy Eyeballs Version 2 not only for this method but for all Socket globally.
 *
 * When using TCPSocket.new on Windows, Happy Eyeballs Version 2 is not provided,
 * and it behaves the same as in Ruby 3.3 and earlier.
 *
 * [:resolv_timeout] Specifies the timeout in seconds from when the hostname resolution starts.
 * [:connect_timeout] This method sequentially attempts connecting to all candidate destination addresses.<br>The +connect_timeout+ specifies the timeout in seconds from the start of the connection attempt to the last candidate.<br>By default, all connection attempts continue until the timeout occurs.<br>When +fast_fallback:false+ is explicitly specified,<br>a timeout is set for each connection attempt and any connection attempt that exceeds its timeout will be canceled.
 * [:open_timeout] Specifies the timeout in seconds from the start of the method execution.<br>If this timeout is reached while there are still addresses that have not yet been attempted for connection, no further attempts will be made.<br>If this option is specified together with other timeout options, an +ArgumentError+ will be raised.
 * [:fast_fallback] Enables the Happy Eyeballs Version 2 algorithm (enabled by default).
 */
static VALUE
tcp_init(int argc, VALUE *argv, VALUE sock)
{
    VALUE remote_host, remote_serv;
    VALUE local_host, local_serv;
    VALUE opt;
    static ID keyword_ids[5];
    VALUE kwargs[5];
    VALUE resolv_timeout = Qnil;
    VALUE connect_timeout = Qnil;
    VALUE open_timeout = Qnil;
    VALUE fast_fallback = Qnil;
    VALUE test_mode_settings = Qnil;

    if (!keyword_ids[0]) {
        CONST_ID(keyword_ids[0], "resolv_timeout");
        CONST_ID(keyword_ids[1], "connect_timeout");
        CONST_ID(keyword_ids[2], "open_timeout");
        CONST_ID(keyword_ids[3], "fast_fallback");
        CONST_ID(keyword_ids[4], "test_mode_settings");
    }

    rb_scan_args(argc, argv, "22:", &remote_host, &remote_serv,
                        &local_host, &local_serv, &opt);

    if (!NIL_P(opt)) {
        rb_get_kwargs(opt, keyword_ids, 0, 5, kwargs);
        if (kwargs[0] != Qundef) { resolv_timeout = kwargs[0]; }
        if (kwargs[1] != Qundef) { connect_timeout = kwargs[1]; }
        if (kwargs[2] != Qundef) { open_timeout = kwargs[2]; }
        if (kwargs[3] != Qundef) { fast_fallback = kwargs[3]; }
        if (kwargs[4] != Qundef) { test_mode_settings = kwargs[4]; }
    }

    if (fast_fallback == Qnil) {
        fast_fallback = rb_ivar_get(rb_cSocket, tcp_fast_fallback);
        if (fast_fallback == Qnil) fast_fallback = Qtrue;
    }

    return rsock_init_inetsock(sock, remote_host, remote_serv,
                               local_host, local_serv, INET_CLIENT,
                               resolv_timeout, connect_timeout, open_timeout,
                               fast_fallback, test_mode_settings);
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
        rsock_addrinfo(host, Qnil, AF_UNSPEC, SOCK_STREAM, AI_CANONNAME, 0);
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
