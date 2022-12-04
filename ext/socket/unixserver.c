/************************************************

  unixserver.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
/*
 * call-seq:
 *   UNIXServer.new(path) => unixserver
 *
 * Creates a new UNIX server socket bound to _path_.
 *
 *   require 'socket'
 *
 *   serv = UNIXServer.new("/tmp/sock")
 *   s = serv.accept
 *   p s.read
 */
static VALUE
unix_svr_init(VALUE sock, VALUE path)
{
    return rsock_init_unixsock(sock, path, 1);
}

/*
 * call-seq:
 *   unixserver.accept => unixsocket
 *
 * Accepts an incoming connection.
 * It returns a new UNIXSocket object.
 *
 *   UNIXServer.open("/tmp/sock") {|serv|
 *     UNIXSocket.open("/tmp/sock") {|c|
 *       s = serv.accept
 *       s.puts "hi"
 *       s.close
 *       p c.read #=> "hi\n"
 *     }
 *   }
 *
 */
static VALUE
unix_accept(VALUE server)
{
    struct sockaddr_un buffer;
    socklen_t length = sizeof(buffer);

    return rsock_s_accept(rb_cUNIXSocket, server, (struct sockaddr*)&buffer, &length);
}

/* :nodoc: */
static VALUE
unix_accept_nonblock(VALUE sock, VALUE ex)
{
    rb_io_t *fptr;
    struct sockaddr_un from;
    socklen_t fromlen;

    GetOpenFile(sock, fptr);
    fromlen = (socklen_t)sizeof(from);
    return rsock_s_accept_nonblock(rb_cUNIXSocket, ex, fptr,
                                   (struct sockaddr *)&from, &fromlen);
}

/*
 * call-seq:
 *   unixserver.sysaccept => file_descriptor
 *
 * Accepts a new connection.
 * It returns the new file descriptor which is an integer.
 *
 *   UNIXServer.open("/tmp/sock") {|serv|
 *     UNIXSocket.open("/tmp/sock") {|c|
 *       fd = serv.sysaccept
 *       s = IO.new(fd)
 *       s.puts "hi"
 *       s.close
 *       p c.read #=> "hi\n"
 *     }
 *   }
 *
 */
static VALUE
unix_sysaccept(VALUE server)
{
    struct sockaddr_un buffer;
    socklen_t length = sizeof(buffer);

    return rsock_s_accept(0, server, (struct sockaddr*)&buffer, &length);
}

#endif

void
rsock_init_unixserver(void)
{
#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
    /*
     * Document-class: UNIXServer < UNIXSocket
     *
     * UNIXServer represents a UNIX domain stream server socket.
     *
     */
    rb_cUNIXServer = rb_define_class("UNIXServer", rb_cUNIXSocket);
    rb_define_method(rb_cUNIXServer, "initialize", unix_svr_init, 1);
    rb_define_method(rb_cUNIXServer, "accept", unix_accept, 0);

    rb_define_private_method(rb_cUNIXServer,
                             "__accept_nonblock", unix_accept_nonblock, 1);

    rb_define_method(rb_cUNIXServer, "sysaccept", unix_sysaccept, 0);
    rb_define_method(rb_cUNIXServer, "listen", rsock_sock_listen, 1); /* in socket.c */
#endif
}
