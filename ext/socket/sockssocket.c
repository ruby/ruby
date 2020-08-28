/************************************************

  sockssocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

#ifdef SOCKS
/*
 * call-seq:
 *   SOCKSSocket.new(host, port) => socket
 *
 * Opens a SOCKS connection to +host+ via the SOCKS server.
 *
 * The SOCKS server configuration varies by implementation
 *
 * When using the Dante libsocks/libsocksd implementation it is configured as SOCKS_SERVER env var.
 *
 * See: https://manpages.debian.org/testing/dante-client/socksify.1.en.html for full env variable support.
 *
 */
static VALUE
socks_init(VALUE sock, VALUE host, VALUE port)
{
    static int init = 0;

    if (init == 0) {
	SOCKSinit("ruby");
	init = 1;
    }

    return rsock_init_inetsock(sock, host, port, Qnil, Qnil, INET_SOCKS, Qnil);
}

#ifdef SOCKS5
/*
 * Closes the SOCKS connection.
 *
 */
static VALUE
socks_s_close(VALUE sock)
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    shutdown(fptr->fd, 2);
    return rb_io_close(sock);
}
#endif
#endif

void
rsock_init_sockssocket(void)
{
#ifdef SOCKS
    /*
     * Document-class: SOCKSSocket < TCPSocket
     *
     * SOCKS is an Internet protocol that routes packets between a client and
     * a server through a proxy server.  SOCKS5, if supported, additionally
     * provides authentication so only authorized users may access a server.
     */
    rb_cSOCKSSocket = rb_define_class("SOCKSSocket", rb_cTCPSocket);
    rb_define_method(rb_cSOCKSSocket, "initialize", socks_init, 2);
#ifdef SOCKS5
    rb_define_method(rb_cSOCKSSocket, "close", socks_s_close, 0);
#endif
#endif
}
