#include "rubysocket.h"

VALUE rb_cSockOpt;

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
#ifdef INET6
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
    NEWOBJ(obj, struct RObject);
    OBJSETUP(obj, rb_cSockOpt, T_OBJECT);
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
 *   Socket::Option.int(family, level, optname, integer) => sockopt
 *
 * Creates a new Socket::Option object which contains an int as data.
 *
 * The size and endian is dependent on the host. 
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
    int i = NUM2INT(vint);
    return rsock_sockopt_new(family, level, optname, rb_str_new((char*)&i, sizeof(i)));
}

/*
 * call-seq:
 *   sockopt.int => integer
 *
 * Returns the data in _sockopt_ as an int.
 *
 * The size and endian is dependent on the host. 
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
    if (RSTRING_LEN(data) != sizeof(int))
        rb_raise(rb_eTypeError, "size differ.  expected as sizeof(int)=%d but %ld",
                 (int)sizeof(int), (long)RSTRING_LEN(data));
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
    return rsock_sockopt_new(family, level, optname, rb_str_new((char*)&i, sizeof(i)));
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
    VALUE data = sockopt_data(self);
    StringValue(data);
    if (RSTRING_LEN(data) != sizeof(int))
        rb_raise(rb_eTypeError, "size differ.  expected as sizeof(int)=%d but %ld",
                 (int)sizeof(int), (long)RSTRING_LEN(data));
    memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
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
    return rsock_sockopt_new(AF_UNSPEC, SOL_SOCKET, SO_LINGER, rb_str_new((char*)&l, sizeof(l)));
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
    if (RSTRING_LEN(data) != sizeof(l))
        rb_raise(rb_eTypeError, "size differ.  expected as sizeof(struct linger)=%d but %ld",
                 (int)sizeof(struct linger), (long)RSTRING_LEN(data));
    memcpy((char*)&l, RSTRING_PTR(data), sizeof(struct linger));
    switch (l.l_onoff) {
      case 0: vonoff = Qfalse; break;
      case 1: vonoff = Qtrue; break;
      default: vonoff = INT2NUM(l.l_onoff); break;
    }
    vsecs = INT2NUM(l.l_linger);
    return rb_assoc_new(vonoff, vsecs);
}

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

#if defined(IPV6_MULTICAST_IF) || defined(IPV6_MULTICAST_LOOP)
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

#if defined(SOL_SOCKET) && defined(SO_PEERCRED) /* GNU/Linux */
static int
inspect_peercred(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ucred)) {
        struct ucred cred;
        memcpy(&cred, RSTRING_PTR(data), sizeof(struct ucred));
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
	    rb_str_catf(ret, " %s", rb_id2name(SYM2ID(v)));
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
#            if defined(SO_PEERCRED) /* GNU/Linux */
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
#        if defined(IPPROTO_IPV6)
          case IPPROTO_IPV6:
            switch (optname) {
              /* IPV6_JOIN_GROUP ipv6_mreq, IPV6_LEAVE_GROUP ipv6_mreq */
#            if defined(IPV6_MULTICAST_HOPS) /* POSIX */
              case IPV6_MULTICAST_HOPS: inspected = inspect_int(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_MULTICAST_IF) /* POSIX */
              case IPV6_MULTICAST_IF: inspected = inspect_uint(level, optname, data, ret); break;
#            endif
#            if defined(IPV6_MULTICAST_LOOP) /* POSIX */
              case IPV6_MULTICAST_LOOP: inspected = inspect_uint(level, optname, data, ret); break;
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
        data = rb_str_dump(data);
        rb_str_catf(ret, " %s", StringValueCStr(data));
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
Init_sockopt(void)
{
    /* for rdoc */
    /* rb_cSocket = rb_define_class("Socket", rb_cBasicSocket); */

    rb_cSockOpt = rb_define_class_under(rb_cSocket, "Option", rb_cObject);
    rb_define_method(rb_cSockOpt, "initialize", sockopt_initialize, 4);
    rb_define_method(rb_cSockOpt, "family", sockopt_family_m, 0);
    rb_define_method(rb_cSockOpt, "level", sockopt_level_m, 0);
    rb_define_method(rb_cSockOpt, "optname", sockopt_optname_m, 0);
    rb_define_method(rb_cSockOpt, "data", sockopt_data, 0);
    rb_define_method(rb_cSockOpt, "inspect", sockopt_inspect, 0);

    rb_define_singleton_method(rb_cSockOpt, "int", sockopt_s_int, 4);
    rb_define_method(rb_cSockOpt, "int", sockopt_int, 0);

    rb_define_singleton_method(rb_cSockOpt, "bool", sockopt_s_bool, 4);
    rb_define_method(rb_cSockOpt, "bool", sockopt_bool, 0);

    rb_define_singleton_method(rb_cSockOpt, "linger", sockopt_s_linger, 2);
    rb_define_method(rb_cSockOpt, "linger", sockopt_linger, 0);

    rb_define_method(rb_cSockOpt, "unpack", sockopt_unpack, 1);

    rb_define_method(rb_cSockOpt, "to_s", sockopt_data, 0); /* compatibility for ruby before 1.9.2 */
}

