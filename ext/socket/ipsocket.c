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
	struct rb_addrinfo *res;
    } remote, local;
    int type;
    int fd;
    VALUE resolv_timeout;
    VALUE connect_timeout;
};

static VALUE
inetsock_cleanup(VALUE v)
{
    struct inetsock_arg *arg = (void *)v;
    if (arg->remote.res) {
	rb_freeaddrinfo(arg->remote.res);
	arg->remote.res = 0;
    }
    if (arg->local.res) {
	rb_freeaddrinfo(arg->local.res);
	arg->local.res = 0;
    }
    if (arg->fd >= 0) {
	close(arg->fd);
    }
    return Qnil;
}

static VALUE
init_inetsock_internal(VALUE v)
{
    struct inetsock_arg *arg = (void *)v;
    int error = 0;
    int type = arg->type;
    struct addrinfo *res, *lres;
    int fd, status = 0, local = 0;
    int family = AF_UNSPEC;
    const char *syscall = 0;
    VALUE connect_timeout = arg->connect_timeout;
    struct timeval tv_storage;
    struct timeval *tv = NULL;

    if (!NIL_P(connect_timeout)) {
        tv_storage = rb_time_interval(connect_timeout);
        tv = &tv_storage;
    }

    arg->remote.res = rsock_addrinfo(arg->remote.host, arg->remote.serv,
				     family, SOCK_STREAM,
				     (type == INET_SERVER) ? AI_PASSIVE : 0);


    /*
     * Maybe also accept a local address
     */

    if (type != INET_SERVER && (!NIL_P(arg->local.host) || !NIL_P(arg->local.serv))) {
	arg->local.res = rsock_addrinfo(arg->local.host, arg->local.serv,
					family, SOCK_STREAM, 0);
    }

    arg->fd = fd = -1;
    for (res = arg->remote.res->ai; res; res = res->ai_next) {
#if !defined(INET6) && defined(AF_INET6)
	if (res->ai_family == AF_INET6)
	    continue;
#endif
        lres = NULL;
        if (arg->local.res) {
            for (lres = arg->local.res->ai; lres; lres = lres->ai_next) {
                if (lres->ai_family == res->ai_family)
                    break;
            }
            if (!lres) {
                if (res->ai_next || status < 0)
                    continue;
                /* Use a different family local address if no choice, this
                 * will cause EAFNOSUPPORT. */
                lres = arg->local.res->ai;
            }
        }
	status = rsock_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
	syscall = "socket(2)";
	fd = status;
	if (fd < 0) {
	    error = errno;
	    continue;
	}
	arg->fd = fd;
	if (type == INET_SERVER) {
#if !defined(_WIN32) && !defined(__CYGWIN__)
	    status = 1;
	    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
		       (char*)&status, (socklen_t)sizeof(status));
#endif
	    status = bind(fd, res->ai_addr, res->ai_addrlen);
	    syscall = "bind(2)";
	}
	else {
	    if (lres) {
#if !defined(_WIN32) && !defined(__CYGWIN__)
                status = 1;
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
                           (char*)&status, (socklen_t)sizeof(status));
#endif
		status = bind(fd, lres->ai_addr, lres->ai_addrlen);
		local = status;
		syscall = "bind(2)";
	    }

	    if (status >= 0) {
		status = rsock_connect(fd, res->ai_addr, res->ai_addrlen,
				       (type == INET_SOCKS), tv);
		syscall = "connect(2)";
	    }
	}

	if (status < 0) {
	    error = errno;
	    close(fd);
	    arg->fd = fd = -1;
	    continue;
	} else
	    break;
    }
    if (status < 0) {
	VALUE host, port;

	if (local < 0) {
	    host = arg->local.host;
	    port = arg->local.serv;
	} else {
	    host = arg->remote.host;
	    port = arg->remote.serv;
	}

	rsock_syserr_fail_host_port(error, syscall, host, port);
    }

    arg->fd = -1;

    if (type == INET_SERVER) {
	status = listen(fd, SOMAXCONN);
	if (status < 0) {
	    error = errno;
	    close(fd);
	    rb_syserr_fail(error, "listen(2)");
	}
    }

    /* create new instance */
    return rsock_init_sock(arg->sock, fd);
}

static void
getclockofday(struct timespec *ts)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
    if (clock_gettime(CLOCK_MONOTONIC, ts) == 0)
        return;
#endif
    rb_timespec_now(ts);
}

/*
 * Don't inline this, since library call is already time consuming
 * and we don't want "struct timespec" on stack too long for GC
 */
NOINLINE(rb_hrtime_t rb_hrtime_now(void));
rb_hrtime_t
rb_hrtime_now(void)
{
    struct timespec ts;

    getclockofday(&ts);
    return rb_timespec2hrtime(&ts);
}

#if defined(F_SETFL) && defined(F_GETFL)
static void
socket_nonblock_set(int fd, int nonblock)
{
    int flags = fcntl(fd, F_GETFL);
    if (flags == -1) { rb_sys_fail(0); }
    if (nonblock) {
	if ((flags & O_NONBLOCK) != 0) { return; }
	flags |= O_NONBLOCK;
    } else {
	if ((flags & O_NONBLOCK) == 0) { return; }
	flags &= ~O_NONBLOCK;
    }
    if (fcntl(fd, F_SETFL, flags) == -1) { rb_sys_fail(0); }
    return;
}

/*
 * @end is the absolute time when @ts is set to expire
 * Returns true if @end has past
 * Updates @ts and returns false otherwise
 */
static int
hrtime_update_expire(rb_hrtime_t *timeout, const rb_hrtime_t end)
{
    rb_hrtime_t now = rb_hrtime_now();
    if (now > end) return 1;
    *timeout = end - now;
    return 0;
}

static int
check_socket_error(const int fd) {
    int value;
    socklen_t len = (socklen_t)sizeof(value);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, (void *)&value, &len);
    return value;
}

static int
find_connected_socket(VALUE fds, rb_fdset_t *writefds) {
    for (int i=0; i<RARRAY_LEN(fds); i++) {
        int fd = FIX2INT(RARRAY_AREF(fds, i));
        if (rb_fd_isset(fd, writefds)) {
            int error = check_socket_error(fd);
            switch (error) {
              case 0: // success
                return fd;
              case EINPROGRESS:
                break;
              default: // fail
                close(fd);
                errno = error;
                rb_ary_delete_at(fds, i);
                i--;
                break;
            }
        }
    }
    return -1;
}

static int
set_fds(const VALUE fds, rb_fdset_t *set) {
    int nfds = 0;
    rb_fd_init(set);
    for (int i=0; i<RARRAY_LEN(fds); i++) {
        int fd = FIX2INT(RARRAY_AREF(fds, i));
        if (fd > nfds) { nfds = fd; }
        rb_fd_set(fd, set);
    }
    nfds++;
    return nfds;
}

#define CONNECTION_ATTEMPT_DELAY_USEC 250000 /* 250ms is a recommended value in RFC8305 */

static VALUE
init_inetsock_internal_happy(VALUE v)
{
    struct inetsock_arg *arg = (void *)v;
    struct addrinfo *res, *lres;
    int fd, nfds, error = 0, status = 0, local = 0, family = AF_UNSPEC;
    const char *syscall = 0;
    rb_fdset_t writefds;
    VALUE fds_ary = rb_ary_tmp_new(1);
    struct timeval connection_attempt_delay;
    rb_hrtime_t rel = 0, end = 0, *limit = NULL;

    if (!NIL_P(arg->connect_timeout)) {
        struct timeval timeout = rb_time_interval(arg->connect_timeout);
        rel = rb_timeval2hrtime(&timeout);
        limit = &rel;
        end = rb_hrtime_add(rb_hrtime_now(), rel);
    }

    arg->remote.res = rsock_addrinfo(arg->remote.host, arg->remote.serv,
				     family, SOCK_STREAM, 0);

    /*
     * Maybe also accept a local address
     */
    if (!NIL_P(arg->local.host) || !NIL_P(arg->local.serv)) {
	arg->local.res = rsock_addrinfo(arg->local.host, arg->local.serv,
					family, SOCK_STREAM, 0);
    }

    arg->fd = fd = -1;

    for (res = arg->remote.res->ai; res; res = res->ai_next) {
#if !defined(INET6) && defined(AF_INET6)
	if (res->ai_family == AF_INET6)
	    continue;
#endif
        lres = NULL;
        if (arg->local.res) {
            for (lres = arg->local.res->ai; lres; lres = lres->ai_next) {
                if (lres->ai_family == res->ai_family) { break; }
            }
            if (!lres) {
                if (res->ai_next || status < 0) { continue; }
                /* Use a different family local address if no choice, this
                 * will cause EAFNOSUPPORT. */
                lres = arg->local.res->ai;
            }
        }
        status = rsock_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
        syscall = "socket(2)";
        fd = status;
        if (fd < 0) {
            error = errno;
            continue;
        }
        arg->fd = fd;
        socket_nonblock_set(fd, true);
        if (lres) {
#if !defined(_WIN32) && !defined(__CYGWIN__)
            status = 1;
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
                       (char*)&status, (socklen_t)sizeof(status));
#endif
            status = bind(fd, lres->ai_addr, lres->ai_addrlen);
            local = status;
            syscall = "bind(2)";
        }
        if (status >= 0) {
            status = connect(fd, res->ai_addr, res->ai_addrlen);
            syscall = "connect(2)";
        }

        if (status < 0 && errno != EINPROGRESS) {
            error = errno;
            close(fd);
            arg->fd = fd = -1;
            continue;
        } else {
            rb_ary_push(fds_ary, INT2FIX(fd));
            nfds = set_fds(fds_ary, &writefds);
            /* connection_attempt_delay may be modified by select(2) in linux */
            connection_attempt_delay.tv_sec = 0;
            connection_attempt_delay.tv_usec = CONNECTION_ATTEMPT_DELAY_USEC;
            status = rb_thread_fd_select(nfds, NULL, &writefds, NULL, &connection_attempt_delay);
            syscall = "select(2)";
            if (status >= 0) {
                arg->fd = fd = find_connected_socket(fds_ary, &writefds);
                if (fd >= 0) { break; }
                status = -1; // no connected socket found
            }
            error = errno;
        }
    }

    /* wait connection */
    while (fd < 0 && RARRAY_LEN(fds_ary) > 0) {
        struct timeval tv_storage, *tv = NULL;
        if (limit) { // if timeout is specified
            if (hrtime_update_expire(limit, end)) { // check if timeout has expired and update timeout
                status = -1;
                error = ETIMEDOUT;
                break;
            }
            rb_hrtime2timeval(&tv_storage, limit); // set new timeout
            tv = &tv_storage;
        }
        nfds = set_fds(fds_ary, &writefds);
        status = rb_thread_fd_select(nfds, NULL, &writefds, NULL, tv);
        syscall = "select(2)";
        if (status > 0) {
            arg->fd = fd = find_connected_socket(fds_ary, &writefds);
            if (fd >= 0) { break; }
            status = -1; // no connected socket found
        }
        error = errno;
    }

    /* close unused fds */
    for (int i=0; i<RARRAY_LEN(fds_ary); i++) {
        int _fd = FIX2INT(RARRAY_AREF(fds_ary, i));
        if (_fd != fd) { close(_fd); }
    }
    rb_ary_clear(fds_ary);

    if (status < 0) {
	VALUE host, port;

	if (local < 0) {
	    host = arg->local.host;
	    port = arg->local.serv;
	} else {
	    host = arg->remote.host;
	    port = arg->remote.serv;
	}

	rsock_syserr_fail_host_port(error, syscall, host, port);
    }

    arg->fd = -1;
    socket_nonblock_set(fd, false);

    /* create new instance */
    return rsock_init_sock(arg->sock, fd);
}
#endif // defined(F_SETFL) && defined(F_GETFL)

VALUE
rsock_init_inetsock(VALUE sock, VALUE remote_host, VALUE remote_serv,
	            VALUE local_host, VALUE local_serv, int type,
		    VALUE resolv_timeout, VALUE connect_timeout)
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
    arg.resolv_timeout = resolv_timeout;
    arg.connect_timeout = connect_timeout;

#if defined(F_SETFL) && defined(F_GETFL) // if nonblocking mode is available
    if (type == INET_CLIENT) {
        return rb_ensure(init_inetsock_internal_happy, (VALUE)&arg,
                         inetsock_cleanup, (VALUE)&arg);
    }
#endif

    return rb_ensure(init_inetsock_internal, (VALUE)&arg,
                     inetsock_cleanup, (VALUE)&arg);
}

static ID id_numeric, id_hostname;

int
rsock_revlookup_flag(VALUE revlookup, int *norevlookup)
{
#define return_norevlookup(x) {*norevlookup = (x); return 1;}
    ID id;

    switch (revlookup) {
      case Qtrue:  return_norevlookup(0);
      case Qfalse: return_norevlookup(1);
      case Qnil: break;
      default:
	Check_Type(revlookup, T_SYMBOL);
	id = SYM2ID(revlookup);
	if (id == id_numeric) return_norevlookup(1);
	if (id == id_hostname) return_norevlookup(0);
	rb_raise(rb_eArgError, "invalid reverse_lookup flag: :%s", rb_id2name(id));
    }
    return 0;
#undef return_norevlookup
}

/*
 * call-seq:
 *   ipsocket.inspect   -> string
 *
 * Return a string describing this IPSocket object.
 */
static VALUE
ip_inspect(VALUE sock)
{
    VALUE str = rb_call_super(0, 0);
    rb_io_t *fptr = RFILE(sock)->fptr;
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    ID id;
    if (fptr && fptr->fd >= 0 &&
	getsockname(fptr->fd, &addr.addr, &len) >= 0 &&
	(id = rsock_intern_family(addr.addr.sa_family)) != 0) {
	VALUE family = rb_id2str(id);
	char hbuf[1024], pbuf[1024];
	long slen = RSTRING_LEN(str);
	const char last = (slen > 1 && RSTRING_PTR(str)[slen - 1] == '>') ?
	    (--slen, '>') : 0;
	str = rb_str_subseq(str, 0, slen);
	rb_str_cat_cstr(str, ", ");
	rb_str_append(str, family);
	if (!rb_getnameinfo(&addr.addr, len, hbuf, sizeof(hbuf),
			    pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV)) {
	    rb_str_cat_cstr(str, ", ");
	    rb_str_cat_cstr(str, hbuf);
	    rb_str_cat_cstr(str, ", ");
	    rb_str_cat_cstr(str, pbuf);
	}
	if (last) rb_str_cat(str, &last, 1);
    }
    return str;
}

/*
 * call-seq:
 *   ipsocket.addr([reverse_lookup]) => [address_family, port, hostname, numeric_address]
 *
 * Returns the local address as an array which contains
 * address_family, port, hostname and numeric_address.
 *
 * If +reverse_lookup+ is +true+ or +:hostname+,
 * hostname is obtained from numeric_address using reverse lookup.
 * Or if it is +false+, or +:numeric+,
 * hostname is the same as numeric_address.
 * Or if it is +nil+ or omitted, obeys to +ipsocket.do_not_reverse_lookup+.
 * See +Socket.getaddrinfo+ also.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.addr #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(true)  #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(false) #=> ["AF_INET", 49429, "192.168.0.128", "192.168.0.128"]
 *     p sock.addr(:hostname)  #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(:numeric)   #=> ["AF_INET", 49429, "192.168.0.128", "192.168.0.128"]
 *   }
 *
 */
static VALUE
ip_addr(int argc, VALUE *argv, VALUE sock)
{
    rb_io_t *fptr;
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    int norevlookup;

    GetOpenFile(sock, fptr);

    if (argc < 1 || !rsock_revlookup_flag(argv[0], &norevlookup))
	norevlookup = fptr->mode & FMODE_NOREVLOOKUP;
    if (getsockname(fptr->fd, &addr.addr, &len) < 0)
	rb_sys_fail("getsockname(2)");
    return rsock_ipaddr(&addr.addr, len, norevlookup);
}

/*
 * call-seq:
 *   ipsocket.peeraddr([reverse_lookup]) => [address_family, port, hostname, numeric_address]
 *
 * Returns the remote address as an array which contains
 * address_family, port, hostname and numeric_address.
 * It is defined for connection oriented socket such as TCPSocket.
 *
 * If +reverse_lookup+ is +true+ or +:hostname+,
 * hostname is obtained from numeric_address using reverse lookup.
 * Or if it is +false+, or +:numeric+,
 * hostname is the same as numeric_address.
 * Or if it is +nil+ or omitted, obeys to +ipsocket.do_not_reverse_lookup+.
 * See +Socket.getaddrinfo+ also.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.peeraddr #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(true)  #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(false) #=> ["AF_INET", 80, "221.186.184.68", "221.186.184.68"]
 *     p sock.peeraddr(:hostname) #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(:numeric)  #=> ["AF_INET", 80, "221.186.184.68", "221.186.184.68"]
 *   }
 *
 */
static VALUE
ip_peeraddr(int argc, VALUE *argv, VALUE sock)
{
    rb_io_t *fptr;
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    int norevlookup;

    GetOpenFile(sock, fptr);

    if (argc < 1 || !rsock_revlookup_flag(argv[0], &norevlookup))
	norevlookup = fptr->mode & FMODE_NOREVLOOKUP;
    if (getpeername(fptr->fd, &addr.addr, &len) < 0)
	rb_sys_fail("getpeername(2)");
    return rsock_ipaddr(&addr.addr, len, norevlookup);
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
 * ipaddr is the same as IPSocket#{peeraddr,addr}.
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
 * Lookups the IP address of _host_.
 *
 *   require 'socket'
 *
 *   IPSocket.getaddress("localhost")     #=> "127.0.0.1"
 *   IPSocket.getaddress("ip6-localhost") #=> "::1"
 *
 */
static VALUE
ip_s_getaddress(VALUE obj, VALUE host)
{
    union_sockaddr addr;
    struct rb_addrinfo *res = rsock_addrinfo(host, Qnil, AF_UNSPEC, SOCK_STREAM, 0);
    socklen_t len = res->ai->ai_addrlen;

    /* just take the first one */
    memcpy(&addr, res->ai->ai_addr, len);
    rb_freeaddrinfo(res);

    return rsock_make_ipaddr(&addr.addr, len);
}

void
rsock_init_ipsocket(void)
{
    /*
     * Document-class: IPSocket < BasicSocket
     *
     * IPSocket is the super class of TCPSocket and UDPSocket.
     */
    rb_cIPSocket = rb_define_class("IPSocket", rb_cBasicSocket);
    rb_define_method(rb_cIPSocket, "inspect", ip_inspect, 0);
    rb_define_method(rb_cIPSocket, "addr", ip_addr, -1);
    rb_define_method(rb_cIPSocket, "peeraddr", ip_peeraddr, -1);
    rb_define_method(rb_cIPSocket, "recvfrom", ip_recvfrom, -1);
    rb_define_singleton_method(rb_cIPSocket, "getaddress", ip_s_getaddress, 1);
    rb_undef_method(rb_cIPSocket, "getpeereid");

    id_numeric = rb_intern_const("numeric");
    id_hostname = rb_intern_const("hostname");
}
