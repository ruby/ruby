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
        return constant_to_sym(optname, intern_so_optname);
      case IPPROTO_IP:
        return constant_to_sym(optname, intern_ip_optname);
#ifdef INET6
      case IPPROTO_IPV6:
        return constant_to_sym(optname, intern_ipv6_optname);
#endif
      case IPPROTO_TCP:
        return constant_to_sym(optname, intern_tcp_optname);
      case IPPROTO_UDP:
        return constant_to_sym(optname, intern_udp_optname);
      default:
        return INT2NUM(optname);
    }
}

static VALUE
sockopt_initialize(VALUE self, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE data)
{
    int family;
    int level;
    StringValue(data);
    level = level_arg(vlevel);
    family = family_arg(vfamily);
    rb_ivar_set(self, rb_intern("family"), INT2NUM(family));
    rb_ivar_set(self, rb_intern("level"), INT2NUM(level));
    rb_ivar_set(self, rb_intern("optname"), INT2NUM(optname_arg(level, voptname)));
    rb_ivar_set(self, rb_intern("data"), data);
    return self;
}

VALUE
sockopt_new(int family, int level, int optname, VALUE data)
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
 */
static VALUE
sockopt_family(VALUE self)
{
    return rb_attr_get(self, rb_intern("family"));
}

/*
 * call-seq:
 *   sockopt.level => integer
 *
 * returns the socket level as an integer.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).level
 */
static VALUE
sockopt_level(VALUE self)
{
    return rb_attr_get(self, rb_intern("level"));
}

/*
 * call-seq:
 *   sockopt.optname => integer
 *
 * returns the socket option name as an integer.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :RECVPKTINFO, [1].pack("i!")).optname
 */
static VALUE
sockopt_optname(VALUE self)
{
    return rb_attr_get(self, rb_intern("optname"));
}

/*
 * call-seq:
 *   sockopt.data => string
 *
 * returns the socket option data as a string.
 *
 *   p Socket::Option.new(:INET6, :IPV6, :PKTINFO, [1].pack("i!")).data
 */
static VALUE
sockopt_data(VALUE self)
{
    return rb_attr_get(self, rb_intern("data"));
}

/*
 * call-seq:
 *   Socket::Option.int(family, level, optname, integer) => sockopt
 *
 * Creates a new Socket::Option object which contains an int as data.
 *
 * The size and endian is dependent on the host. 
 *
 *   p Socket::Option.int(:SOCKET, :KEEPALIVE, 1)
 *   #=> #<Socket::Option: SOCKET KEEPALIVE 1>
 */
static VALUE
sockopt_s_int(VALUE klass, VALUE vfamily, VALUE vlevel, VALUE voptname, VALUE vint)
{
    int family = family_arg(vfamily);
    int level = level_arg(vlevel);
    int optname = optname_arg(level, voptname);
    int i = NUM2INT(vint);
    return sockopt_new(family, level, optname, rb_str_new((char*)&i, sizeof(i)));
}

/*
 * call-seq:
 *   sockopt.int => integer
 *
 * Returns the data in _sockopt_ as an int.
 *
 * The size and endian is dependent on the host. 
 *
 *   sockopt = Socket::Option.int(:SOCKET, :KEEPALIVE, 1)
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

static int
inspect_int(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        int i;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(int));
        rb_str_catf(ret, " %d", i);
        return 0;
    }
    else {
        return -1;
    }
}

static int
inspect_uint(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(int)) {
        unsigned int i;
        memcpy((char*)&i, RSTRING_PTR(data), sizeof(unsigned int));
        rb_str_catf(ret, " %u", i);
        return 0;
    }
    else {
        return -1;
    }
}

#if defined(SOL_SOCKET) && defined(SO_LINGER) /* POSIX */
static int
inspect_linger(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct linger)) {
        struct linger s;
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        rb_str_catf(ret, " onoff:%d linger:%d", s.l_onoff, s.l_linger);
        return 0;
    }
    else {
        return -1;
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
        id = intern_socktype(i);
        if (id)
            rb_str_catf(ret, " %s", rb_id2name(id));
        else
            rb_str_catf(ret, " %d", i);
        return 0;
    }
    else {
        return -1;
    }
}
#endif

static int
inspect_timeval(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct linger)) {
        struct timeval s;
        memcpy((char*)&s, RSTRING_PTR(data), sizeof(s));
        rb_str_catf(ret, " %ld.%06ldsec", (long)s.tv_sec, (long)s.tv_usec);
        return 0;
    }
    else {
        return -1;
    }
}

#if defined(SOL_SOCKET) && defined(SO_PEERCRED) /* GNU/Linux */
static int
inspect_peercred(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct ucred)) {
        struct ucred cred;
        memcpy(&cred, RSTRING_PTR(data), sizeof(struct ucred));
        rb_str_catf(ret, " pid=%u uid=%u gid=%u", cred.pid, cred.uid, cred.gid);
        rb_str_cat2(ret, " (ucred)");
        return 0;
    }
    else {
        return -1;
    }
}
#endif

#if defined(LOCAL_PEERCRED) /* FreeBSD */
static int
inspect_local_peercred(int level, int optname, VALUE data, VALUE ret)
{
    if (RSTRING_LEN(data) == sizeof(struct xucred)) {
        struct xucred cred;
        memcpy(&cred, RSTRING_PTR(data), sizeof(struct xucred));
        rb_str_catf(ret, " version=%u", cred.cr_version);
        rb_str_catf(ret, " euid=%u", cred.cr_uid);
	if (cred.cr_ngroups) {
	    int i;
	    char *sep = " groups=";
	    for (i = 0; i < cred.cr_ngroups; i++) {
		rb_str_catf(ret, "%s%u", sep, cred.cr_groups[i]);
		sep = ",";
	    }
	}
        rb_str_cat2(ret, " (xucred)");
        return 0;
    }
    else {
        return -1;
    }
}
#endif

static VALUE
sockopt_inspect(VALUE self)
{
    int family = NUM2INT(sockopt_family(self));
    int level = NUM2INT(sockopt_level(self));
    int optname = NUM2INT(sockopt_optname(self));
    VALUE data = sockopt_data(self);
    VALUE v, ret;
    ID family_id, level_id, optname_id;

    StringValue(data);

    ret = rb_sprintf("#<%s: ", rb_obj_classname(self));

    family_id = intern_family(family);
    if (family_id)
	rb_str_cat2(ret, rb_id2name(family_id));
    else
        rb_str_catf(ret, "family:%d", family);

    if (family == AF_UNIX && level == 0) {
	rb_str_catf(ret, " level:%d", level);

	optname_id = intern_local_optname(optname);
	if (optname_id)
	    rb_str_catf(ret, " %s", rb_id2name(optname_id));
	else
	    rb_str_catf(ret, " optname:%d", optname);
    }
    else {
	level_id = intern_level(level);
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

    if (family == AF_UNIX && level == 0) {
#     if defined(LOCAL_PEERCRED)
	if (optname == LOCAL_PEERCRED) {
	    if (inspect_local_peercred(level, optname, data, ret) == -1) goto dump;
	    goto finish;
	}
#     endif
    }

    switch (level) {
#    if defined(SOL_SOCKET)
      case SOL_SOCKET:
        switch (optname) {
#        if defined(SO_DEBUG) /* POSIX */
          case SO_DEBUG: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_ERROR) /* POSIX */
          case SO_ERROR: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_TYPE) /* POSIX */
          case SO_TYPE: if (inspect_socktype(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_ACCEPTCONN) /* POSIX */
          case SO_ACCEPTCONN: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_BROADCAST) /* POSIX */
          case SO_BROADCAST: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_REUSEADDR) /* POSIX */
          case SO_REUSEADDR: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_KEEPALIVE) /* POSIX */
          case SO_KEEPALIVE: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_OOBINLINE) /* POSIX */
          case SO_OOBINLINE: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_SNDBUF) /* POSIX */
          case SO_SNDBUF: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_RCVBUF) /* POSIX */
          case SO_RCVBUF: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_DONTROUTE) /* POSIX */
          case SO_DONTROUTE: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_RCVLOWAT) /* POSIX */
          case SO_RCVLOWAT: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_SNDLOWAT) /* POSIX */
          case SO_SNDLOWAT: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif

#        if defined(SO_LINGER) /* POSIX */
          case SO_LINGER: if (inspect_linger(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_RCVTIMEO) /* POSIX */
          case SO_RCVTIMEO: if (inspect_timeval(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_SNDTIMEO) /* POSIX */
          case SO_SNDTIMEO: if (inspect_timeval(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(SO_PEERCRED) /* GNU/Linux */
          case SO_PEERCRED: if (inspect_peercred(level, optname, data, ret) == -1) goto dump; break;
#        endif

          default: goto dump;
        }
        break;
#    endif

#    if defined(IPPROTO_IPV6)
      case IPPROTO_IPV6:
        switch (optname) {
          /* IPV6_JOIN_GROUP ipv6_mreq, IPV6_LEAVE_GROUP ipv6_mreq */
#        if defined(IPV6_MULTICAST_HOPS) /* POSIX */
          case IPV6_MULTICAST_HOPS: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(IPV6_MULTICAST_IF) /* POSIX */
          case IPV6_MULTICAST_IF: if (inspect_uint(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(IPV6_MULTICAST_LOOP) /* POSIX */
          case IPV6_MULTICAST_LOOP: if (inspect_uint(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(IPV6_UNICAST_HOPS) /* POSIX */
          case IPV6_UNICAST_HOPS: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
#        if defined(IPV6_V6ONLY) /* POSIX */
          case IPV6_V6ONLY: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
          default: goto dump;
        }
        break;
#    endif

#    if defined(IPPROTO_TCP)
      case IPPROTO_TCP:
        switch (optname) {
#        if defined(TCP_NODELAY) /* POSIX */
          case TCP_NODELAY: if (inspect_int(level, optname, data, ret) == -1) goto dump; break;
#        endif
          default: goto dump;
        }
        break;
#    endif

      default:
      dump:
        data = rb_str_dump(data);
        rb_str_catf(ret, " %s", StringValueCStr(data));
    }

  finish:
    rb_str_cat2(ret, ">");

    return ret;
}

static VALUE
sockopt_unpack(VALUE self, VALUE template)
{
    return rb_funcall(sockopt_data(self), rb_intern("unpack"), 1, template);
}

void
Init_sockopt(void)
{
    rb_cSockOpt = rb_define_class_under(rb_cSocket, "Option", rb_cObject);
    rb_define_method(rb_cSockOpt, "initialize", sockopt_initialize, 4);
    rb_define_method(rb_cSockOpt, "family", sockopt_family, 0);
    rb_define_method(rb_cSockOpt, "level", sockopt_level, 0);
    rb_define_method(rb_cSockOpt, "optname", sockopt_optname, 0);
    rb_define_method(rb_cSockOpt, "data", sockopt_data, 0);
    rb_define_method(rb_cSockOpt, "inspect", sockopt_inspect, 0);

    rb_define_singleton_method(rb_cSockOpt, "int", sockopt_s_int, 4);
    rb_define_method(rb_cSockOpt, "int", sockopt_int, 0);

    rb_define_method(rb_cSockOpt, "unpack", sockopt_unpack, 1);

    rb_define_method(rb_cSockOpt, "to_s", sockopt_data, 0); /* compatibility for ruby before 1.9.2 */
}

