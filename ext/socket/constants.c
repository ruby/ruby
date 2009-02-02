/************************************************

  constants.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

static void sock_define_const(const char *name, int value, VALUE mConst);
static void sock_define_uconst(const char *name, unsigned int value, VALUE mConst);
#define sock_define_const(name, value) sock_define_const(name, value, mConst)
#define sock_define_uconst(name, value) sock_define_uconst(name, value, mConst)
#include "constdefs.c"
#undef sock_define_const
#undef sock_define_uconst

static int
constant_arg(VALUE arg, int (*str_to_int)(const char*, int, int*), const char *errmsg)
{
    VALUE tmp;
    char *ptr;
    int ret;

    if (SYMBOL_P(arg)) {
        arg = rb_sym_to_s(arg);
        goto str;
    }
    else if (!NIL_P(tmp = rb_check_string_type(arg))) {
	arg = tmp;
      str:
	rb_check_safe_obj(arg);
        ptr = RSTRING_PTR(arg);
        if (str_to_int(ptr, RSTRING_LEN(arg), &ret) == -1)
	    rb_raise(rb_eSocket, "%s: %s", errmsg, ptr);
    }
    else {
	ret = NUM2INT(arg);
    }
    return ret;
}

int
family_arg(VALUE domain)
{
    /* convert AF_INET, etc. */
    return constant_arg(domain, family_to_int, "unknown socket domain");
}

int
socktype_arg(VALUE type)
{
    /* convert SOCK_STREAM, etc. */
    return constant_arg(type, socktype_to_int, "unknown socket type");
}

int
level_arg(VALUE level)
{
    /* convert SOL_SOCKET, IPPROTO_TCP, etc. */
    return constant_arg(level, level_to_int, "unknown protocol level");
}

int
optname_arg(int level, VALUE optname)
{
    switch (level) {
      case SOL_SOCKET:
        return constant_arg(optname, so_optname_to_int, "unknown socket level option name");
      case IPPROTO_IP:
        return constant_arg(optname, ip_optname_to_int, "unknown IP level option name");
#ifdef IPPROTO_IPV6
      case IPPROTO_IPV6:
        return constant_arg(optname, ipv6_optname_to_int, "unknown IPv6 level option name");
#endif
      case IPPROTO_TCP:
        return constant_arg(optname, tcp_optname_to_int, "unknown TCP level option name");
      case IPPROTO_UDP:
        return constant_arg(optname, udp_optname_to_int, "unknown UDP level option name");
      default:
        return NUM2INT(optname);
    }
}

int
shutdown_how_arg(VALUE how)
{
    /* convert SHUT_RD, SHUT_WR, SHUT_RDWR. */
    return constant_arg(how, shutdown_how_to_int, "unknown shutdown argument");
}

int
cmsg_type_arg(int level, VALUE optname)
{
    switch (level) {
      case SOL_SOCKET:
        return constant_arg(optname, scm_optname_to_int, "unknown UNIX control message");
      case IPPROTO_IP:
        return constant_arg(optname, ip_optname_to_int, "unknown IP control message");
      case IPPROTO_IPV6:
        return constant_arg(optname, ipv6_optname_to_int, "unknown IPv6 control message");
      case IPPROTO_TCP:
        return constant_arg(optname, tcp_optname_to_int, "unknown TCP control message");
      case IPPROTO_UDP:
        return constant_arg(optname, udp_optname_to_int, "unknown UDP control message");
      default:
        return NUM2INT(optname);
    }
}

static void
sock_define_const(const char *name, int value, VALUE mConst)
{
    rb_define_const(rb_cSocket, name, INT2NUM(value));
    rb_define_const(mConst, name, INT2NUM(value));
}

static void
sock_define_uconst(const char *name, unsigned int value, VALUE mConst)
{
    rb_define_const(rb_cSocket, name, UINT2NUM(value));
    rb_define_const(mConst, name, UINT2NUM(value));
}

/*
 * Socket::Constants module
 */
void
Init_socket_constants(void)
{
    VALUE mConst;

    /* constants */
    mConst = rb_define_module_under(rb_cSocket, "Constants");
    init_constants(mConst);
}
