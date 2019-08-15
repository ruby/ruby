/************************************************

  basicsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

/*
 * call-seq:
 *   BasicSocket.for_fd(fd) => basicsocket
 *
 * Returns a socket object which contains the file descriptor, _fd_.
 *
 *   # If invoked by inetd, STDIN/STDOUT/STDERR is a socket.
 *   STDIN_SOCK = Socket.for_fd(STDIN.fileno)
 *   p STDIN_SOCK.remote_address
 *
 */
static VALUE
bsock_s_for_fd(VALUE klass, VALUE fd)
{
    rb_io_t *fptr;
    VALUE sock = rsock_init_sock(rb_obj_alloc(klass), NUM2INT(fd));

    GetOpenFile(sock, fptr);

    return sock;
}

/*
 * call-seq:
 *   basicsocket.shutdown([how]) => 0
 *
 * Calls shutdown(2) system call.
 *
 * s.shutdown(Socket::SHUT_RD) disallows further read.
 *
 * s.shutdown(Socket::SHUT_WR) disallows further write.
 *
 * s.shutdown(Socket::SHUT_RDWR) disallows further read and write.
 *
 * _how_ can be symbol or string:
 * - :RD, :SHUT_RD, "RD" and "SHUT_RD" are accepted as Socket::SHUT_RD.
 * - :WR, :SHUT_WR, "WR" and "SHUT_WR" are accepted as Socket::SHUT_WR.
 * - :RDWR, :SHUT_RDWR, "RDWR" and "SHUT_RDWR" are accepted as Socket::SHUT_RDWR.
 *
 *   UNIXSocket.pair {|s1, s2|
 *     s1.puts "ping"
 *     s1.shutdown(:WR)
 *     p s2.read          #=> "ping\n"
 *     s2.puts "pong"
 *     s2.close
 *     p s1.read          #=> "pong\n"
 *   }
 *
 */
static VALUE
bsock_shutdown(int argc, VALUE *argv, VALUE sock)
{
    VALUE howto;
    int how;
    rb_io_t *fptr;

    rb_scan_args(argc, argv, "01", &howto);
    if (howto == Qnil)
	how = SHUT_RDWR;
    else {
	how = rsock_shutdown_how_arg(howto);
        if (how != SHUT_WR && how != SHUT_RD && how != SHUT_RDWR) {
	    rb_raise(rb_eArgError, "`how' should be either :SHUT_RD, :SHUT_WR, :SHUT_RDWR");
	}
    }
    GetOpenFile(sock, fptr);
    if (shutdown(fptr->fd, how) == -1)
	rb_sys_fail("shutdown(2)");

    return INT2FIX(0);
}

/*
 * call-seq:
 *   basicsocket.close_read => nil
 *
 * Disallows further read using shutdown system call.
 *
 *   s1, s2 = UNIXSocket.pair
 *   s1.close_read
 *   s2.puts #=> Broken pipe (Errno::EPIPE)
 */
static VALUE
bsock_close_read(VALUE sock)
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    shutdown(fptr->fd, 0);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	return rb_io_close(sock);
    }
    fptr->mode &= ~FMODE_READABLE;

    return Qnil;
}

/*
 * call-seq:
 *   basicsocket.close_write => nil
 *
 * Disallows further write using shutdown system call.
 *
 *   UNIXSocket.pair {|s1, s2|
 *     s1.print "ping"
 *     s1.close_write
 *     p s2.read        #=> "ping"
 *     s2.print "pong"
 *     s2.close
 *     p s1.read        #=> "pong"
 *   }
 */
static VALUE
bsock_close_write(VALUE sock)
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	return rb_io_close(sock);
    }
    shutdown(fptr->fd, 1);
    fptr->mode &= ~FMODE_WRITABLE;

    return Qnil;
}

/*
 * Document-method: setsockopt
 * call-seq:
 *   setsockopt(level, optname, optval)
 *   setsockopt(socketoption)
 *
 * Sets a socket option. These are protocol and system specific, see your
 * local system documentation for details.
 *
 * === Parameters
 * * +level+ is an integer, usually one of the SOL_ constants such as
 *   Socket::SOL_SOCKET, or a protocol level.
 *   A string or symbol of the name, possibly without prefix, is also
 *   accepted.
 * * +optname+ is an integer, usually one of the SO_ constants, such
 *   as Socket::SO_REUSEADDR.
 *   A string or symbol of the name, possibly without prefix, is also
 *   accepted.
 * * +optval+ is the value of the option, it is passed to the underlying
 *   setsockopt() as a pointer to a certain number of bytes. How this is
 *   done depends on the type:
 *   - Integer: value is assigned to an int, and a pointer to the int is
 *     passed, with length of sizeof(int).
 *   - true or false: 1 or 0 (respectively) is assigned to an int, and the
 *     int is passed as for an Integer. Note that +false+ must be passed,
 *     not +nil+.
 *   - String: the string's data and length is passed to the socket.
 * * +socketoption+ is an instance of Socket::Option
 *
 * === Examples
 *
 * Some socket options are integers with boolean values, in this case
 * #setsockopt could be called like this:
 *   sock.setsockopt(:SOCKET, :REUSEADDR, true)
 *   sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
 *   sock.setsockopt(Socket::Option.bool(:INET, :SOCKET, :REUSEADDR, true))
 *
 * Some socket options are integers with numeric values, in this case
 * #setsockopt could be called like this:
 *   sock.setsockopt(:IP, :TTL, 255)
 *   sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, 255)
 *   sock.setsockopt(Socket::Option.int(:INET, :IP, :TTL, 255))
 *
 * Option values may be structs. Passing them can be complex as it involves
 * examining your system headers to determine the correct definition. An
 * example is an +ip_mreq+, which may be defined in your system headers as:
 *   struct ip_mreq {
 *     struct  in_addr imr_multiaddr;
 *     struct  in_addr imr_interface;
 *   };
 *
 * In this case #setsockopt could be called like this:
 *   optval = IPAddr.new("224.0.0.251").hton +
 *            IPAddr.new(Socket::INADDR_ANY, Socket::AF_INET).hton
 *   sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, optval)
 *
*/
static VALUE
bsock_setsockopt(int argc, VALUE *argv, VALUE sock)
{
    VALUE lev, optname, val;
    int family, level, option;
    rb_io_t *fptr;
    int i;
    char *v;
    int vlen;

    if (argc == 1) {
        lev = rb_funcall(argv[0], rb_intern("level"), 0);
        optname = rb_funcall(argv[0], rb_intern("optname"), 0);
        val = rb_funcall(argv[0], rb_intern("data"), 0);
    }
    else {
        rb_scan_args(argc, argv, "30", &lev, &optname, &val);
    }

    GetOpenFile(sock, fptr);
    family = rsock_getfamily(fptr);
    level = rsock_level_arg(family, lev);
    option = rsock_optname_arg(family, level, optname);

    switch (TYPE(val)) {
      case T_FIXNUM:
	i = FIX2INT(val);
	goto numval;
      case T_FALSE:
	i = 0;
	goto numval;
      case T_TRUE:
	i = 1;
      numval:
	v = (char*)&i; vlen = (int)sizeof(i);
	break;
      default:
	StringValue(val);
	v = RSTRING_PTR(val);
	vlen = RSTRING_SOCKLEN(val);
	break;
    }

    rb_io_check_closed(fptr);
    if (setsockopt(fptr->fd, level, option, v, vlen) < 0)
        rsock_sys_fail_path("setsockopt(2)", fptr->pathv);

    return INT2FIX(0);
}

/*
 * Document-method: getsockopt
 * call-seq:
 *   getsockopt(level, optname) => socketoption
 *
 * Gets a socket option. These are protocol and system specific, see your
 * local system documentation for details. The option is returned as
 * a Socket::Option object.
 *
 * === Parameters
 * * +level+ is an integer, usually one of the SOL_ constants such as
 *   Socket::SOL_SOCKET, or a protocol level.
 *   A string or symbol of the name, possibly without prefix, is also
 *   accepted.
 * * +optname+ is an integer, usually one of the SO_ constants, such
 *   as Socket::SO_REUSEADDR.
 *   A string or symbol of the name, possibly without prefix, is also
 *   accepted.
 *
 * === Examples
 *
 * Some socket options are integers with boolean values, in this case
 * #getsockopt could be called like this:
 *
 *   reuseaddr = sock.getsockopt(:SOCKET, :REUSEADDR).bool
 *
 *   optval = sock.getsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR)
 *   optval = optval.unpack "i"
 *   reuseaddr = optval[0] == 0 ? false : true
 *
 * Some socket options are integers with numeric values, in this case
 * #getsockopt could be called like this:
 *
 *   ipttl = sock.getsockopt(:IP, :TTL).int
 *
 *   optval = sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL)
 *   ipttl = optval.unpack("i")[0]
 *
 * Option values may be structs. Decoding them can be complex as it involves
 * examining your system headers to determine the correct definition. An
 * example is a +struct linger+, which may be defined in your system headers
 * as:
 *   struct linger {
 *     int l_onoff;
 *     int l_linger;
 *   };
 *
 * In this case #getsockopt could be called like this:
 *
 *   # Socket::Option knows linger structure.
 *   onoff, linger = sock.getsockopt(:SOCKET, :LINGER).linger
 *
 *   optval =  sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER)
 *   onoff, linger = optval.unpack "ii"
 *   onoff = onoff == 0 ? false : true
*/
static VALUE
bsock_getsockopt(VALUE sock, VALUE lev, VALUE optname)
{
    int level, option;
    socklen_t len;
    char *buf;
    rb_io_t *fptr;
    int family;

    GetOpenFile(sock, fptr);
    family = rsock_getfamily(fptr);
    level = rsock_level_arg(family, lev);
    option = rsock_optname_arg(family, level, optname);
    len = 256;
#ifdef _AIX
    switch (option) {
      case SO_DEBUG:
      case SO_REUSEADDR:
      case SO_KEEPALIVE:
      case SO_DONTROUTE:
      case SO_BROADCAST:
      case SO_OOBINLINE:
        /* AIX doesn't set len for boolean options */
        len = sizeof(int);
    }
#endif
    buf = ALLOCA_N(char,len);

    rb_io_check_closed(fptr);

    if (getsockopt(fptr->fd, level, option, buf, &len) < 0)
	rsock_sys_fail_path("getsockopt(2)", fptr->pathv);

    return rsock_sockopt_new(family, level, option, rb_str_new(buf, len));
}

/*
 * call-seq:
 *   basicsocket.getsockname => sockaddr
 *
 * Returns the local address of the socket as a sockaddr string.
 *
 *   TCPServer.open("127.0.0.1", 15120) {|serv|
 *     p serv.getsockname #=> "\x02\x00;\x10\x7F\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00"
 *   }
 *
 * If Addrinfo object is preferred over the binary string,
 * use BasicSocket#local_address.
 */
static VALUE
bsock_getsockname(VALUE sock)
{
    union_sockaddr buf;
    socklen_t len = (socklen_t)sizeof buf;
    socklen_t len0 = len;
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (getsockname(fptr->fd, &buf.addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    if (len0 < len) len = len0;
    return rb_str_new((char*)&buf, len);
}

/*
 * call-seq:
 *   basicsocket.getpeername => sockaddr
 *
 * Returns the remote address of the socket as a sockaddr string.
 *
 *   TCPServer.open("127.0.0.1", 1440) {|serv|
 *     c = TCPSocket.new("127.0.0.1", 1440)
 *     s = serv.accept
 *     p s.getpeername #=> "\x02\x00\x82u\x7F\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00"
 *   }
 *
 * If Addrinfo object is preferred over the binary string,
 * use BasicSocket#remote_address.
 *
 */
static VALUE
bsock_getpeername(VALUE sock)
{
    union_sockaddr buf;
    socklen_t len = (socklen_t)sizeof buf;
    socklen_t len0 = len;
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (getpeername(fptr->fd, &buf.addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    if (len0 < len) len = len0;
    return rb_str_new((char*)&buf, len);
}

#if defined(HAVE_GETPEEREID) || defined(SO_PEERCRED) || defined(HAVE_GETPEERUCRED)
/*
 * call-seq:
 *   basicsocket.getpeereid => [euid, egid]
 *
 * Returns the user and group on the peer of the UNIX socket.
 * The result is a two element array which contains the effective uid and the effective gid.
 *
 *   Socket.unix_server_loop("/tmp/sock") {|s|
 *     begin
 *       euid, egid = s.getpeereid
 *
 *       # Check the connected client is myself or not.
 *       next if euid != Process.uid
 *
 *       # do something about my resource.
 *
 *     ensure
 *       s.close
 *     end
 *   }
 *
 */
static VALUE
bsock_getpeereid(VALUE self)
{
#if defined(HAVE_GETPEEREID)
    rb_io_t *fptr;
    uid_t euid;
    gid_t egid;
    GetOpenFile(self, fptr);
    if (getpeereid(fptr->fd, &euid, &egid) == -1)
	rb_sys_fail("getpeereid(3)");
    return rb_assoc_new(UIDT2NUM(euid), GIDT2NUM(egid));
#elif defined(SO_PEERCRED) /* GNU/Linux */
    rb_io_t *fptr;
    struct ucred cred;
    socklen_t len = sizeof(cred);
    GetOpenFile(self, fptr);
    if (getsockopt(fptr->fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == -1)
	rb_sys_fail("getsockopt(SO_PEERCRED)");
    return rb_assoc_new(UIDT2NUM(cred.uid), GIDT2NUM(cred.gid));
#elif defined(HAVE_GETPEERUCRED) /* Solaris */
    rb_io_t *fptr;
    ucred_t *uc = NULL;
    VALUE ret;
    GetOpenFile(self, fptr);
    if (getpeerucred(fptr->fd, &uc) == -1)
	rb_sys_fail("getpeerucred(3C)");
    ret = rb_assoc_new(UIDT2NUM(ucred_geteuid(uc)), GIDT2NUM(ucred_getegid(uc)));
    ucred_free(uc);
    return ret;
#endif
}
#else
#define bsock_getpeereid rb_f_notimplement
#endif

/*
 * call-seq:
 *   bsock.local_address => addrinfo
 *
 * Returns an Addrinfo object for local address obtained by getsockname.
 *
 * Note that addrinfo.protocol is filled by 0.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|s|
 *     p s.local_address #=> #<Addrinfo: 192.168.0.129:36873 TCP>
 *   }
 *
 *   TCPServer.open("127.0.0.1", 1512) {|serv|
 *     p serv.local_address #=> #<Addrinfo: 127.0.0.1:1512 TCP>
 *   }
 *
 */
static VALUE
bsock_local_address(VALUE sock)
{
    union_sockaddr buf;
    socklen_t len = (socklen_t)sizeof buf;
    socklen_t len0 = len;
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (getsockname(fptr->fd, &buf.addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    if (len0 < len) len = len0;
    return rsock_fd_socket_addrinfo(fptr->fd, &buf.addr, len);
}

/*
 * call-seq:
 *   bsock.remote_address => addrinfo
 *
 * Returns an Addrinfo object for remote address obtained by getpeername.
 *
 * Note that addrinfo.protocol is filled by 0.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|s|
 *     p s.remote_address #=> #<Addrinfo: 221.186.184.68:80 TCP>
 *   }
 *
 *   TCPServer.open("127.0.0.1", 1728) {|serv|
 *     c = TCPSocket.new("127.0.0.1", 1728)
 *     s = serv.accept
 *     p s.remote_address #=> #<Addrinfo: 127.0.0.1:36504 TCP>
 *   }
 *
 */
static VALUE
bsock_remote_address(VALUE sock)
{
    union_sockaddr buf;
    socklen_t len = (socklen_t)sizeof buf;
    socklen_t len0 = len;
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (getpeername(fptr->fd, &buf.addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    if (len0 < len) len = len0;
    return rsock_fd_socket_addrinfo(fptr->fd, &buf.addr, len);
}

/*
 * call-seq:
 *   basicsocket.send(mesg, flags [, dest_sockaddr]) => numbytes_sent
 *
 * send _mesg_ via _basicsocket_.
 *
 * _mesg_ should be a string.
 *
 * _flags_ should be a bitwise OR of Socket::MSG_* constants.
 *
 * _dest_sockaddr_ should be a packed sockaddr string or an addrinfo.
 *
 *   TCPSocket.open("localhost", 80) {|s|
 *     s.send "GET / HTTP/1.0\r\n\r\n", 0
 *     p s.read
 *   }
 */
VALUE
rsock_bsock_send(int argc, VALUE *argv, VALUE sock)
{
    struct rsock_send_arg arg;
    VALUE flags, to;
    rb_io_t *fptr;
    ssize_t n;
    rb_blocking_function_t *func;
    const char *funcname;

    rb_scan_args(argc, argv, "21", &arg.mesg, &flags, &to);

    StringValue(arg.mesg);
    if (!NIL_P(to)) {
	SockAddrStringValue(to);
	to = rb_str_new4(to);
	arg.to = (struct sockaddr *)RSTRING_PTR(to);
	arg.tolen = RSTRING_SOCKLEN(to);
	func = rsock_sendto_blocking;
	funcname = "sendto(2)";
    }
    else {
	func = rsock_send_blocking;
	funcname = "send(2)";
    }
    GetOpenFile(sock, fptr);
    arg.fd = fptr->fd;
    arg.flags = NUM2INT(flags);
    while (rsock_maybe_fd_writable(arg.fd),
	   (n = (ssize_t)BLOCKING_REGION_FD(func, &arg)) < 0) {
	if (rb_io_wait_writable(arg.fd)) {
	    continue;
	}
	rb_sys_fail(funcname);
    }
    return SSIZET2NUM(n);
}

/*
 * call-seq:
 *   basicsocket.do_not_reverse_lookup => true or false
 *
 * Gets the do_not_reverse_lookup flag of _basicsocket_.
 *
 *   require 'socket'
 *
 *   BasicSocket.do_not_reverse_lookup = false
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.do_not_reverse_lookup      #=> false
 *   }
 *   BasicSocket.do_not_reverse_lookup = true
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.do_not_reverse_lookup      #=> true
 *   }
 */
static VALUE
bsock_do_not_reverse_lookup(VALUE sock)
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    return (fptr->mode & FMODE_NOREVLOOKUP) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   basicsocket.do_not_reverse_lookup = bool
 *
 * Sets the do_not_reverse_lookup flag of _basicsocket_.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.do_not_reverse_lookup       #=> true
 *     p sock.peeraddr                    #=> ["AF_INET", 80, "221.186.184.68", "221.186.184.68"]
 *     sock.do_not_reverse_lookup = false
 *     p sock.peeraddr                    #=> ["AF_INET", 80, "carbon.ruby-lang.org", "54.163.249.195"]
 *   }
 *
 */
static VALUE
bsock_do_not_reverse_lookup_set(VALUE sock, VALUE state)
{
    rb_io_t *fptr;

    GetOpenFile(sock, fptr);
    if (RTEST(state)) {
	fptr->mode |= FMODE_NOREVLOOKUP;
    }
    else {
	fptr->mode &= ~FMODE_NOREVLOOKUP;
    }
    return sock;
}

/*
 * call-seq:
 *   basicsocket.recv(maxlen[, flags[, outbuf]]) => mesg
 *
 * Receives a message.
 *
 * _maxlen_ is the maximum number of bytes to receive.
 *
 * _flags_ should be a bitwise OR of Socket::MSG_* constants.
 *
 * _outbuf_ will contain only the received data after the method call
 * even if it is not empty at the beginning.
 *
 *   UNIXSocket.pair {|s1, s2|
 *     s1.puts "Hello World"
 *     p s2.recv(4)                     #=> "Hell"
 *     p s2.recv(4, Socket::MSG_PEEK)   #=> "o Wo"
 *     p s2.recv(4)                     #=> "o Wo"
 *     p s2.recv(10)                    #=> "rld\n"
 *   }
 */
static VALUE
bsock_recv(int argc, VALUE *argv, VALUE sock)
{
    return rsock_s_recvfrom(sock, argc, argv, RECV_RECV);
}

/* :nodoc: */
static VALUE
bsock_recv_nonblock(VALUE sock, VALUE len, VALUE flg, VALUE str, VALUE ex)
{
    return rsock_s_recvfrom_nonblock(sock, len, flg, str, ex, RECV_RECV);
}

/*
 * call-seq:
 *   BasicSocket.do_not_reverse_lookup => true or false
 *
 * Gets the global do_not_reverse_lookup flag.
 *
 *   BasicSocket.do_not_reverse_lookup  #=> false
 */
static VALUE
bsock_do_not_rev_lookup(void)
{
    return rsock_do_not_reverse_lookup?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   BasicSocket.do_not_reverse_lookup = bool
 *
 * Sets the global do_not_reverse_lookup flag.
 *
 * The flag is used for initial value of do_not_reverse_lookup for each socket.
 *
 *   s1 = TCPSocket.new("localhost", 80)
 *   p s1.do_not_reverse_lookup                 #=> true
 *   BasicSocket.do_not_reverse_lookup = false
 *   s2 = TCPSocket.new("localhost", 80)
 *   p s2.do_not_reverse_lookup                 #=> false
 *   p s1.do_not_reverse_lookup                 #=> true
 *
 */
static VALUE
bsock_do_not_rev_lookup_set(VALUE self, VALUE val)
{
    rsock_do_not_reverse_lookup = RTEST(val);
    return val;
}

void
rsock_init_basicsocket(void)
{
    /*
     * Document-class: BasicSocket < IO
     *
     * BasicSocket is the super class for all the Socket classes.
     */
    rb_cBasicSocket = rb_define_class("BasicSocket", rb_cIO);
    rb_undef_method(rb_cBasicSocket, "initialize");

    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup",
			       bsock_do_not_rev_lookup, 0);
    rb_define_singleton_method(rb_cBasicSocket, "do_not_reverse_lookup=",
			       bsock_do_not_rev_lookup_set, 1);
    rb_define_singleton_method(rb_cBasicSocket, "for_fd", bsock_s_for_fd, 1);

    rb_define_method(rb_cBasicSocket, "close_read", bsock_close_read, 0);
    rb_define_method(rb_cBasicSocket, "close_write", bsock_close_write, 0);
    rb_define_method(rb_cBasicSocket, "shutdown", bsock_shutdown, -1);
    rb_define_method(rb_cBasicSocket, "setsockopt", bsock_setsockopt, -1);
    rb_define_method(rb_cBasicSocket, "getsockopt", bsock_getsockopt, 2);
    rb_define_method(rb_cBasicSocket, "getsockname", bsock_getsockname, 0);
    rb_define_method(rb_cBasicSocket, "getpeername", bsock_getpeername, 0);
    rb_define_method(rb_cBasicSocket, "getpeereid", bsock_getpeereid, 0);
    rb_define_method(rb_cBasicSocket, "local_address", bsock_local_address, 0);
    rb_define_method(rb_cBasicSocket, "remote_address", bsock_remote_address, 0);
    rb_define_method(rb_cBasicSocket, "send", rsock_bsock_send, -1);
    rb_define_method(rb_cBasicSocket, "recv", bsock_recv, -1);

    rb_define_method(rb_cBasicSocket, "do_not_reverse_lookup", bsock_do_not_reverse_lookup, 0);
    rb_define_method(rb_cBasicSocket, "do_not_reverse_lookup=", bsock_do_not_reverse_lookup_set, 1);

    /* for ext/socket/lib/socket.rb use only: */
    rb_define_private_method(rb_cBasicSocket,
			     "__recv_nonblock", bsock_recv_nonblock, 4);

#if MSG_DONTWAIT_RELIABLE
    rb_define_private_method(rb_cBasicSocket,
			     "__read_nonblock", rsock_read_nonblock, 3);
    rb_define_private_method(rb_cBasicSocket,
			     "__write_nonblock", rsock_write_nonblock, 2);
#endif

    /* in ancdata.c */
    rb_define_private_method(rb_cBasicSocket, "__sendmsg",
			     rsock_bsock_sendmsg, 4);
    rb_define_private_method(rb_cBasicSocket, "__sendmsg_nonblock",
			     rsock_bsock_sendmsg_nonblock, 5);
    rb_define_private_method(rb_cBasicSocket, "__recvmsg",
			     rsock_bsock_recvmsg, 4);
    rb_define_private_method(rb_cBasicSocket, "__recvmsg_nonblock",
			    rsock_bsock_recvmsg_nonblock, 5);

}
