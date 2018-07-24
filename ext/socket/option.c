#include "rubysocket.h"

VALUE rb_cSockOpt;

#define pack_var(v) rb_str_new((const char *)&(v), sizeof(v))

#define CAT(x,y) x##y
#define XCAT(x,y) CAT(x,y)

#if defined(__linux__) || \
    defined(__GNU__) /* GNU/Hurd */ || \
    defined(__FreeBSD__) || \
    defined(__DragonFly__) || \
    defined(__APPLE__) || \
    defined(_WIN32) || \
    defined(__CYGWIN__)
# define TYPE_IP_MULTICAST_LOOP int
# define TYPE_IP_MULTICAST_TTL int
#else
/* The original IP multicast implementation by Steve Deering
 * NetBSD
 * OpenBSD
 * SunOS
 */
# define TYPE_IP_MULTICAST_LOOP byte
# define TYPE_IP_MULTICAST_TTL byte
# define USE_INSPECT_BYTE 1
#endif

#define check_size(len, size) \
    ((len) == (size) ? \
     (void)0 : \
     rb_raise(rb_eTypeError, "size differ.  expected as "#size"=%d but %ld", \
	      (int)size, (long)(len)))

static VALUE
sockopt_pack_byte(VALUE value)
{
    char i = NUM2CHR(rb_to_int(value));
    return pack_var(i);
}

static VALUE
sockopt_pack_int(VALUE value)
{
    int i = NUM2INT(rb_to_int(value));
    return pack_var(i);
}

static VALUE
constant_to_sym(int constant, ID (*intern_const)(int))
{
    ID name = intern_const(constant);
    if (name) {
        return ID2SYM(name);
    }

    return INT2NUM(constant);
}

static VALUE
optname_to_sym(int level, int optname)
{
    switch (level) {
      case SOL_SOCKET:
        return constant_to_sym(optname, rsock_intern_so_optname);
      case IPPROTO_IP:
        return constant_to_sym(optname, rsock_intern_ip_optname);
#ifdef IPPROTO_IPV6
      case IPPROTO_IPV6:
        return constant_to_sym(optname, rsock_intern_ipv6_optname);
#endif
      case IPPROTO_TCP:
        return constant_to_sym(optname, rsock_intern_tcp_optname);
      case IPPROTO_UDP:
        return constant_to_sym(optname, rsock_intern_udp_optname);
      default:
        return INT2NUM(optname);
    }
}

/*
 * call-seq:
 *   Socket::Option.new(family, level, optname, data) => sockopt
 *
 * Returns a new Socket::Option object.
 *
 *   sockopt = Socket::Option.new(:INET, :SOCKET, :KEEPALIVE, [1].pack("i"))
 *   p sockopt #=> #<Socket::Option: INET SOCKET KEEPALIVE 1>
 *
 */
static VALUE
sockopt_initialize(VALUE self, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE data)
{
    int family = rsock_family_arg(vfamily);
    int level = rsock_level_arg(family, vlevel);
    int optname = rsock_optname_arg(family, level, voptname);
    StringValue(data);
    rb_ivar_set(self, rb_intern("family"), INT2NUM(family));
    rb_ivar_set(self, rb_intern("level"), INT2NUM(level));
    rb_ivar_set(self, rb_intern("optname"), INT2NUM(optname));
    rb_ivar_set(self, rb_intern("data"), data);
    return self;
}

VALUE
rsock_sockopt_new(int family, int level, int optname, VALUE data)
{
    NEWOBJ_OF(obj, struct RObject, rb_cSockOpt, T_OBJECT);
    StringValue(data);
    sockopt_initialize((VALUE)obj, INT2NUM(family), INT2NUM(level), INT2NUM(optname), data);
    return (VALUE)obj;
}

/*
 * call-seq:
 *   sockopt.family => integer
 *
 * returns the socket family as an integer.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).family
 *   #=> 10
 */
static VALUE
sockopt_family_m(VALUE self)
{
    return rb_attr_get(self, rb_intern("family"));
}

static int
sockopt_level(VALUE self)
{
    return NUM2INT(rb_attr_get(self, rb_intern("level")));
}

/*
 * call-seq:
 *   sockopt.level => integer
 *
 * returns the socket level as an integer.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).level
 *   #=> 41
 */
static VALUE
sockopt_level_m(VALUE self)
{
    return INT2NUM(sockopt_level(self));
}

static int
sockopt_optname(VALUE self)
{
    return NUM2INT(rb_attr_get(self, rb_intern("optname")));
}

/*
 * call-seq:
 *   sockopt.optname => integer
 *
 * returns the socket option name as an integer.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).optname
 *   #=> 2
 */
static VALUE
sockopt_optname_m(VALUE self)
{
    return INT2NUM(sockopt_optname(self));
}

/*
 * call-seq:
 *   sockopt.data => string
 *   sockopt.to_s => string
 *
 * returns the socket option data as a string.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).data
 *   #=> "\x01\x00\x00\x00"
 */
static VALUE
sockopt_data(VALUE self)
{
    VALUE v = rb_attr_get(self, rb_intern("data"));
    StringValue(v);
    return v;
}

/*
 * call-seq:
 *   Socket::Option.byte(family, level, optname, integer) => sockopt
 *
 * Creates a new Socket::Option object which contains a byte as data.
 *
 *   p Socket::Option.byte(:INET, :SOCKET, :KEEPALIVE, 1)
 *   #=> #<Socket::Option: INET SOCKET KEEPALIVE 1>
 */
static VALUE
sockopt_s_byte(VALUE klass, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE vint)
{
    int family = rsock_family_arg(vfamily);
    int level = rsock_level_arg(family, vlevel);
    int optname = rsock_optname_arg(family, level, voptname);
    return rsock_sockopt_new(family, level, optname, sockopt_pack_byte(vint));
}

/*
 * call-seq:
 *   sockopt.byte => integer
 *
 * Returns the data in _sockopt_ as an byte.
 *
 *   sockopt = Socket::Option.byte(:INET, :SOCKET, :KEEPALIVE, 1)
 *   p sockopt.byte => 1
 */
static VALUE
sockopt_byte(VALUE self)
{
    VALUE data = sockopt_data(self);
    StringValue(data);
    check_size(RSTRING_LEN(data), sizeof(char));
    return CHR2FIX(*RSTRING_PTR(data));
}

/*
 * call-seq:
 *   Socket::Option.int(family, level, optname, integer) => sockopt
 *
 * Creates a new Socket::Option object which contains an int as data.
 *
 * The size and endian is dependent on the platform.
 *
 *   p Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
 *   #=> #<Socket::Option: INET SOCKET KEEPALIVE 1>
 */
static VALUE
sockopt_s_int(VALUE klass, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE vint)
{
    int family = rsock_family_arg(vfamily);
    int level = rsock_level_arg(family, vlevel);
    int optname = rsock_optname_arg(family, level, voptname);
    return rsock_sockopt_new(family, level, optname, sockopt_pack_int(vint));
}

/*
 * call-seq:
 *   sockopt.int => integer
 *
 * Returns the data in _sockopt_ as an int.
 *
 * The size and endian is dependent on the platform.
 *
 *   sockopt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
 *   p sockopt.int => 1
 */
static VALUE
sockopt_int(VALUE self)
{
    int i;
    VALUE data = sockopt_data(self);
    StringValue(data);
    check_size(RSTRING_LEN(data), sizeof(int));
    memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
    return INT2NUM(i);
}

/*
 * call-seq:
 *   Socket::Option.bool(family, level, optname, bool) => sockopt
 *
 * Creates a new Socket::Option object which contains boolean as data.
 * Actually 0 or 1 as int is used.
 *
 *   require 'socket'
 *
 *   p Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
 *   #=> #<Socket::Option: INET SOCKET KEEPALIVE 1>
 *
 *   p Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, false)
 *   #=> #<Socket::Option: AF_INET SOCKET KEEPALIVE 0>
 *
 */
static VALUE
sockopt_s_bool(VALUE klass, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE vbool)
{
    int family = rsock_family_arg(vfamily);
    int level = rsock_level_arg(family, vlevel);
    int optname = rsock_optname_arg(family, level, voptname);
    int i = RTEST(vbool) ? 1 : 0;
    return rsock_sockopt_new(family, level, optname, pack_var(i));
}

/*
 * call-seq:
 *   sockopt.bool => true or false
 *
 * Returns the data in _sockopt_ as an boolean value.
 *
 *   sockopt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
 *   p sockopt.bool => true
 */
static VALUE
sockopt_bool(VALUE self)
{
    int i;
    long len;
    VALUE data = sockopt_data(self);
    StringValue(data);
    len = RSTRING_LEN(data);
    if (len == 1) {
	return *RSTRING_PTR(data) == 0 ? Qfalse : Qtrue;
    }
    check_size(len, sizeof(int));
    memcpy((char*)&i, RSTRING_PTR(data), len);
    return i == 0 ? Qfalse : Qtrue;
}

/*
 * call-seq:
 *   Socket::Option.linger(onoff, secs) => sockopt
 *
 * Creates a new Socket::Option object for SOL_SOCKET/SO_LINGER.
 *
 * _onoff_ should be an integer or a boolean.
 *
 * _secs_ should be the number of seconds.
 *
 *   p Socket::Option.linger(true, 10)
 *   #=> #<Socket::Option: UNSPEC SOCKET LINGER on 10sec>
 *
 */
static VALUE
sockopt_s_linger(VALUE klass, VALUE vonoff, VALUE vsecs)
{
    VALUE tmp;
    struct linger l;
    memset(&l, 0, sizeof(l));
    if (!NIL_P(tmp = rb_check_to_integer(vonoff, "to_int")))
        l.l_onoff = NUM2INT(tmp);
    else
        l.l_onoff = RTEST(vonoff) ? 1 : 0;
    l.l_linger = NUM2INT(vsecs);
    return rsock_sockopt_new(AF_UNSPEC, SOL_SOCKET, SO_LINGER, pack_var(l));
}

/*
 * call-seq:
 *   sockopt.linger => [bool, seconds]
 *
 * Returns the linger data in _sockopt_ as a pair of boolean and integer.
 *
 *   sockopt = Socket::Option.linger(true, 10)
 *   p sockopt.linger => [true, 10]
 */
static VALUE
sockopt_linger(VALUE self)
{
    int level = sockopt_level(self);
    int optname = sockopt_optname(self);
    VALUE data = sockopt_data(self);
    struct linger l;
    VALUE vonoff, vsecs;

    if (level != SOL_SOCKET || optname != SO_LINGER)
        rb_raise(rb_eTypeError, "linger socket option expected");
    check_size(RSTRING_LEN(data), sizeof(struct linger));
    memcpy((char*)&l, RSTRING_PTR(data), sizeof(struct linger));
    switch (l.l_onoff) {
      case 0: vonoff = Qfalse; break;
      case 1: vonoff = Qtrue; break;
      default: vonoff = INT2NUM(l.l_onoff); break;
    }
    vsecs = INT2NUM(l.l_linger);
    return rb_assoc_new(vonoff, vsecs);
}

/*
 * call-seq:
 *   Socket::Option.ipv4_multicast_loop(integer) => sockopt
 *
 * Creates a new Socket::Option object for IP_MULTICAST_LOOP.
 *
 * The size is dependent on the platform.
 *
 *   sockopt = Socket::Option.int(:INET, :IPPROTO_IP, :IP_MULTICAST_LOOP, 1)
 *   p sockopt.int => 1
 *
 *   p Socket::Option.ipv4_multicast_loop(10)
 *   #=> #<Socket::Option: INET IP MULTICAST_LOOP 10>
 *
 */
static VALUE
sockopt_s_ipv4_multicast_loop(VALUE klass, VALUE value)
{

#if defined(IPPROTO_IP) && defined(IP_MULTICAST_LOOP)
    VALUE o = XCAT(sockopt_pack_,TYPE_IP_MULTICAST_LOOP)(value);
    return rsock_sockopt_new(AF_INET, IPPROTO_IP, IP_MULTICAST_LOOP, o);
#else
# error IPPROTO_IP or IP_MULTICAST_LOOP is not implemented
#endif
}

/*
 * call-seq:
 *   sockopt.ipv4_multicast_loop => integer
 *
 * Returns the ipv4_multicast_loop data in _sockopt_ as an integer.
 *
 *   sockopt = Socket::Option.ipv4_multicast_loop(10)
 *   p sockopt.ipv4_multicast_loop => 10
 */
static VALUE
sockopt_ipv4_multicast_loop(VALUE self)
{
    int family = NUM2INT(sockopt_family_m(self));
    int level = sockopt_level(self);
    int optname = sockopt_optname(self);

#if defined(IPPROTO_IP) && defined(IP_MULTICAST_LOOP)
    if (family == AF_INET && level == IPPROTO_IP && optname == IP_MULTICAST_LOOP) {
	return XCAT(sockopt_,TYPE_IP_MULTICAST_LOOP)(self);
    }
#endif
    rb_raise(rb_eTypeError, "ipv4_multicast_loop socket option expected");
    UNREACHABLE_RETURN(Qnil);
}

#define inspect_ipv4_multicast_loop(a,b,c,d) \
  XCAT(inspect_,TYPE_IP_MULTICAST_LOOP)(a,b,c,d)

/*
 * call-seq:
 *   Socket::Option.ipv4_multicast_ttl(integer) => sockopt
 *
 * Creates a new Socket::Option object for IP_MULTICAST_TTL.
 *
 * The size is dependent on the platform.
 *
 *   p Socket::Option.ipv4_multicast_ttl(10)
 *   #=> #<Socket::Option: INET IP MULTICAST_TTL 10>
 *
 */
static VALUE
sockopt_s_ipv4_multicast_ttl(VALUE klass, VALUE value)
{
#if defined(IPPROTO_IP) && defined(IP_MULTICAST_TTL)
    VALUE o = XCAT(sockopt_pack_,TYPE_IP_MULTICAST_TTL)(value);
    return rsock_sockopt_new(AF_INET, IPPROTO_IP, IP_MULTICAST_TTL, o);
#else
# error IPPROTO_IP or IP_MULTICAST_TTL is not implemented
#endif
}

/*
 * call-seq:
 *   sockopt.ipv4_multicast_ttl => integer
 *
 * Returns the ipv4_multicast_ttl data in _sockopt_ as an integer.
 *
 *   sockopt = Socket::Option.ipv4_multicast_ttl(10)
 *   p sockopt.ipv4_multicast_ttl => 10
 */
static VALUE
sockopt_ipv4_multicast_ttl(VALUE self)
{
    int family = NUM2INT(sockopt_family_m(self));
    int level = sockopt_level(self);
    int optname = sockopt_optname(self);

#if defined(IPPROTO_IP) && defined(IP_MULTICAST_TTL)
    if (family == AF_INET && level == IPPROTO_IP && optname == IP_MULTICAST_TTL) {
	return XCAT(sockopt_,TYPE_IP_MULTICAST_TTL)(self);
    }
#endif
    rb_raise(rb_eTypeError, "ipv4_multicast_ttl socket option expected");
    UNREACHABLE_RETURN(Qnil);
}

#define inspect_ipv4_multicast_ttl(a,b,c,d) \
    XCAT(inspect_,TYPE_IP_MULTICAST_TTL)(a,b,c,d)

static int
inspect_int(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        int i;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
        rb_str_catf(ret, " %d", i);
        return 1;
    }
    else {
        return 0;
    }
}

#ifdef USE_INSPECT_BYTE
static int
inspect_byte(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(unsigned char)) {
        rb_str_catf(ret, " %d", (unsigned char)*RSTRING_PTR(data));
        return 1;
    }
    else {
        return 0;
    }
}
#endif

static int
inspect_errno(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        int i;
        char *err;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
        err = strerror(i);
        rb_str_catf(ret, " %s (%d)", err, i);
        return 1;
    }
    else {
        return 0;
    }
}

#if defined(IPV6_MULTICAST_LOOP)
static int
inspect_uint(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        unsigned int i;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(unsigned int));
        rb_str_catf(ret, " %u", i);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(SOL_SOCKET) && defined(SO_LINGER) /* POSIX */
static int
inspect_linger(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct linger)) {
        struct linger s;
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        switch (s.l_onoff) {
          case 0: rb_str_cat2(ret, " off"); break;
          case 1: rb_str_cat2(ret, " on"); break;
          default: rb_str_catf(ret, " on(%d)", s.l_onoff); break;
        }
        rb_str_catf(ret, " %dsec", s.l_linger);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(SOL_SOCKET) && defined(SO_TYPE) /* POSIX */
static int
inspect_socktype(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        int i;
        ID id;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
        id = rsock_intern_socktype(i);
        if (id)
            rb_str_catf(ret, " %s", rb_id2name(id));
        else
            rb_str_catf(ret, " %d", i);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

static int
inspect_timeval_as_interval(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct timeval)) {
        struct timeval s;
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        rb_str_catf(ret, " %ld.%06ldsec", (long)s.tv_sec, (long)s.tv_usec);
        return 1;
    }
    else {
        return 0;
    }
}

/*
 * socket option for IPv4 multicast is bit confusing.
 *
 * IP Multicast is implemented by Steve Deering at first:
 *   IP Multicast Extensions for 4.3BSD UNIX and related systems
 *   (MULTICAST 1.2 Release)
 *   http://www.kohala.com/start/mcast.api.txt
 *
 * There are 2 socket options which takes a u_char (unsigned char).
 *
 *   IP_MULTICAST_TTL
 *   IP_MULTICAST_LOOP
 *
 * However Linux and FreeBSD setsockname accepts int argument
 * as well as u_char.
 * Their getsockname returns int.
 *
 * There are 3 socket options which takes a struct.
 *
 *   IP_MULTICAST_IF: struct in_addr
 *   IP_ADD_MEMBERSHIP: struct ip_mreq
 *   IP_DROP_MEMBERSHIP: struct ip_mreq
 *
 * But they uses an IP address to specify an interface.
 * This means the API cannot specify an unnumbered interface.
 *
 * Linux 2.4 introduces struct ip_mreqn to fix this problem.
 * struct ip_mreqn has imr_ifindex field to specify interface index.
 *
 *   IP_MULTICAST_IF: struct ip_mreqn
 *   IP_ADD_MEMBERSHIP: struct ip_mreqn
 *   IP_DROP_MEMBERSHIP: struct ip_mreqn
 *
 * FreeBSD 7 obtained struct ip_mreqn for IP_MULTICAST_IF.
 * http://www.FreeBSD.org/cgi/cvsweb.cgi/src/sys/netinet/in.h.diff?r1=1.99;r2=1.100
 *
 * Another hackish workaround is "RFC 1724 hack".
 * RFC 1724 section 3.3 suggests unnumbered interfaces
 * specified by pseudo address 0.0.0.0/8.
 * NetBSD 4 and FreeBSD 5 documented it.
 * http://cvsweb.netbsd.org/cgi-bin/cvsweb.cgi/src/share/man/man4/ip.4.diff?r1=1.16&r2=1.17
 * http://www.FreeBSD.org/cgi/cvsweb.cgi/src/share/man/man4/ip.4.diff?r1=1.37;r2=1.38
 * FreeBSD 7.0 removed it.
 * http://www.FreeBSD.org/cgi/cvsweb.cgi/src/share/man/man4/ip.4.diff?r1=1.49;r2=1.50
 *
 * RFC 1724 hack is not supported by Socket::Option#inspect because
 * it is not distinguishable by the size.
 */

#if !defined HAVE_INET_NTOP && ! defined _WIN32
const char *
inet_ntop(int af, const void *addr, char *numaddr, size_t numaddr_len)
{
#ifdef HAVE_INET_NTOA
    struct in_addr in;
    memcpy(&in.s_addr, addr, sizeof(in.s_addr));
    snprintf(numaddr, numaddr_len, "%s", inet_ntoa(in));
#else
    unsigned long x = ntohl(*(unsigned long*)addr);
    snprintf(numaddr, numaddr_len, "%d.%d.%d.%d",
	     (int) (x>>24) & 0xff, (int) (x>>16) & 0xff,
	     (int) (x>> 8) & 0xff, (int) (x>> 0) & 0xff);
#endif
    return numaddr;
}
#endif

/* Although the buffer size needed depends on the prefixes, "%u" may generate "4294967295".  */
static int
rb_if_indextoname(const char *succ_prefix, const char *fail_prefix, unsigned int ifindex, char *buf, size_t len)
{
#if defined(HAVE_IF_INDEXTONAME)
    char ifbuf[IFNAMSIZ];
    if (if_indextoname(ifindex, ifbuf) == NULL)
        return snprintf(buf, len, "%s%u", fail_prefix, ifindex);
    else
        return snprintf(buf, len, "%s%s", succ_prefix, ifbuf);
#else
#   ifndef IFNAMSIZ
#       define IFNAMSIZ (sizeof(unsigned int)*3+1)
#   endif
    return snprintf(buf, len, "%s%u", fail_prefix, ifindex);
#endif
}

#if defined(IPPROTO_IP) && defined(HAVE_TYPE_STRUCT_IP_MREQ) /* 4.4BSD, GNU/Linux */
static int
inspect_ipv4_mreq(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ip_mreq)) {
        struct ip_mreq s;
        char addrbuf[INET_ADDRSTRLEN];
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        if (inet_ntop(AF_INET, &s.imr_multiaddr, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_cat2(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        if (inet_ntop(AF_INET, &s.imr_interface, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_catf(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(IPPROTO_IP) && defined(HAVE_TYPE_STRUCT_IP_MREQN) /* GNU/Linux, FreeBSD 7 */
static int
inspect_ipv4_mreqn(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ip_mreqn)) {
        struct ip_mreqn s;
        char addrbuf[INET_ADDRSTRLEN], ifbuf[32+IFNAMSIZ];
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        if (inet_ntop(AF_INET, &s.imr_multiaddr, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_cat2(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        if (inet_ntop(AF_INET, &s.imr_address, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_catf(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        rb_if_indextoname(" ", " ifindex:", s.imr_ifindex, ifbuf, sizeof(ifbuf));
        rb_str_cat2(ret, ifbuf);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(IPPROTO_IP) && defined(HAVE_TYPE_STRUCT_IP_MREQ) /* 4.4BSD, GNU/Linux */
static int
inspect_ipv4_add_drop_membership(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ip_mreq))
        return inspect_ipv4_mreq(level, optname, data, ret);
# if defined(HAVE_TYPE_STRUCT_IP_MREQN)
    else if (RSTRING_LEN(data) == sizeof(struct ip_mreqn))
        return inspect_ipv4_mreqn(level, optname, data, ret);
# endif
    else
        return 0;
}
#endif

#if defined(IPPROTO_IP) && defined(IP_MULTICAST_IF) && defined(HAVE_TYPE_STRUCT_IP_MREQN) /* 4.4BSD, GNU/Linux */
static int
inspect_ipv4_multicast_if(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct in_addr)) {
        struct in_addr s;
        char addrbuf[INET_ADDRSTRLEN];
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        if (inet_ntop(AF_INET, &s, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_cat2(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        return 1;
    }
    else if (RSTRING_LEN(data) == sizeof(struct ip_mreqn)) {
        return inspect_ipv4_mreqn(level, optname, data, ret);
    }
    else {
        return 0;
    }
}
#endif

#if defined(IPV6_MULTICAST_IF) /* POSIX, RFC 3493 */
static int
inspect_ipv6_multicast_if(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        char ifbuf[32+IFNAMSIZ];
        unsigned int ifindex;
        memcpy((char*)&ifindex, RSTRING_PTR(data), sizeof(unsigned int));
        rb_if_indextoname(" ", " ", ifindex, ifbuf, sizeof(ifbuf));
        rb_str_cat2(ret, ifbuf);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(IPPROTO_IPV6) && defined(HAVE_TYPE_STRUCT_IPV6_MREQ) /* POSIX, RFC 3493 */
static int
inspect_ipv6_mreq(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ipv6_mreq)) {
        struct ipv6_mreq s;
        char addrbuf[INET6_ADDRSTRLEN], ifbuf[32+IFNAMSIZ];
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        if (inet_ntop(AF_INET6, &s.ipv6mr_multiaddr, addrbuf, (socklen_t)sizeof(addrbuf)) == NULL)
            rb_str_cat2(ret, " invalid-address");
        else
            rb_str_catf(ret, " %s", addrbuf);
        rb_if_indextoname(" ", " interface:", s.ipv6mr_interface, ifbuf, sizeof(ifbuf));
        rb_str_cat2(ret, ifbuf);
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(IPPROTO_TCP) && defined(TCP_INFO) && defined(HAVE_TYPE_STRUCT_TCP_INFO)

#ifdef __FreeBSD__
# ifndef HAVE_CONST_TCP_ESTABLISHED
#  define TCP_ESTABLISHED TCPS_ESTABLISHED
# endif
# ifndef HAVE_CONST_TCP_SYN_SENT
#  define TCP_SYN_SENT TCPS_SYN_SENT
# endif
# ifndef HAVE_CONST_TCP_SYN_RECV
#  define TCP_SYN_RECV TCPS_SYN_RECEIVED
# endif
# ifndef HAVE_CONST_TCP_FIN_WAIT1
#  define TCP_FIN_WAIT1 TCPS_FIN_WAIT_1
# endif
# ifndef HAVE_CONST_TCP_FIN_WAIT2
#  define TCP_FIN_WAIT2 TCPS_FIN_WAIT_2
# endif
# ifndef HAVE_CONST_TCP_TIME_WAIT
#  define TCP_TIME_WAIT TCPS_TIME_WAIT
# endif
# ifndef HAVE_CONST_TCP_CLOSE
#  define TCP_CLOSE TCPS_CLOSED
# endif
# ifndef HAVE_CONST_TCP_CLOSE_WAIT
#  define TCP_CLOSE_WAIT TCPS_CLOSE_WAIT
# endif
# ifndef HAVE_CONST_TCP_LAST_ACK
#  define TCP_LAST_ACK TCPS_LAST_ACK
# endif
# ifndef HAVE_CONST_TCP_LISTEN
#  define TCP_LISTEN TCPS_LISTEN
# endif
# ifndef HAVE_CONST_TCP_CLOSING
#  define TCP_CLOSING TCPS_CLOSING
# endif
#endif

#if defined(HAVE_CONST_TCP_ESTABLISHED) && !defined(TCP_ESTABLISHED)
# define TCP_ESTABLISHED TCP_ESTABLISHED
#endif
#if defined(HAVE_CONST_TCP_SYN_SENT) && !defined(TCP_SYN_SENT)
# define TCP_SYN_SENT TCP_SYN_SENT
#endif
#if defined(HAVE_CONST_TCP_SYN_RECV) && !defined(TCP_SYN_RECV)
# define TCP_SYN_RECV TCP_SYN_RECV
#endif
#if defined(HAVE_CONST_TCP_FIN_WAIT1) && !defined(TCP_FIN_WAIT1)
# define TCP_FIN_WAIT1 TCP_FIN_WAIT1
#endif
#if defined(HAVE_CONST_TCP_FIN_WAIT2) && !defined(TCP_FIN_WAIT2)
# define TCP_FIN_WAIT2 TCP_FIN_WAIT2
#endif
#if defined(HAVE_CONST_TCP_TIME_WAIT) && !defined(TCP_TIME_WAIT)
# define TCP_TIME_WAIT TCP_TIME_WAIT
#endif
#if defined(HAVE_CONST_TCP_CLOSE) && !defined(TCP_CLOSE)
# define TCP_CLOSE TCP_CLOSE
#endif
#if defined(HAVE_CONST_TCP_CLOSE_WAIT) && !defined(TCP_CLOSE_WAIT)
# define TCP_CLOSE_WAIT TCP_CLOSE_WAIT
#endif
#if defined(HAVE_CONST_TCP_LAST_ACK) && !defined(TCP_LAST_ACK)
# define TCP_LAST_ACK TCP_LAST_ACK
#endif
#if defined(HAVE_CONST_TCP_LISTEN) && !defined(TCP_LISTEN)
# define TCP_LISTEN TCP_LISTEN
#endif
#if defined(HAVE_CONST_TCP_CLOSING) && !defined(TCP_CLOSING)
# define TCP_CLOSING TCP_CLOSING
#endif

static void
inspect_tcpi_options(VALUE ret, uint8_t options)
{
    int sep = '=';

    rb_str_cat2(ret, " options");
#define INSPECT_TCPI_OPTION(optval, name) \
    if (options & (optval)) { \
        options &= ~(uint8_t)(optval); \
        rb_str_catf(ret, "%c%s", sep, name); \
        sep = ','; \
    }
#ifdef TCPI_OPT_TIMESTAMPS /* GNU/Linux, FreeBSD */
    INSPECT_TCPI_OPTION(TCPI_OPT_TIMESTAMPS, "TIMESTAMPS");
#endif
#ifdef TCPI_OPT_SACK /* GNU/Linux, FreeBSD */
    INSPECT_TCPI_OPTION(TCPI_OPT_SACK, "SACK");
#endif
#ifdef TCPI_OPT_WSCALE /* GNU/Linux, FreeBSD */
    INSPECT_TCPI_OPTION(TCPI_OPT_WSCALE, "WSCALE");
#endif
#ifdef TCPI_OPT_ECN /* GNU/Linux, FreeBSD */
    INSPECT_TCPI_OPTION(TCPI_OPT_ECN, "ECN");
#endif
#ifdef TCPI_OPT_ECN_SEEN /* GNU/Linux */
    INSPECT_TCPI_OPTION(TCPI_OPT_ECN_SEEN, "ECN_SEEN");
#endif
#ifdef TCPI_OPT_SYN_DATA /* GNU/Linux */
    INSPECT_TCPI_OPTION(TCPI_OPT_SYN_DATA, "SYN_DATA");
#endif
#ifdef TCPI_OPT_TOE /* FreeBSD */
    INSPECT_TCPI_OPTION(TCPI_OPT_TOE, "TOE");
#endif
#undef INSPECT_TCPI_OPTION

    if (options || sep == '=') {
        rb_str_catf(ret, "%c%u", sep, options);
    }
}

static void
inspect_tcpi_usec(VALUE ret, const char *prefix, uint32_t t)
{
    rb_str_catf(ret, "%s%u.%06us", prefix, t / 1000000, t % 1000000);
}

#if !defined __FreeBSD__ && ( \
    defined HAVE_STRUCT_TCP_INFO_TCPI_LAST_DATA_SENT || \
    defined HAVE_STRUCT_TCP_INFO_TCPI_LAST_DATA_RECV || \
    defined HAVE_STRUCT_TCP_INFO_TCPI_LAST_ACK_SENT  || \
    defined HAVE_STRUCT_TCP_INFO_TCPI_LAST_ACK_RECV  || \
    0)
static void
inspect_tcpi_msec(VALUE ret, const char *prefix, uint32_t t)
{
    rb_str_catf(ret, "%s%u.%03us", prefix, t / 1000, t % 1000);
}
#endif

#ifdef __FreeBSD__
# define inspect_tcpi_rto(ret, t) inspect_tcpi_usec(ret, " rto=", t)
# define inspect_tcpi_last_data_recv(ret, t) inspect_tcpi_usec(ret, " last_data_recv=", t)
# define inspect_tcpi_rtt(ret, t) inspect_tcpi_usec(ret, " rtt=", t)
# define inspect_tcpi_rttvar(ret, t) inspect_tcpi_usec(ret, " rttvar=", t)
#else
# define inspect_tcpi_rto(ret, t) inspect_tcpi_usec(ret, " rto=", t)
# define inspect_tcpi_ato(ret, t) inspect_tcpi_usec(ret, " ato=", t)
# define inspect_tcpi_last_data_sent(ret, t) inspect_tcpi_msec(ret, " last_data_sent=", t)
# define inspect_tcpi_last_data_recv(ret, t) inspect_tcpi_msec(ret, " last_data_recv=", t)
# define inspect_tcpi_last_ack_sent(ret, t) inspect_tcpi_msec(ret, " last_ack_sent=", t)
# define inspect_tcpi_last_ack_recv(ret, t) inspect_tcpi_msec(ret, " last_ack_recv=", t)
# define inspect_tcpi_rtt(ret, t) inspect_tcpi_usec(ret, " rtt=", t)
# define inspect_tcpi_rttvar(ret, t) inspect_tcpi_usec(ret, " rttvar=", t)
# define inspect_tcpi_rcv_rtt(ret, t) inspect_tcpi_usec(ret, " rcv_rtt=", t)
#endif

static int
inspect_tcp_info(int level, int optname, VALUE data, VALUE ret)
{
    size_t actual_size = RSTRING_LEN(data);
    if (sizeof(struct tcp_info) <= actual_size) {
        struct tcp_info s;
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_STATE
        switch (s.tcpi_state) {
# ifdef TCP_ESTABLISHED
          case TCP_ESTABLISHED: rb_str_cat_cstr(ret, " state=ESTABLISHED"); break;
# endif
# ifdef TCP_SYN_SENT
          case TCP_SYN_SENT: rb_str_cat_cstr(ret, " state=SYN_SENT"); break;
# endif
# ifdef TCP_SYN_RECV
          case TCP_SYN_RECV: rb_str_cat_cstr(ret, " state=SYN_RECV"); break;
# endif
# ifdef TCP_FIN_WAIT1
          case TCP_FIN_WAIT1: rb_str_cat_cstr(ret, " state=FIN_WAIT1"); break;
# endif
# ifdef TCP_FIN_WAIT2
          case TCP_FIN_WAIT2: rb_str_cat_cstr(ret, " state=FIN_WAIT2"); break;
# endif
# ifdef TCP_TIME_WAIT
          case TCP_TIME_WAIT: rb_str_cat_cstr(ret, " state=TIME_WAIT"); break;
# endif
# ifdef TCP_CLOSE
          case TCP_CLOSE: rb_str_cat_cstr(ret, " state=CLOSED"); break; /* RFC 793 uses "CLOSED", not "CLOSE" */
# endif
# ifdef TCP_CLOSE_WAIT
          case TCP_CLOSE_WAIT: rb_str_cat_cstr(ret, " state=CLOSE_WAIT"); break;
# endif
# ifdef TCP_LAST_ACK
          case TCP_LAST_ACK: rb_str_cat_cstr(ret, " state=LAST_ACK"); break;
# endif
# ifdef TCP_LISTEN
          case TCP_LISTEN: rb_str_cat_cstr(ret, " state=LISTEN"); break;
# endif
# ifdef TCP_CLOSING
          case TCP_CLOSING: rb_str_cat_cstr(ret, " state=CLOSING"); break;
# endif
          default: rb_str_catf(ret, " state=%u", s.tcpi_state); break;
        }
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_CA_STATE
        switch (s.tcpi_ca_state) {
          case TCP_CA_Open: rb_str_cat_cstr(ret, " ca_state=Open"); break;
          case TCP_CA_Disorder: rb_str_cat_cstr(ret, " ca_state=Disorder"); break;
          case TCP_CA_CWR: rb_str_cat_cstr(ret, " ca_state=CWR"); break;
          case TCP_CA_Recovery: rb_str_cat_cstr(ret, " ca_state=Recovery"); break;
          case TCP_CA_Loss: rb_str_cat_cstr(ret, " ca_state=Loss"); break;
          default: rb_str_catf(ret, " ca_state=%u", s.tcpi_ca_state); break;
        }
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RETRANSMITS
        rb_str_catf(ret, " retransmits=%u", s.tcpi_retransmits);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_PROBES
        rb_str_catf(ret, " probes=%u", s.tcpi_probes);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_BACKOFF
        rb_str_catf(ret, " backoff=%u", s.tcpi_backoff);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_OPTIONS
        inspect_tcpi_options(ret, s.tcpi_options);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_WSCALE
        rb_str_catf(ret, " snd_wscale=%u", s.tcpi_snd_wscale);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_WSCALE
        rb_str_catf(ret, " rcv_wscale=%u", s.tcpi_rcv_wscale);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RTO
        inspect_tcpi_rto(ret, s.tcpi_rto);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_ATO
        inspect_tcpi_ato(ret, s.tcpi_ato);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_MSS
        rb_str_catf(ret, " snd_mss=%u", s.tcpi_snd_mss);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_MSS
        rb_str_catf(ret, " rcv_mss=%u", s.tcpi_rcv_mss);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_UNACKED
        rb_str_catf(ret, " unacked=%u", s.tcpi_unacked);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SACKED
        rb_str_catf(ret, " sacked=%u", s.tcpi_sacked);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_LOST
        rb_str_catf(ret, " lost=%u", s.tcpi_lost);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RETRANS
        rb_str_catf(ret, " retrans=%u", s.tcpi_retrans);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_FACKETS
        rb_str_catf(ret, " fackets=%u", s.tcpi_fackets);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_LAST_DATA_SENT
	inspect_tcpi_last_data_sent(ret, s.tcpi_last_data_sent);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_LAST_ACK_SENT
	inspect_tcpi_last_ack_sent(ret, s.tcpi_last_ack_sent);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_LAST_DATA_RECV
	inspect_tcpi_last_data_recv(ret, s.tcpi_last_data_recv);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_LAST_ACK_RECV
	inspect_tcpi_last_ack_recv(ret, s.tcpi_last_ack_recv);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_PMTU
        rb_str_catf(ret, " pmtu=%u", s.tcpi_pmtu);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_SSTHRESH
        rb_str_catf(ret, " rcv_ssthresh=%u", s.tcpi_rcv_ssthresh);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RTT
	inspect_tcpi_rtt(ret, s.tcpi_rtt);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RTTVAR
	inspect_tcpi_rttvar(ret, s.tcpi_rttvar);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_SSTHRESH
        rb_str_catf(ret, " snd_ssthresh=%u", s.tcpi_snd_ssthresh);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_CWND
        rb_str_catf(ret, " snd_cwnd=%u", s.tcpi_snd_cwnd);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_ADVMSS
        rb_str_catf(ret, " advmss=%u", s.tcpi_advmss);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_REORDERING
        rb_str_catf(ret, " reordering=%u", s.tcpi_reordering);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_RTT
        inspect_tcpi_rcv_rtt(ret, s.tcpi_rcv_rtt);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_SPACE
        rb_str_catf(ret, " rcv_space=%u", s.tcpi_rcv_space);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_TOTAL_RETRANS
        rb_str_catf(ret, " total_retrans=%u", s.tcpi_total_retrans);
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_WND
        rb_str_catf(ret, " snd_wnd=%u", s.tcpi_snd_wnd); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_BWND
        rb_str_catf(ret, " snd_bwnd=%u", s.tcpi_snd_bwnd); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_NXT
        rb_str_catf(ret, " snd_nxt=%u", s.tcpi_snd_nxt); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_NXT
        rb_str_catf(ret, " rcv_nxt=%u", s.tcpi_rcv_nxt); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_TOE_TID
        rb_str_catf(ret, " toe_tid=%u", s.tcpi_toe_tid); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_REXMITPACK
        rb_str_catf(ret, " snd_rexmitpack=%u", s.tcpi_snd_rexmitpack); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_RCV_OOOPACK
        rb_str_catf(ret, " rcv_ooopack=%u", s.tcpi_rcv_ooopack); /* FreeBSD */
#endif
#ifdef HAVE_STRUCT_TCP_INFO_TCPI_SND_ZEROWIN
        rb_str_catf(ret, " snd_zerowin=%u", s.tcpi_snd_zerowin); /* FreeBSD */
#endif
        if (sizeof(struct tcp_info) < actual_size)
            rb_str_catf(ret, " (%u bytes too long)", (unsigned)(actual_size - sizeof(struct tcp_info)));
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(SOL_SOCKET) && defined(SO_PEERCRED) /* GNU/Linux, OpenBSD */
#if defined(__OpenBSD__)
#define RUBY_SOCK_PEERCRED struct sockpeercred
#else
#define RUBY_SOCK_PEERCRED struct ucred
#endif
static int
inspect_peercred(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(RUBY_SOCK_PEERCRED)) {
        RUBY_SOCK_PEERCRED cred;
        memcpy(&cred, RSTRING_PTR(data), sizeof(RUBY_SOCK_PEERCRED));
        rb_str_catf(ret, " pid=%u euid=%u egid=%u",
		    (unsigned)cred.pid, (unsigned)cred.uid, (unsigned)cred.gid);
        rb_str_cat2(ret, " (ucred)");
        return 1;
    }
    else {
        return 0;
    }
}
#endif

#if defined(LOCAL_PEERCRED) /* FreeBSD, MacOS X */
static int
inspect_local_peercred(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct xucred)) {
        struct xucred cred;
        memcpy(&cred, RSTRING_PTR(data), sizeof(struct xucred));
        if (cred.cr_version != XUCRED_VERSION)
            return 0;
        rb_str_catf(ret, " version=%u", cred.cr_version);
        rb_str_catf(ret, " euid=%u", cred.cr_uid);
	if (cred.cr_ngroups) {
	    int i;
	    const char *sep = " groups=";
	    for (i = 0; i < cred.cr_ngroups; i++) {
		rb_str_catf(ret, "%s%u", sep, cred.cr_groups[i]);
		sep = ",";
	    }
	}
        rb_str_cat2(ret, " (xucred)");
        return 1;
    }
    else {
        return 0;
    }
}
#endif


/*
 * call-seq:
 *   sockopt.inspect => string
 *
 * Returns a string which shows sockopt in human-readable form.
 *
 *   p Socket::Option.new(:INET, :SOCKET, :KEEPALIVE, [1].pack("i")).inspect
 *   #=> "#<Socket::Option: INET SOCKET KEEPALIVE 1>"
 *
 */
static VALUE
sockopt_inspect(VALUE self)
{
    int family = NUM2INT(sockopt_family_m(self));
    int level = NUM2INT(sockopt_level_m(self));
    int optname = NUM2INT(sockopt_optname_m(self));
    VALUE data = sockopt_data(self);
    VALUE v, ret;
    ID family_id, level_id, optname_id;
    int inspected;

    StringValue(data);

    ret = rb_sprintf("#<%s:", rb_obj_classname(self));

    family_id = rsock_intern_family_noprefix(family);
    if (family_id)
	rb_str_catf(ret, " %s", rb_id2name(family_id));
    else
        rb_str_catf(ret, " family:%d", family);

    if (level == SOL_SOCKET) {
        rb_str_cat2(ret, " SOCKET");

	optname_id = rsock_intern_so_optname(optname);
	if (optname_id)
	    rb_str_catf(ret, " %s", rb_id2name(optname_id));
	else
	    rb_str_catf(ret, " optname:%d", optname);
    }
#ifdef HAVE_SYS_UN_H
    else if (family == AF_UNIX) {
	rb_str_catf(ret, " level:%d", level);

	optname_id = rsock_intern_local_optname(optname);
	if (optname_id)
	    rb_str_catf(ret, " %s", rb_id2name(optname_id));
	else
	    rb_str_catf(ret, " optname:%d", optname);
    }
#endif
    else if (IS_IP_FAMILY(family)) {
	level_id = rsock_intern_iplevel(level);
	if (level_id)
	    rb_str_catf(ret, " %s", rb_id2name(level_id));
	else
	    rb_str_catf(ret, " level:%d", level);

	v = optname_to_sym(level, optname);
	if (SYMBOL_P(v))
	    rb_str_catf(ret, " %"PRIsVALUE, rb_sym2str(v));
	else
	    rb_str_catf(ret, " optname:%d", optname);
    }
    else {
        rb_str_catf(ret, " level:%d", level);
        rb_str_catf(ret, " optname:%d", optname);
    }

    inspected = 0;

    if (level == SOL_SOCKET)
        family = AF_UNSPEC;
    switch (family) {
      case AF_UNSPEC:
        switch (level) {
          case SOL_SOCKET:
            switch (optname) {
#            if defined(SO_DEBUG) /* POSIX */
              case SO_DEBUG: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_ERROR) /* POSIX */
              case SO_ERROR: inspected = inspect_errno(level, optname, data, ret); break;
#            endif
#            if defined(SO_TYPE) /* POSIX */
              case SO_TYPE: inspected = inspect_socktype(level, optname, data, ret); break;
#            endif
#            if defined(SO_ACCEPTCONN) /* POSIX */
              case SO_ACCEPTCONN: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_BROADCAST) /* POSIX */
              case SO_BROADCAST: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_REUSEADDR) /* POSIX */
              case SO_REUSEADDR: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_KEEPALIVE) /* POSIX */
              case SO_KEEPALIVE: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_OOBINLINE) /* POSIX */
              case SO_OOBINLINE: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_SNDBUF) /* POSIX */
              case SO_SNDBUF: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_RCVBUF) /* POSIX */
              case SO_RCVBUF: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_DONTROUTE) /* POSIX */
              case SO_DONTROUTE: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_RCVLOWAT) /* POSIX */
              case SO_RCVLOWAT: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_SNDLOWAT) /* POSIX */
              case SO_SNDLOWAT: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(SO_LINGER) /* POSIX */
              case SO_LINGER: inspected = inspect_linger(level, optname, data, ret); break;
#            endif
#            if defined(SO_RCVTIMEO) /* POSIX */
              case SO_RCVTIMEO: inspected = inspect_timeval_as_interval(level, optname, data, ret); break;
#            endif
#            if defined(SO_SNDTIMEO) /* POSIX */
              case SO_SNDTIMEO: inspected = inspect_timeval_as_interval(level, optname, data, ret); break;
#            endif
#            if defined(SO_PEERCRED) /* GNU/Linux, OpenBSD */
              case SO_PEERCRED: inspected = inspect_peercred(level, optname, data, ret); break;
#            endif
            }
            break;
        }
        break;

      case AF_INET:
#ifdef INET6
      case AF_INET6:
#endif
        switch (level) {
#        if defined(IPPROTO_IP)
          case IPPROTO_IP:
            switch (optname) {
#            if defined(IP_MULTICAST_IF) && defined(HAVE_TYPE_STRUCT_IP_MREQN) /* 4.4BSD, GNU/Linux */
              case IP_MULTICAST_IF: inspected = inspect_ipv4_multicast_if(level, optname, data, ret); break;
#            endif
#            if defined(IP_ADD_MEMBERSHIP) /* 4.4BSD, GNU/Linux */
              case IP_ADD_MEMBERSHIP: inspected = inspect_ipv4_add_drop_membership(level, optname, data, ret); break;
#            endif
#            if defined(IP_DROP_MEMBERSHIP) /* 4.4BSD, GNU/Linux */
              case IP_DROP_MEMBERSHIP: inspected = inspect_ipv4_add_drop_membership(level, optname, data, ret); break;
#            endif
#            if defined(IP_MULTICAST_LOOP) /* 4.4BSD, GNU/Linux */
              case IP_MULTICAST_LOOP: inspected = inspect_ipv4_multicast_loop(level, optname, data, ret); break;
#            endif
#            if defined(IP_MULTICAST_TTL) /* 4.4BSD, GNU/Linux */
              case IP_MULTICAST_TTL: inspected = inspect_ipv4_multicast_ttl(level, optname, data, ret); break;
#            endif
            }
            break;
#        endif

#        if defined(IPPROTO_IPV6)
          case IPPROTO_IPV6:
            switch (optname) {
#            if defined(IPV6_MULTICAST_HOPS) /* POSIX */
              case IPV6_MULTICAST_HOPS: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_MULTICAST_IF) /* POSIX */
              case IPV6_MULTICAST_IF: inspected = inspect_ipv6_multicast_if(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_MULTICAST_LOOP) /* POSIX */
              case IPV6_MULTICAST_LOOP: inspected = inspect_uint(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_JOIN_GROUP) /* POSIX */
              case IPV6_JOIN_GROUP: inspected = inspect_ipv6_mreq(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_LEAVE_GROUP) /* POSIX */
              case IPV6_LEAVE_GROUP: inspected = inspect_ipv6_mreq(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_UNICAST_HOPS) /* POSIX */
              case IPV6_UNICAST_HOPS: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_V6ONLY) /* POSIX */
              case IPV6_V6ONLY: inspected = inspect_int(level, optname, data, ret); break;
#            endif
            }
            break;
#        endif

#        if defined(IPPROTO_TCP)
          case IPPROTO_TCP:
            switch (optname) {
#            if defined(TCP_NODELAY) /* POSIX */
              case TCP_NODELAY: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(TCP_INFO) && defined(HAVE_TYPE_STRUCT_TCP_INFO) /* Linux, FreeBSD */
              case TCP_INFO: inspected = inspect_tcp_info(level, optname, data, ret); break;
#            endif
            }
            break;
#        endif
        }
        break;

#ifdef HAVE_SYS_UN_H
      case AF_UNIX:
        switch (level) {
          case 0:
            switch (optname) {
#            if defined(LOCAL_PEERCRED)
              case LOCAL_PEERCRED: inspected = inspect_local_peercred(level, optname, data, ret); break;
#            endif
            }
            break;
        }
        break;
#endif
    }

    if (!inspected) {
        rb_str_cat2(ret, " ");
        rb_str_append(ret, rb_str_dump(data));
    }

    rb_str_cat2(ret, ">");

    return ret;
}

/*
 * call-seq:
 *   sockopt.unpack(template) => array
 *
 * Calls String#unpack on sockopt.data.
 *
 *   sockopt = Socket::Option.new(:INET, :SOCKET, :KEEPALIVE, [1].pack("i"))
 *   p sockopt.unpack("i")      #=> [1]
 *   p sockopt.data.unpack("i") #=> [1]
 */
static VALUE
sockopt_unpack(VALUE self, VALUE template)
{
    return rb_funcall(sockopt_data(self), rb_intern("unpack"), 1, template);
}

void
rsock_init_sockopt(void)
{
    /*
     * Document-class: Socket::Option
     *
     * Socket::Option represents a socket option used by
     * BasicSocket#getsockopt and BasicSocket#setsockopt.  A socket option
     * contains the socket #family, protocol #level, option name #optname and
     * option value #data.
     */
    rb_cSockOpt = rb_define_class_under(rb_cSocket, "Option", rb_cObject);
    rb_define_method(rb_cSockOpt, "initialize", sockopt_initialize, 4);
    rb_define_method(rb_cSockOpt, "family", sockopt_family_m, 0);
    rb_define_method(rb_cSockOpt, "level", sockopt_level_m, 0);
    rb_define_method(rb_cSockOpt, "optname", sockopt_optname_m, 0);
    rb_define_method(rb_cSockOpt, "data", sockopt_data, 0);
    rb_define_method(rb_cSockOpt, "inspect", sockopt_inspect, 0);

    rb_define_singleton_method(rb_cSockOpt, "int", sockopt_s_int, 4);
    rb_define_method(rb_cSockOpt, "int", sockopt_int, 0);

    rb_define_singleton_method(rb_cSockOpt, "byte", sockopt_s_byte, 4);
    rb_define_method(rb_cSockOpt, "byte", sockopt_byte, 0);

    rb_define_singleton_method(rb_cSockOpt, "bool", sockopt_s_bool, 4);
    rb_define_method(rb_cSockOpt, "bool", sockopt_bool, 0);

    rb_define_singleton_method(rb_cSockOpt, "linger", sockopt_s_linger, 2);
    rb_define_method(rb_cSockOpt, "linger", sockopt_linger, 0);

    rb_define_singleton_method(rb_cSockOpt, "ipv4_multicast_ttl", sockopt_s_ipv4_multicast_ttl, 1);
    rb_define_method(rb_cSockOpt, "ipv4_multicast_ttl", sockopt_ipv4_multicast_ttl, 0);

    rb_define_singleton_method(rb_cSockOpt, "ipv4_multicast_loop", sockopt_s_ipv4_multicast_loop, 1);
    rb_define_method(rb_cSockOpt, "ipv4_multicast_loop", sockopt_ipv4_multicast_loop, 0);

    rb_define_method(rb_cSockOpt, "unpack", sockopt_unpack, 1);

    rb_define_method(rb_cSockOpt, "to_s", sockopt_data, 0); /* compatibility for ruby before 1.9.2 */
}
