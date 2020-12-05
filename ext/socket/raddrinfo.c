/************************************************

  raddrinfo.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"

#if defined(INET6) && (defined(LOOKUP_ORDER_HACK_INET) || defined(LOOKUP_ORDER_HACK_INET6))
#define LOOKUP_ORDERS (sizeof(lookup_order_table) / sizeof(lookup_order_table[0]))
static const int lookup_order_table[] = {
#if defined(LOOKUP_ORDER_HACK_INET)
    PF_INET, PF_INET6, PF_UNSPEC,
#elif defined(LOOKUP_ORDER_HACK_INET6)
    PF_INET6, PF_INET, PF_UNSPEC,
#else
    /* should not happen */
#endif
};

static int
ruby_getaddrinfo(const char *nodename, const char *servname,
		 const struct addrinfo *hints, struct addrinfo **res)
{
    struct addrinfo tmp_hints;
    int i, af, error;

    if (hints->ai_family != PF_UNSPEC) {
	return getaddrinfo(nodename, servname, hints, res);
    }

    for (i = 0; i < LOOKUP_ORDERS; i++) {
	af = lookup_order_table[i];
	MEMCPY(&tmp_hints, hints, struct addrinfo, 1);
	tmp_hints.ai_family = af;
	error = getaddrinfo(nodename, servname, &tmp_hints, res);
	if (error) {
	    if (tmp_hints.ai_family == PF_UNSPEC) {
		break;
	    }
	}
	else {
	    break;
	}
    }

    return error;
}
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo((node),(serv),(hints),(res))
#endif

#if defined(_AIX)
static int
ruby_getaddrinfo__aix(const char *nodename, const char *servname,
		      const struct addrinfo *hints, struct addrinfo **res)
{
    int error = getaddrinfo(nodename, servname, hints, res);
    struct addrinfo *r;
    if (error)
	return error;
    for (r = *res; r != NULL; r = r->ai_next) {
	if (r->ai_addr->sa_family == 0)
	    r->ai_addr->sa_family = r->ai_family;
	if (r->ai_addr->sa_len == 0)
	    r->ai_addr->sa_len = r->ai_addrlen;
    }
    return 0;
}
#undef getaddrinfo
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo__aix((node),(serv),(hints),(res))
static int
ruby_getnameinfo__aix(const struct sockaddr *sa, size_t salen,
		      char *host, size_t hostlen,
		      char *serv, size_t servlen, int flags)
{
    struct sockaddr_in6 *sa6;
    u_int32_t *a6;

    if (sa->sa_family == AF_INET6) {
	sa6 = (struct sockaddr_in6 *)sa;
	a6 = sa6->sin6_addr.u6_addr.u6_addr32;

	if (a6[0] == 0 && a6[1] == 0 && a6[2] == 0 && a6[3] == 0) {
	    strncpy(host, "::", hostlen);
	    snprintf(serv, servlen, "%d", sa6->sin6_port);
	    return 0;
	}
    }
    return getnameinfo(sa, salen, host, hostlen, serv, servlen, flags);
}
#undef getnameinfo
#define getnameinfo(sa, salen, host, hostlen, serv, servlen, flags) \
            ruby_getnameinfo__aix((sa), (salen), (host), (hostlen), (serv), (servlen), (flags))
#endif

static int str_is_number(const char *);

#if defined(__APPLE__)
static int
ruby_getaddrinfo__darwin(const char *nodename, const char *servname,
			 const struct addrinfo *hints, struct addrinfo **res)
{
    /* fix [ruby-core:29427] */
    const char *tmp_servname;
    struct addrinfo tmp_hints;
    int error;

    tmp_servname = servname;
    MEMCPY(&tmp_hints, hints, struct addrinfo, 1);
    if (nodename && servname) {
	if (str_is_number(tmp_servname) && atoi(servname) == 0) {
	    tmp_servname = NULL;
#ifdef AI_NUMERICSERV
	    if (tmp_hints.ai_flags) tmp_hints.ai_flags &= ~AI_NUMERICSERV;
#endif
	}
    }

    error = getaddrinfo(nodename, tmp_servname, &tmp_hints, res);
    if (error == 0) {
        /* [ruby-dev:23164] */
        struct addrinfo *r;
        r = *res;
        while (r) {
            if (! r->ai_socktype) r->ai_socktype = hints->ai_socktype;
            if (! r->ai_protocol) {
                if (r->ai_socktype == SOCK_DGRAM) {
                    r->ai_protocol = IPPROTO_UDP;
                }
                else if (r->ai_socktype == SOCK_STREAM) {
                    r->ai_protocol = IPPROTO_TCP;
                }
            }
            r = r->ai_next;
        }
    }

    return error;
}
#undef getaddrinfo
#define getaddrinfo(node,serv,hints,res) ruby_getaddrinfo__darwin((node),(serv),(hints),(res))
#endif

#ifdef HAVE_INET_PTON
static int
parse_numeric_port(const char *service, int *portp)
{
    unsigned long u;

    if (!service) {
        *portp = 0;
        return 1;
    }

    if (strspn(service, "0123456789") != strlen(service))
        return 0;

    errno = 0;
    u = STRTOUL(service, NULL, 10);
    if (errno)
        return 0;

    if (0x10000 <= u)
        return 0;

    *portp = (int)u;

    return 1;
}
#endif

#ifndef GETADDRINFO_EMU
struct getaddrinfo_arg
{
    const char *node;
    const char *service;
    const struct addrinfo *hints;
    struct addrinfo **res;
};

static void *
nogvl_getaddrinfo(void *arg)
{
    int ret;
    struct getaddrinfo_arg *ptr = arg;
    ret = getaddrinfo(ptr->node, ptr->service, ptr->hints, ptr->res);
#ifdef __linux__
    /* On Linux (mainly Ubuntu 13.04) /etc/nsswitch.conf has mdns4 and
     * it cause getaddrinfo to return EAI_SYSTEM/ENOENT. [ruby-list:49420]
     */
    if (ret == EAI_SYSTEM && errno == ENOENT)
	ret = EAI_NONAME;
#endif
    return (void *)(VALUE)ret;
}
#endif

#ifdef HAVE_GETADDRINFO_A
struct gai_suspend_arg
{
    struct gaicb *req;
    struct timespec *timeout;
};

static void *
nogvl_gai_suspend(void *arg)
{
    int ret;
    struct gai_suspend_arg *ptr = arg;
    struct gaicb const *wait_reqs[1];

    wait_reqs[0] = ptr->req;
    ret = gai_suspend(wait_reqs, 1, ptr->timeout);

    return (void *)(VALUE)ret;
}
#endif

static int
numeric_getaddrinfo(const char *node, const char *service,
        const struct addrinfo *hints,
        struct addrinfo **res)
{
#ifdef HAVE_INET_PTON
# if defined __MINGW64__
#   define inet_pton(f,s,d)        rb_w32_inet_pton(f,s,d)
# endif

    int port;

    if (node && parse_numeric_port(service, &port)) {
	static const struct {
	    int socktype;
	    int protocol;
	} list[] = {
	    { SOCK_STREAM, IPPROTO_TCP },
	    { SOCK_DGRAM, IPPROTO_UDP },
	    { SOCK_RAW, 0 }
	};
	struct addrinfo *ai = NULL;
        int hint_family = hints ? hints->ai_family : PF_UNSPEC;
        int hint_socktype = hints ? hints->ai_socktype : 0;
        int hint_protocol = hints ? hints->ai_protocol : 0;
        char ipv4addr[4];
#ifdef AF_INET6
        char ipv6addr[16];
        if ((hint_family == PF_UNSPEC || hint_family == PF_INET6) &&
            strspn(node, "0123456789abcdefABCDEF.:") == strlen(node) &&
            inet_pton(AF_INET6, node, ipv6addr)) {
            int i;
            for (i = numberof(list)-1; 0 <= i; i--) {
                if ((hint_socktype == 0 || hint_socktype == list[i].socktype) &&
                    (hint_protocol == 0 || list[i].protocol == 0 || hint_protocol == list[i].protocol)) {
                    struct addrinfo *ai0 = xcalloc(1, sizeof(struct addrinfo));
                    struct sockaddr_in6 *sa = xmalloc(sizeof(struct sockaddr_in6));
                    INIT_SOCKADDR_IN6(sa, sizeof(struct sockaddr_in6));
                    memcpy(&sa->sin6_addr, ipv6addr, sizeof(ipv6addr));
                    sa->sin6_port = htons(port);
                    ai0->ai_family = PF_INET6;
                    ai0->ai_socktype = list[i].socktype;
                    ai0->ai_protocol = hint_protocol ? hint_protocol : list[i].protocol;
                    ai0->ai_addrlen = sizeof(struct sockaddr_in6);
                    ai0->ai_addr = (struct sockaddr *)sa;
                    ai0->ai_canonname = NULL;
                    ai0->ai_next = ai;
                    ai = ai0;
                }
            }
        }
        else
#endif
        if ((hint_family == PF_UNSPEC || hint_family == PF_INET) &&
            strspn(node, "0123456789.") == strlen(node) &&
            inet_pton(AF_INET, node, ipv4addr)) {
            int i;
            for (i = numberof(list)-1; 0 <= i; i--) {
                if ((hint_socktype == 0 || hint_socktype == list[i].socktype) &&
                    (hint_protocol == 0 || list[i].protocol == 0 || hint_protocol == list[i].protocol)) {
                    struct addrinfo *ai0 = xcalloc(1, sizeof(struct addrinfo));
                    struct sockaddr_in *sa = xmalloc(sizeof(struct sockaddr_in));
                    INIT_SOCKADDR_IN(sa, sizeof(struct sockaddr_in));
                    memcpy(&sa->sin_addr, ipv4addr, sizeof(ipv4addr));
                    sa->sin_port = htons(port);
                    ai0->ai_family = PF_INET;
                    ai0->ai_socktype = list[i].socktype;
                    ai0->ai_protocol = hint_protocol ? hint_protocol : list[i].protocol;
                    ai0->ai_addrlen = sizeof(struct sockaddr_in);
                    ai0->ai_addr = (struct sockaddr *)sa;
                    ai0->ai_canonname = NULL;
                    ai0->ai_next = ai;
                    ai = ai0;
                }
            }
        }
        if (ai) {
            *res = ai;
            return 0;
        }
    }
#endif
    return EAI_FAIL;
}

int
rb_getaddrinfo(const char *node, const char *service,
               const struct addrinfo *hints,
               struct rb_addrinfo **res)
{
    struct addrinfo *ai;
    int ret;
    int allocated_by_malloc = 0;

    ret = numeric_getaddrinfo(node, service, hints, &ai);
    if (ret == 0)
        allocated_by_malloc = 1;
    else {
#ifdef GETADDRINFO_EMU
        ret = getaddrinfo(node, service, hints, &ai);
#else
        struct getaddrinfo_arg arg;
        MEMZERO(&arg, struct getaddrinfo_arg, 1);
        arg.node = node;
        arg.service = service;
        arg.hints = hints;
        arg.res = &ai;
        ret = (int)(VALUE)rb_thread_call_without_gvl(nogvl_getaddrinfo, &arg, RUBY_UBF_IO, 0);
#endif
    }

    if (ret == 0) {
        *res = (struct rb_addrinfo *)xmalloc(sizeof(struct rb_addrinfo));
        (*res)->allocated_by_malloc = allocated_by_malloc;
        (*res)->ai = ai;
    }
    return ret;
}

#ifdef HAVE_GETADDRINFO_A
struct gaicbs {
    struct gaicbs *next;
    struct gaicb *gaicb;
};

/* linked list to retain all outstanding and ongoing requests */
static struct gaicbs *requests = NULL;

static void
gaicbs_add(struct gaicb *req)
{
    struct gaicbs *request;

    if (!req) return;
    request = (struct gaicbs *)xmalloc(sizeof(struct gaicbs));
    request->gaicb = req;
    request->next = requests;

    requests = request;
}

static void
gaicbs_remove(struct gaicb *req)
{
    struct gaicbs *request = requests;
    struct gaicbs *prev = NULL;

    if (!req) return;

    while (request) {
        if (request->gaicb == req) break;
        prev = request;
        request = request->next;
    }

    if (request) {
        if (prev) {
            prev->next = request->next;
        } else {
            requests = request->next;
        }
        xfree(request);
    }
}

static void
gaicbs_cancel_all(void)
{
    struct gaicbs *request = requests;
    struct gaicbs *tmp, *prev = NULL;
    int ret;

    while (request) {
        ret = gai_cancel(request->gaicb);
        if (ret == EAI_NOTCANCELED) {
            // continue to next request
            prev = request;
            request = request->next;
        } else {
            // remove the request from the list
            if (prev) {
                prev->next = request->next;
            } else {
                requests = request->next;
            }
            tmp = request;
            request = request->next;
            xfree(tmp);
        }
    }
}

static void
gaicbs_wait_all(void)
{
    struct gaicbs *request = requests;
    int size = 0;

    // count gaicbs
    while (request) {
        size++;
        request = request->next;
    }

    // create list to wait
    const struct gaicb *reqs[size];
    request = requests;
    for (int i=0; request; i++) {
        reqs[i] = request->gaicb;
        request = request->next;
    }

    // wait requests
    gai_suspend(reqs, size, NULL); // ignore result intentionally
}

#define MILLISECOND_IN_NANOSECONDS 1000000

/*  A mitigation for [Bug #17220].
    It cancels all outstanding requests and waits for ongoing requests.
    Then, it waits internal worker threads in getaddrinfo_a(3) to be finished. */
void
rb_getaddrinfo_a_before_exec(void)
{
    gaicbs_cancel_all();
    gaicbs_wait_all();

    /* wait worker threads in getaddrinfo_a(3) to be finished.
       they will finish after 1 second sleep. */
    struct timespec ts = {1, 500 * MILLISECOND_IN_NANOSECONDS};
    nanosleep(&ts, NULL);
}

int
rb_getaddrinfo_a(const char *node, const char *service,
               const struct addrinfo *hints,
               struct rb_addrinfo **res, struct timespec *timeout)
{
    struct addrinfo *ai;
    int ret;
    int allocated_by_malloc = 0;

    ret = numeric_getaddrinfo(node, service, hints, &ai);
    if (ret == 0)
        allocated_by_malloc = 1;
    else {
	struct gai_suspend_arg arg;
	struct gaicb *reqs[1];
	struct gaicb req;

	req.ar_name = node;
	req.ar_service = service;
	req.ar_request = hints;

	reqs[0] = &req;
	ret = getaddrinfo_a(GAI_NOWAIT, reqs, 1, NULL);
	if (ret) return ret;
        gaicbs_add(&req);

	arg.req = &req;
	arg.timeout = timeout;

	ret = (int)(VALUE)rb_thread_call_without_gvl(nogvl_gai_suspend, &arg, RUBY_UBF_IO, 0);
        gaicbs_remove(&req);
        if (ret && ret != EAI_ALLDONE) {
            /* EAI_ALLDONE indicates that the request already completed and gai_suspend was redundant */
            /* on Ubuntu 18.04 (or other systems), gai_suspend(3) returns EAI_SYSTEM/ENOENT on timeout */
            if (ret == EAI_SYSTEM && errno == ENOENT) {
                return EAI_AGAIN;
            } else {
                return ret;
            }
        }


	ret = gai_error(reqs[0]);
	ai = reqs[0]->ar_result;
    }

    if (ret == 0) {
        *res = (struct rb_addrinfo *)xmalloc(sizeof(struct rb_addrinfo));
        (*res)->allocated_by_malloc = allocated_by_malloc;
        (*res)->ai = ai;
    }
    return ret;
}
#endif

void
rb_freeaddrinfo(struct rb_addrinfo *ai)
{
    if (!ai->allocated_by_malloc)
        freeaddrinfo(ai->ai);
    else {
        struct addrinfo *ai1, *ai2;
        ai1 = ai->ai;
        while (ai1) {
            ai2 = ai1->ai_next;
            xfree(ai1->ai_addr);
            xfree(ai1);
            ai1 = ai2;
        }
    }
    xfree(ai);
}

#ifndef GETADDRINFO_EMU
struct getnameinfo_arg
{
    const struct sockaddr *sa;
    socklen_t salen;
    int flags;
    char *host;
    size_t hostlen;
    char *serv;
    size_t servlen;
};

static void *
nogvl_getnameinfo(void *arg)
{
    struct getnameinfo_arg *ptr = arg;
    return (void *)(VALUE)getnameinfo(ptr->sa, ptr->salen,
				      ptr->host, (socklen_t)ptr->hostlen,
				      ptr->serv, (socklen_t)ptr->servlen,
				      ptr->flags);
}
#endif

int
rb_getnameinfo(const struct sockaddr *sa, socklen_t salen,
           char *host, size_t hostlen,
           char *serv, size_t servlen, int flags)
{
#ifdef GETADDRINFO_EMU
    return getnameinfo(sa, salen, host, hostlen, serv, servlen, flags);
#else
    struct getnameinfo_arg arg;
    int ret;
    arg.sa = sa;
    arg.salen = salen;
    arg.host = host;
    arg.hostlen = hostlen;
    arg.serv = serv;
    arg.servlen = servlen;
    arg.flags = flags;
    ret = (int)(VALUE)rb_thread_call_without_gvl(nogvl_getnameinfo, &arg, RUBY_UBF_IO, 0);
    return ret;
#endif
}

static void
make_ipaddr0(struct sockaddr *addr, socklen_t addrlen, char *buf, size_t buflen)
{
    int error;

    error = rb_getnameinfo(addr, addrlen, buf, buflen, NULL, 0, NI_NUMERICHOST);
    if (error) {
        rsock_raise_socket_error("getnameinfo", error);
    }
}

VALUE
rsock_make_ipaddr(struct sockaddr *addr, socklen_t addrlen)
{
    char hbuf[1024];

    make_ipaddr0(addr, addrlen, hbuf, sizeof(hbuf));
    return rb_str_new2(hbuf);
}

static void
make_inetaddr(unsigned int host, char *buf, size_t buflen)
{
    struct sockaddr_in sin;

    INIT_SOCKADDR_IN(&sin, sizeof(sin));
    sin.sin_addr.s_addr = host;
    make_ipaddr0((struct sockaddr*)&sin, sizeof(sin), buf, buflen);
}

static int
str_is_number(const char *p)
{
    char *ep;

    if (!p || *p == '\0')
        return 0;
    ep = NULL;
    (void)STRTOUL(p, &ep, 10);
    if (ep && *ep == '\0')
        return 1;
    else
        return 0;
}

#define str_equal(ptr, len, name) \
    ((ptr)[0] == name[0] && \
     rb_strlen_lit(name) == (len) && memcmp(ptr, name, len) == 0)

static char*
host_str(VALUE host, char *hbuf, size_t hbuflen, int *flags_ptr)
{
    if (NIL_P(host)) {
        return NULL;
    }
    else if (rb_obj_is_kind_of(host, rb_cInteger)) {
        unsigned int i = NUM2UINT(host);

        make_inetaddr(htonl(i), hbuf, hbuflen);
        if (flags_ptr) *flags_ptr |= AI_NUMERICHOST;
        return hbuf;
    }
    else {
        const char *name;
        size_t len;

        StringValueCStr(host);
        RSTRING_GETMEM(host, name, len);
        if (!len || str_equal(name, len, "<any>")) {
            make_inetaddr(INADDR_ANY, hbuf, hbuflen);
            if (flags_ptr) *flags_ptr |= AI_NUMERICHOST;
        }
        else if (str_equal(name, len, "<broadcast>")) {
            make_inetaddr(INADDR_BROADCAST, hbuf, hbuflen);
            if (flags_ptr) *flags_ptr |= AI_NUMERICHOST;
        }
        else if (len >= hbuflen) {
            rb_raise(rb_eArgError, "hostname too long (%"PRIuSIZE")",
                     len);
        }
        else {
            memcpy(hbuf, name, len);
            hbuf[len] = '\0';
        }
        return hbuf;
    }
}

static char*
port_str(VALUE port, char *pbuf, size_t pbuflen, int *flags_ptr)
{
    if (NIL_P(port)) {
        return 0;
    }
    else if (FIXNUM_P(port)) {
        snprintf(pbuf, pbuflen, "%ld", FIX2LONG(port));
#ifdef AI_NUMERICSERV
        if (flags_ptr) *flags_ptr |= AI_NUMERICSERV;
#endif
        return pbuf;
    }
    else {
        const char *serv;
        size_t len;

        StringValueCStr(port);
        RSTRING_GETMEM(port, serv, len);
        if (len >= pbuflen) {
            rb_raise(rb_eArgError, "service name too long (%"PRIuSIZE")",
                     len);
        }
        memcpy(pbuf, serv, len);
        pbuf[len] = '\0';
        return pbuf;
    }
}

struct rb_addrinfo*
rsock_getaddrinfo(VALUE host, VALUE port, struct addrinfo *hints, int socktype_hack)
{
    struct rb_addrinfo* res = NULL;
    char *hostp, *portp;
    int error;
    char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];
    int additional_flags = 0;

    hostp = host_str(host, hbuf, sizeof(hbuf), &additional_flags);
    portp = port_str(port, pbuf, sizeof(pbuf), &additional_flags);

    if (socktype_hack && hints->ai_socktype == 0 && str_is_number(portp)) {
        hints->ai_socktype = SOCK_DGRAM;
    }
    hints->ai_flags |= additional_flags;

    error = rb_getaddrinfo(hostp, portp, hints, &res);
    if (error) {
        if (hostp && hostp[strlen(hostp)-1] == '\n') {
            rb_raise(rb_eSocket, "newline at the end of hostname");
        }
        rsock_raise_socket_error("getaddrinfo", error);
    }

    return res;
}

#ifdef HAVE_GETADDRINFO_A
struct rb_addrinfo*
rsock_getaddrinfo_a(VALUE host, VALUE port, struct addrinfo *hints, int socktype_hack, VALUE timeout)
{
    struct rb_addrinfo* res = NULL;
    char *hostp, *portp;
    int error;
    char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];
    int additional_flags = 0;

    hostp = host_str(host, hbuf, sizeof(hbuf), &additional_flags);
    portp = port_str(port, pbuf, sizeof(pbuf), &additional_flags);

    if (socktype_hack && hints->ai_socktype == 0 && str_is_number(portp)) {
       hints->ai_socktype = SOCK_DGRAM;
    }
    hints->ai_flags |= additional_flags;

    if (NIL_P(timeout)) {
        error = rb_getaddrinfo_a(hostp, portp, hints, &res, (struct timespec *)NULL);
    } else {
        struct timespec _timeout = rb_time_timespec_interval(timeout);
        error = rb_getaddrinfo_a(hostp, portp, hints, &res, &_timeout);
    }

    if (error) {
        if (hostp && hostp[strlen(hostp)-1] == '\n') {
            rb_raise(rb_eSocket, "newline at the end of hostname");
        }
        rsock_raise_socket_error("getaddrinfo_a", error);
    }

    return res;
}
#endif

int
rsock_fd_family(int fd)
{
    struct sockaddr sa = { 0 };
    socklen_t sa_len = sizeof(sa);

    if (fd < 0 || getsockname(fd, &sa, &sa_len) != 0 ||
        (size_t)sa_len < offsetof(struct sockaddr, sa_family) + sizeof(sa.sa_family)) {
	return AF_UNSPEC;
    }
    return sa.sa_family;
}

struct rb_addrinfo*
rsock_addrinfo(VALUE host, VALUE port, int family, int socktype, int flags)
{
    struct addrinfo hints;

    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = family;
    hints.ai_socktype = socktype;
    hints.ai_flags = flags;
    return rsock_getaddrinfo(host, port, &hints, 1);
}

#ifdef HAVE_GETADDRINFO_A
struct rb_addrinfo*
rsock_addrinfo_a(VALUE host, VALUE port, int family, int socktype, int flags, VALUE timeout)
{
    struct addrinfo hints;

    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = family;
    hints.ai_socktype = socktype;
    hints.ai_flags = flags;
    return rsock_getaddrinfo_a(host, port, &hints, 1, timeout);
}
#endif

VALUE
rsock_ipaddr(struct sockaddr *sockaddr, socklen_t sockaddrlen, int norevlookup)
{
    VALUE family, port, addr1, addr2;
    VALUE ary;
    int error;
    char hbuf[1024], pbuf[1024];
    ID id;

    id = rsock_intern_family(sockaddr->sa_family);
    if (id) {
        family = rb_str_dup(rb_id2str(id));
    }
    else {
        sprintf(pbuf, "unknown:%d", sockaddr->sa_family);
        family = rb_str_new2(pbuf);
    }

    addr1 = Qnil;
    if (!norevlookup) {
        error = rb_getnameinfo(sockaddr, sockaddrlen, hbuf, sizeof(hbuf),
                               NULL, 0, 0);
        if (! error) {
            addr1 = rb_str_new2(hbuf);
        }
    }
    error = rb_getnameinfo(sockaddr, sockaddrlen, hbuf, sizeof(hbuf),
                           pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV);
    if (error) {
        rsock_raise_socket_error("getnameinfo", error);
    }
    addr2 = rb_str_new2(hbuf);
    if (addr1 == Qnil) {
        addr1 = addr2;
    }
    port = INT2FIX(atoi(pbuf));
    ary = rb_ary_new3(4, family, port, addr1, addr2);

    return ary;
}

#ifdef HAVE_SYS_UN_H
static long
unixsocket_len(const struct sockaddr_un *su, socklen_t socklen)
{
    const char *s = su->sun_path, *e = (const char*)su + socklen;
    while (s < e && *(e-1) == '\0')
        e--;
    return e - s;
}

VALUE
rsock_unixpath_str(struct sockaddr_un *sockaddr, socklen_t len)
{
    long n = unixsocket_len(sockaddr, len);
    if (n >= 0)
        return rb_str_new(sockaddr->sun_path, n);
    else
        return rb_str_new2("");
}

VALUE
rsock_unixaddr(struct sockaddr_un *sockaddr, socklen_t len)
{
    return rb_assoc_new(rb_str_new2("AF_UNIX"),
                        rsock_unixpath_str(sockaddr, len));
}

socklen_t
rsock_unix_sockaddr_len(VALUE path)
{
#ifdef __linux__
    if (RSTRING_LEN(path) == 0) {
	/* autobind; see unix(7) for details. */
	return (socklen_t) sizeof(sa_family_t);
    }
    else if (RSTRING_PTR(path)[0] == '\0') {
	/* abstract namespace; see unix(7) for details. */
        if (SOCKLEN_MAX - offsetof(struct sockaddr_un, sun_path) < (size_t)RSTRING_LEN(path))
            rb_raise(rb_eArgError, "Linux abstract socket too long");
	return (socklen_t) offsetof(struct sockaddr_un, sun_path) +
	    RSTRING_SOCKLEN(path);
    }
    else {
#endif
	return (socklen_t) sizeof(struct sockaddr_un);
#ifdef __linux__
    }
#endif
}
#endif

struct hostent_arg {
    VALUE host;
    struct rb_addrinfo* addr;
    VALUE (*ipaddr)(struct sockaddr*, socklen_t);
};

static VALUE
make_hostent_internal(VALUE v)
{
    struct hostent_arg *arg = (void *)v;
    VALUE host = arg->host;
    struct addrinfo* addr = arg->addr->ai;
    VALUE (*ipaddr)(struct sockaddr*, socklen_t) = arg->ipaddr;

    struct addrinfo *ai;
    struct hostent *h;
    VALUE ary, names;
    char **pch;
    const char* hostp;
    char hbuf[NI_MAXHOST];

    ary = rb_ary_new();
    if (addr->ai_canonname) {
        hostp = addr->ai_canonname;
    }
    else {
        hostp = host_str(host, hbuf, sizeof(hbuf), NULL);
    }
    rb_ary_push(ary, rb_str_new2(hostp));

    if (addr->ai_canonname && strlen(addr->ai_canonname) < NI_MAXHOST &&
	(h = gethostbyname(addr->ai_canonname))) {
        names = rb_ary_new();
        if (h->h_aliases != NULL) {
            for (pch = h->h_aliases; *pch; pch++) {
                rb_ary_push(names, rb_str_new2(*pch));
            }
        }
    }
    else {
        names = rb_ary_new2(0);
    }
    rb_ary_push(ary, names);
    rb_ary_push(ary, INT2NUM(addr->ai_family));
    for (ai = addr; ai; ai = ai->ai_next) {
        rb_ary_push(ary, (*ipaddr)(ai->ai_addr, ai->ai_addrlen));
    }

    return ary;
}

VALUE
rsock_freeaddrinfo(VALUE arg)
{
    struct rb_addrinfo *addr = (struct rb_addrinfo *)arg;
    rb_freeaddrinfo(addr);
    return Qnil;
}

VALUE
rsock_make_hostent(VALUE host, struct rb_addrinfo *addr, VALUE (*ipaddr)(struct sockaddr *, socklen_t))
{
    struct hostent_arg arg;

    arg.host = host;
    arg.addr = addr;
    arg.ipaddr = ipaddr;
    return rb_ensure(make_hostent_internal, (VALUE)&arg,
                     rsock_freeaddrinfo, (VALUE)addr);
}

typedef struct {
    VALUE inspectname;
    VALUE canonname;
    int pfamily;
    int socktype;
    int protocol;
    socklen_t sockaddr_len;
    union_sockaddr addr;
} rb_addrinfo_t;

static void
addrinfo_mark(void *ptr)
{
    rb_addrinfo_t *rai = ptr;
    rb_gc_mark(rai->inspectname);
    rb_gc_mark(rai->canonname);
}

#define addrinfo_free RUBY_TYPED_DEFAULT_FREE

static size_t
addrinfo_memsize(const void *ptr)
{
    return sizeof(rb_addrinfo_t);
}

static const rb_data_type_t addrinfo_type = {
    "socket/addrinfo",
    {addrinfo_mark, addrinfo_free, addrinfo_memsize,},
};

static VALUE
addrinfo_s_allocate(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &addrinfo_type, 0);
}

#define IS_ADDRINFO(obj) rb_typeddata_is_kind_of((obj), &addrinfo_type)
static inline rb_addrinfo_t *
check_addrinfo(VALUE self)
{
    return rb_check_typeddata(self, &addrinfo_type);
}

static rb_addrinfo_t *
get_addrinfo(VALUE self)
{
    rb_addrinfo_t *rai = check_addrinfo(self);

    if (!rai) {
        rb_raise(rb_eTypeError, "uninitialized socket address");
    }
    return rai;
}


static rb_addrinfo_t *
alloc_addrinfo(void)
{
    rb_addrinfo_t *rai = ZALLOC(rb_addrinfo_t);
    rai->inspectname = Qnil;
    rai->canonname = Qnil;
    return rai;
}

static void
init_addrinfo(rb_addrinfo_t *rai, struct sockaddr *sa, socklen_t len,
              int pfamily, int socktype, int protocol,
              VALUE canonname, VALUE inspectname)
{
    if ((socklen_t)sizeof(rai->addr) < len)
        rb_raise(rb_eArgError, "sockaddr string too big");
    memcpy((void *)&rai->addr, (void *)sa, len);
    rai->sockaddr_len = len;

    rai->pfamily = pfamily;
    rai->socktype = socktype;
    rai->protocol = protocol;
    rai->canonname = canonname;
    rai->inspectname = inspectname;
}

VALUE
rsock_addrinfo_new(struct sockaddr *addr, socklen_t len,
                   int family, int socktype, int protocol,
                   VALUE canonname, VALUE inspectname)
{
    VALUE a;
    rb_addrinfo_t *rai;

    a = addrinfo_s_allocate(rb_cAddrinfo);
    DATA_PTR(a) = rai = alloc_addrinfo();
    init_addrinfo(rai, addr, len, family, socktype, protocol, canonname, inspectname);
    return a;
}

static struct rb_addrinfo *
call_getaddrinfo(VALUE node, VALUE service,
                 VALUE family, VALUE socktype, VALUE protocol, VALUE flags,
                 int socktype_hack, VALUE timeout)
{
    struct addrinfo hints;
    struct rb_addrinfo *res;

    MEMZERO(&hints, struct addrinfo, 1);
    hints.ai_family = NIL_P(family) ? PF_UNSPEC : rsock_family_arg(family);

    if (!NIL_P(socktype)) {
	hints.ai_socktype = rsock_socktype_arg(socktype);
    }
    if (!NIL_P(protocol)) {
	hints.ai_protocol = NUM2INT(protocol);
    }
    if (!NIL_P(flags)) {
	hints.ai_flags = NUM2INT(flags);
    }

#ifdef HAVE_GETADDRINFO_A
    res = rsock_getaddrinfo_a(node, service, &hints, socktype_hack, timeout);
#else
    res = rsock_getaddrinfo(node, service, &hints, socktype_hack);
#endif

    if (res == NULL)
	rb_raise(rb_eSocket, "host not found");
    return res;
}

static VALUE make_inspectname(VALUE node, VALUE service, struct addrinfo *res);

static void
init_addrinfo_getaddrinfo(rb_addrinfo_t *rai, VALUE node, VALUE service,
                          VALUE family, VALUE socktype, VALUE protocol, VALUE flags,
                          VALUE inspectnode, VALUE inspectservice)
{
    struct rb_addrinfo *res = call_getaddrinfo(node, service, family, socktype, protocol, flags, 1, Qnil);
    VALUE canonname;
    VALUE inspectname = rb_str_equal(node, inspectnode) ? Qnil : make_inspectname(inspectnode, inspectservice, res->ai);

    canonname = Qnil;
    if (res->ai->ai_canonname) {
        canonname = rb_str_new_cstr(res->ai->ai_canonname);
        OBJ_FREEZE(canonname);
    }

    init_addrinfo(rai, res->ai->ai_addr, res->ai->ai_addrlen,
                  NUM2INT(family), NUM2INT(socktype), NUM2INT(protocol),
                  canonname, inspectname);

    rb_freeaddrinfo(res);
}

static VALUE
make_inspectname(VALUE node, VALUE service, struct addrinfo *res)
{
    VALUE inspectname = Qnil;

    if (res) {
        /* drop redundant information which also shown in address:port part. */
        char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];
        int ret;
        ret = rb_getnameinfo(res->ai_addr, res->ai_addrlen, hbuf,
                             sizeof(hbuf), pbuf, sizeof(pbuf),
                             NI_NUMERICHOST|NI_NUMERICSERV);
        if (ret == 0) {
            if (RB_TYPE_P(node, T_STRING) && strcmp(hbuf, RSTRING_PTR(node)) == 0)
                node = Qnil;
            if (RB_TYPE_P(service, T_STRING) && strcmp(pbuf, RSTRING_PTR(service)) == 0)
                service = Qnil;
            else if (RB_TYPE_P(service, T_FIXNUM) && atoi(pbuf) == FIX2INT(service))
                service = Qnil;
        }
    }

    if (RB_TYPE_P(node, T_STRING)) {
        inspectname = rb_str_dup(node);
    }
    if (RB_TYPE_P(service, T_STRING)) {
        if (NIL_P(inspectname))
            inspectname = rb_sprintf(":%s", StringValueCStr(service));
        else
            rb_str_catf(inspectname, ":%s", StringValueCStr(service));
    }
    else if (RB_TYPE_P(service, T_FIXNUM) && FIX2INT(service) != 0)
    {
        if (NIL_P(inspectname))
            inspectname = rb_sprintf(":%d", FIX2INT(service));
        else
            rb_str_catf(inspectname, ":%d", FIX2INT(service));
    }
    if (!NIL_P(inspectname)) {
        OBJ_FREEZE(inspectname);
    }
    return inspectname;
}

static VALUE
addrinfo_firstonly_new(VALUE node, VALUE service, VALUE family, VALUE socktype, VALUE protocol, VALUE flags)
{
    VALUE ret;
    VALUE canonname;
    VALUE inspectname;

    struct rb_addrinfo *res = call_getaddrinfo(node, service, family, socktype, protocol, flags, 0, Qnil);

    inspectname = make_inspectname(node, service, res->ai);

    canonname = Qnil;
    if (res->ai->ai_canonname) {
        canonname = rb_str_new_cstr(res->ai->ai_canonname);
        OBJ_FREEZE(canonname);
    }

    ret = rsock_addrinfo_new(res->ai->ai_addr, res->ai->ai_addrlen,
                             res->ai->ai_family, res->ai->ai_socktype,
                             res->ai->ai_protocol,
                             canonname, inspectname);

    rb_freeaddrinfo(res);
    return ret;
}

static VALUE
addrinfo_list_new(VALUE node, VALUE service, VALUE family, VALUE socktype, VALUE protocol, VALUE flags, VALUE timeout)
{
    VALUE ret;
    struct addrinfo *r;
    VALUE inspectname;

    struct rb_addrinfo *res = call_getaddrinfo(node, service, family, socktype, protocol, flags, 0, timeout);

    inspectname = make_inspectname(node, service, res->ai);

    ret = rb_ary_new();
    for (r = res->ai; r; r = r->ai_next) {
        VALUE addr;
        VALUE canonname = Qnil;

        if (r->ai_canonname) {
            canonname = rb_str_new_cstr(r->ai_canonname);
            OBJ_FREEZE(canonname);
        }

        addr = rsock_addrinfo_new(r->ai_addr, r->ai_addrlen,
                                  r->ai_family, r->ai_socktype, r->ai_protocol,
                                  canonname, inspectname);

        rb_ary_push(ret, addr);
    }

    rb_freeaddrinfo(res);
    return ret;
}


#ifdef HAVE_SYS_UN_H
static void
init_unix_addrinfo(rb_addrinfo_t *rai, VALUE path, int socktype)
{
    struct sockaddr_un un;
    socklen_t len;

    StringValue(path);

    if (sizeof(un.sun_path) < (size_t)RSTRING_LEN(path))
        rb_raise(rb_eArgError,
            "too long unix socket path (%"PRIuSIZE" bytes given but %"PRIuSIZE" bytes max)",
            (size_t)RSTRING_LEN(path), sizeof(un.sun_path));

    INIT_SOCKADDR_UN(&un, sizeof(struct sockaddr_un));
    memcpy((void*)&un.sun_path, RSTRING_PTR(path), RSTRING_LEN(path));

    len = rsock_unix_sockaddr_len(path);
    init_addrinfo(rai, (struct sockaddr *)&un, len,
		  PF_UNIX, socktype, 0, Qnil, Qnil);
}

static long
rai_unixsocket_len(const rb_addrinfo_t *rai)
{
    return unixsocket_len(&rai->addr.un, rai->sockaddr_len);
}
#endif

/*
 * call-seq:
 *   Addrinfo.new(sockaddr)                             => addrinfo
 *   Addrinfo.new(sockaddr, family)                     => addrinfo
 *   Addrinfo.new(sockaddr, family, socktype)           => addrinfo
 *   Addrinfo.new(sockaddr, family, socktype, protocol) => addrinfo
 *
 * returns a new instance of Addrinfo.
 * The instance contains sockaddr, family, socktype, protocol.
 * sockaddr means struct sockaddr which can be used for connect(2), etc.
 * family, socktype and protocol are integers which is used for arguments of socket(2).
 *
 * sockaddr is specified as an array or a string.
 * The array should be compatible to the value of IPSocket#addr or UNIXSocket#addr.
 * The string should be struct sockaddr as generated by
 * Socket.sockaddr_in or Socket.unpack_sockaddr_un.
 *
 * sockaddr examples:
 * - ["AF_INET", 46102, "localhost.localdomain", "127.0.0.1"]
 * - ["AF_INET6", 42304, "ip6-localhost", "::1"]
 * - ["AF_UNIX", "/tmp/sock"]
 * - Socket.sockaddr_in("smtp", "2001:DB8::1")
 * - Socket.sockaddr_in(80, "172.18.22.42")
 * - Socket.sockaddr_in(80, "www.ruby-lang.org")
 * - Socket.sockaddr_un("/tmp/sock")
 *
 * In an AF_INET/AF_INET6 sockaddr array, the 4th element,
 * numeric IP address, is used to construct socket address in the Addrinfo instance.
 * If the 3rd element, textual host name, is non-nil, it is also recorded but used only for Addrinfo#inspect.
 *
 * family is specified as an integer to specify the protocol family such as Socket::PF_INET.
 * It can be a symbol or a string which is the constant name
 * with or without PF_ prefix such as :INET, :INET6, :UNIX, "PF_INET", etc.
 * If omitted, PF_UNSPEC is assumed.
 *
 * socktype is specified as an integer to specify the socket type such as Socket::SOCK_STREAM.
 * It can be a symbol or a string which is the constant name
 * with or without SOCK_ prefix such as :STREAM, :DGRAM, :RAW, "SOCK_STREAM", etc.
 * If omitted, 0 is assumed.
 *
 * protocol is specified as an integer to specify the protocol such as Socket::IPPROTO_TCP.
 * It must be an integer, unlike family and socktype.
 * If omitted, 0 is assumed.
 * Note that 0 is reasonable value for most protocols, except raw socket.
 *
 */
static VALUE
addrinfo_initialize(int argc, VALUE *argv, VALUE self)
{
    rb_addrinfo_t *rai;
    VALUE sockaddr_arg, sockaddr_ary, pfamily, socktype, protocol;
    int i_pfamily, i_socktype, i_protocol;
    struct sockaddr *sockaddr_ptr;
    socklen_t sockaddr_len;
    VALUE canonname = Qnil, inspectname = Qnil;

    if (check_addrinfo(self))
        rb_raise(rb_eTypeError, "already initialized socket address");
    DATA_PTR(self) = rai = alloc_addrinfo();

    rb_scan_args(argc, argv, "13", &sockaddr_arg, &pfamily, &socktype, &protocol);

    i_pfamily = NIL_P(pfamily) ? PF_UNSPEC : rsock_family_arg(pfamily);
    i_socktype = NIL_P(socktype) ? 0 : rsock_socktype_arg(socktype);
    i_protocol = NIL_P(protocol) ? 0 : NUM2INT(protocol);

    sockaddr_ary = rb_check_array_type(sockaddr_arg);
    if (!NIL_P(sockaddr_ary)) {
        VALUE afamily = rb_ary_entry(sockaddr_ary, 0);
        int af;
        StringValue(afamily);
        if (rsock_family_to_int(RSTRING_PTR(afamily), RSTRING_LEN(afamily), &af) == -1)
	    rb_raise(rb_eSocket, "unknown address family: %s", StringValueCStr(afamily));
        switch (af) {
          case AF_INET: /* ["AF_INET", 46102, "localhost.localdomain", "127.0.0.1"] */
#ifdef INET6
          case AF_INET6: /* ["AF_INET6", 42304, "ip6-localhost", "::1"] */
#endif
          {
            VALUE service = rb_ary_entry(sockaddr_ary, 1);
            VALUE nodename = rb_ary_entry(sockaddr_ary, 2);
            VALUE numericnode = rb_ary_entry(sockaddr_ary, 3);
            int flags;

            service = INT2NUM(NUM2INT(service));
            if (!NIL_P(nodename))
                StringValue(nodename);
            StringValue(numericnode);
            flags = AI_NUMERICHOST;
#ifdef AI_NUMERICSERV
            flags |= AI_NUMERICSERV;
#endif

            init_addrinfo_getaddrinfo(rai, numericnode, service,
                    INT2NUM(i_pfamily ? i_pfamily : af), INT2NUM(i_socktype), INT2NUM(i_protocol),
                    INT2NUM(flags),
                    nodename, service);
            break;
          }

#ifdef HAVE_SYS_UN_H
          case AF_UNIX: /* ["AF_UNIX", "/tmp/sock"] */
          {
            VALUE path = rb_ary_entry(sockaddr_ary, 1);
            StringValue(path);
            init_unix_addrinfo(rai, path, SOCK_STREAM);
            break;
          }
#endif

          default:
            rb_raise(rb_eSocket, "unexpected address family");
        }
    }
    else {
        StringValue(sockaddr_arg);
        sockaddr_ptr = (struct sockaddr *)RSTRING_PTR(sockaddr_arg);
        sockaddr_len = RSTRING_SOCKLEN(sockaddr_arg);
        init_addrinfo(rai, sockaddr_ptr, sockaddr_len,
                      i_pfamily, i_socktype, i_protocol,
                      canonname, inspectname);
    }

    return self;
}

static int
get_afamily(const struct sockaddr *addr, socklen_t len)
{
    if ((socklen_t)((const char*)&addr->sa_family + sizeof(addr->sa_family) - (char*)addr) <= len)
        return addr->sa_family;
    else
        return AF_UNSPEC;
}

static int
ai_get_afamily(const rb_addrinfo_t *rai)
{
    return get_afamily(&rai->addr.addr, rai->sockaddr_len);
}

static VALUE
inspect_sockaddr(VALUE addrinfo, VALUE ret)
{
    rb_addrinfo_t *rai = get_addrinfo(addrinfo);
    union_sockaddr *sockaddr = &rai->addr;
    socklen_t socklen = rai->sockaddr_len;
    return rsock_inspect_sockaddr((struct sockaddr *)sockaddr, socklen, ret);
}

VALUE
rsock_inspect_sockaddr(struct sockaddr *sockaddr_arg, socklen_t socklen, VALUE ret)
{
    union_sockaddr *sockaddr = (union_sockaddr *)sockaddr_arg;
    if (socklen == 0) {
        rb_str_cat2(ret, "empty-sockaddr");
    }
    else if ((long)socklen < ((char*)&sockaddr->addr.sa_family + sizeof(sockaddr->addr.sa_family)) - (char*)sockaddr)
        rb_str_cat2(ret, "too-short-sockaddr");
    else {
        switch (sockaddr->addr.sa_family) {
          case AF_UNSPEC:
	  {
	    rb_str_cat2(ret, "UNSPEC");
            break;
	  }

          case AF_INET:
          {
            struct sockaddr_in *addr;
            int port;
	    addr = &sockaddr->in;
	    if ((socklen_t)(((char*)&addr->sin_addr)-(char*)addr+0+1) <= socklen)
		rb_str_catf(ret, "%d", ((unsigned char*)&addr->sin_addr)[0]);
	    else
		rb_str_cat2(ret, "?");
	    if ((socklen_t)(((char*)&addr->sin_addr)-(char*)addr+1+1) <= socklen)
		rb_str_catf(ret, ".%d", ((unsigned char*)&addr->sin_addr)[1]);
	    else
		rb_str_cat2(ret, ".?");
	    if ((socklen_t)(((char*)&addr->sin_addr)-(char*)addr+2+1) <= socklen)
		rb_str_catf(ret, ".%d", ((unsigned char*)&addr->sin_addr)[2]);
	    else
		rb_str_cat2(ret, ".?");
	    if ((socklen_t)(((char*)&addr->sin_addr)-(char*)addr+3+1) <= socklen)
		rb_str_catf(ret, ".%d", ((unsigned char*)&addr->sin_addr)[3]);
	    else
		rb_str_cat2(ret, ".?");

	    if ((socklen_t)(((char*)&addr->sin_port)-(char*)addr+(int)sizeof(addr->sin_port)) < socklen) {
		port = ntohs(addr->sin_port);
		if (port)
		    rb_str_catf(ret, ":%d", port);
	    }
	    else {
		rb_str_cat2(ret, ":?");
	    }
	    if ((socklen_t)sizeof(struct sockaddr_in) != socklen)
		rb_str_catf(ret, " (%d bytes for %d bytes sockaddr_in)",
		  (int)socklen,
		  (int)sizeof(struct sockaddr_in));
            break;
          }

#ifdef AF_INET6
          case AF_INET6:
          {
            struct sockaddr_in6 *addr;
            char hbuf[1024];
            int port;
            int error;
            if (socklen < (socklen_t)sizeof(struct sockaddr_in6)) {
                rb_str_catf(ret, "too-short-AF_INET6-sockaddr %d bytes", (int)socklen);
            }
            else {
                addr = &sockaddr->in6;
                /* use getnameinfo for scope_id.
                 * RFC 4007: IPv6 Scoped Address Architecture
                 * draft-ietf-ipv6-scope-api-00.txt: Scoped Address Extensions to the IPv6 Basic Socket API
                 */
                error = getnameinfo(&sockaddr->addr, socklen,
                                    hbuf, (socklen_t)sizeof(hbuf), NULL, 0,
                                    NI_NUMERICHOST|NI_NUMERICSERV);
                if (error) {
                    rsock_raise_socket_error("getnameinfo", error);
                }
                if (addr->sin6_port == 0) {
                    rb_str_cat2(ret, hbuf);
                }
                else {
                    port = ntohs(addr->sin6_port);
                    rb_str_catf(ret, "[%s]:%d", hbuf, port);
                }
                if ((socklen_t)sizeof(struct sockaddr_in6) < socklen)
                    rb_str_catf(ret, "(sockaddr %d bytes too long)", (int)(socklen - sizeof(struct sockaddr_in6)));
            }
            break;
          }
#endif

#ifdef HAVE_SYS_UN_H
          case AF_UNIX:
          {
            struct sockaddr_un *addr = &sockaddr->un;
            char *p, *s, *e;
            long len = unixsocket_len(addr, socklen);
            s = addr->sun_path;
            if (len < 0)
                rb_str_cat2(ret, "too-short-AF_UNIX-sockaddr");
            else if (len == 0)
                rb_str_cat2(ret, "empty-path-AF_UNIX-sockaddr");
            else {
                int printable_only = 1;
                e = s + len;
                p = s;
                while (p < e) {
                    printable_only = printable_only && ISPRINT(*p) && !ISSPACE(*p);
                    p++;
                }
                if (printable_only) { /* only printable, no space */
                    if (s[0] != '/') /* relative path */
                        rb_str_cat2(ret, "UNIX ");
                    rb_str_cat(ret, s, p - s);
                }
                else {
                    rb_str_cat2(ret, "UNIX");
                    while (s < e)
                        rb_str_catf(ret, ":%02x", (unsigned char)*s++);
                }
            }
            break;
          }
#endif

#if defined(AF_PACKET) && defined(__linux__)
          /* GNU/Linux */
          case AF_PACKET:
          {
            struct sockaddr_ll *addr;
            const char *sep = "[";
#define CATSEP do { rb_str_cat2(ret, sep); sep = " "; } while (0);

            addr = (struct sockaddr_ll *)sockaddr;

            rb_str_cat2(ret, "PACKET");

            if (offsetof(struct sockaddr_ll, sll_protocol) + sizeof(addr->sll_protocol) <= (size_t)socklen) {
                CATSEP;
                rb_str_catf(ret, "protocol=%d", ntohs(addr->sll_protocol));
            }
            if (offsetof(struct sockaddr_ll, sll_ifindex) + sizeof(addr->sll_ifindex) <= (size_t)socklen) {
                char buf[IFNAMSIZ];
                CATSEP;
                if (if_indextoname(addr->sll_ifindex, buf) == NULL)
                    rb_str_catf(ret, "ifindex=%d", addr->sll_ifindex);
                else
                    rb_str_catf(ret, "%s", buf);
            }
            if (offsetof(struct sockaddr_ll, sll_hatype) + sizeof(addr->sll_hatype) <= (size_t)socklen) {
                CATSEP;
                rb_str_catf(ret, "hatype=%d", addr->sll_hatype);
            }
            if (offsetof(struct sockaddr_ll, sll_pkttype) + sizeof(addr->sll_pkttype) <= (size_t)socklen) {
                CATSEP;
                if (addr->sll_pkttype == PACKET_HOST)
                    rb_str_cat2(ret, "HOST");
                else if (addr->sll_pkttype == PACKET_BROADCAST)
                    rb_str_cat2(ret, "BROADCAST");
                else if (addr->sll_pkttype == PACKET_MULTICAST)
                    rb_str_cat2(ret, "MULTICAST");
                else if (addr->sll_pkttype == PACKET_OTHERHOST)
                    rb_str_cat2(ret, "OTHERHOST");
                else if (addr->sll_pkttype == PACKET_OUTGOING)
                    rb_str_cat2(ret, "OUTGOING");
                else
                    rb_str_catf(ret, "pkttype=%d", addr->sll_pkttype);
            }
            if (socklen != (socklen_t)(offsetof(struct sockaddr_ll, sll_addr) + addr->sll_halen)) {
                CATSEP;
                if (offsetof(struct sockaddr_ll, sll_halen) + sizeof(addr->sll_halen) <= (size_t)socklen) {
                    rb_str_catf(ret, "halen=%d", addr->sll_halen);
                }
            }
            if (offsetof(struct sockaddr_ll, sll_addr) < (size_t)socklen) {
                socklen_t len, i;
                CATSEP;
                rb_str_cat2(ret, "hwaddr");
                len = addr->sll_halen;
                if ((size_t)socklen < offsetof(struct sockaddr_ll, sll_addr) + len)
                    len = socklen - offsetof(struct sockaddr_ll, sll_addr);
                for (i = 0; i < len; i++) {
                    rb_str_cat2(ret, i == 0 ? "=" : ":");
                    rb_str_catf(ret, "%02x", addr->sll_addr[i]);
                }
            }

            if (socklen < (socklen_t)(offsetof(struct sockaddr_ll, sll_halen) + sizeof(addr->sll_halen)) ||
                (socklen_t)(offsetof(struct sockaddr_ll, sll_addr) + addr->sll_halen) != socklen) {
                CATSEP;
                rb_str_catf(ret, "(%d bytes for %d bytes sockaddr_ll)",
                    (int)socklen, (int)sizeof(struct sockaddr_ll));
            }

            rb_str_cat2(ret, "]");
#undef CATSEP

            break;
          }
#endif

#if defined(AF_LINK) && defined(HAVE_TYPE_STRUCT_SOCKADDR_DL)
	  /* AF_LINK is defined in 4.4BSD derivations since Net2.
	     link_ntoa is also defined at Net2.
             However Debian GNU/kFreeBSD defines AF_LINK but
             don't have link_ntoa.  */
          case AF_LINK:
	  {
	    /*
	     * Simple implementation using link_ntoa():
	     * This doesn't work on Debian GNU/kFreeBSD 6.0.7 (squeeze).
             * Also, the format is bit different.
	     *
	     * rb_str_catf(ret, "LINK %s", link_ntoa(&sockaddr->dl));
	     * break;
	     */
            struct sockaddr_dl *addr = &sockaddr->dl;
            char *np = NULL, *ap = NULL, *endp;
            int nlen = 0, alen = 0;
            int i, off;
            const char *sep = "[";
#define CATSEP do { rb_str_cat2(ret, sep); sep = " "; } while (0);

            rb_str_cat2(ret, "LINK");

            endp = ((char *)addr) + socklen;

            if (offsetof(struct sockaddr_dl, sdl_data) < socklen) {
                np = addr->sdl_data;
                nlen = addr->sdl_nlen;
                if (endp - np < nlen)
                    nlen = (int)(endp - np);
            }
            off = addr->sdl_nlen;

            if (offsetof(struct sockaddr_dl, sdl_data) + off < socklen) {
                ap = addr->sdl_data + off;
                alen = addr->sdl_alen;
                if (endp - ap < alen)
                    alen = (int)(endp - ap);
            }

	    CATSEP;
            if (np)
                rb_str_catf(ret, "%.*s", nlen, np);
            else
                rb_str_cat2(ret, "?");

            if (ap && 0 < alen) {
		CATSEP;
                for (i = 0; i < alen; i++)
                    rb_str_catf(ret, "%s%02x", i == 0 ? "" : ":", (unsigned char)ap[i]);
            }

            if (socklen < (socklen_t)(offsetof(struct sockaddr_dl, sdl_nlen) + sizeof(addr->sdl_nlen)) ||
                socklen < (socklen_t)(offsetof(struct sockaddr_dl, sdl_alen) + sizeof(addr->sdl_alen)) ||
                socklen < (socklen_t)(offsetof(struct sockaddr_dl, sdl_slen) + sizeof(addr->sdl_slen)) ||
                /* longer length is possible behavior because struct sockaddr_dl has "minimum work area, can be larger" as the last field.
                 * cf. Net2:/usr/src/sys/net/if_dl.h. */
                socklen < (socklen_t)(offsetof(struct sockaddr_dl, sdl_data) + addr->sdl_nlen + addr->sdl_alen + addr->sdl_slen)) {
		CATSEP;
                rb_str_catf(ret, "(%d bytes for %d bytes sockaddr_dl)",
                    (int)socklen, (int)sizeof(struct sockaddr_dl));
	    }

            rb_str_cat2(ret, "]");
#undef CATSEP
            break;
          }
#endif

          default:
          {
            ID id = rsock_intern_family(sockaddr->addr.sa_family);
            if (id == 0)
                rb_str_catf(ret, "unknown address family %d", sockaddr->addr.sa_family);
            else
                rb_str_catf(ret, "%s address format unknown", rb_id2name(id));
            break;
          }
        }
    }

    return ret;
}

/*
 * call-seq:
 *   addrinfo.inspect => string
 *
 * returns a string which shows addrinfo in human-readable form.
 *
 *   Addrinfo.tcp("localhost", 80).inspect #=> "#<Addrinfo: 127.0.0.1:80 TCP (localhost)>"
 *   Addrinfo.unix("/tmp/sock").inspect    #=> "#<Addrinfo: /tmp/sock SOCK_STREAM>"
 *
 */
static VALUE
addrinfo_inspect(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int internet_p;
    VALUE ret;

    ret = rb_sprintf("#<%s: ", rb_obj_classname(self));

    inspect_sockaddr(self, ret);

    if (rai->pfamily && ai_get_afamily(rai) != rai->pfamily) {
        ID id = rsock_intern_protocol_family(rai->pfamily);
        if (id)
            rb_str_catf(ret, " %s", rb_id2name(id));
        else
            rb_str_catf(ret, " PF_\?\?\?(%d)", rai->pfamily);
    }

    internet_p = rai->pfamily == PF_INET;
#ifdef INET6
    internet_p = internet_p || rai->pfamily == PF_INET6;
#endif
    if (internet_p && rai->socktype == SOCK_STREAM &&
        (rai->protocol == 0 || rai->protocol == IPPROTO_TCP)) {
        rb_str_cat2(ret, " TCP");
    }
    else if (internet_p && rai->socktype == SOCK_DGRAM &&
        (rai->protocol == 0 || rai->protocol == IPPROTO_UDP)) {
        rb_str_cat2(ret, " UDP");
    }
    else {
        if (rai->socktype) {
            ID id = rsock_intern_socktype(rai->socktype);
            if (id)
                rb_str_catf(ret, " %s", rb_id2name(id));
            else
                rb_str_catf(ret, " SOCK_\?\?\?(%d)", rai->socktype);
        }

        if (rai->protocol) {
            if (internet_p) {
                ID id = rsock_intern_ipproto(rai->protocol);
                if (id)
                    rb_str_catf(ret, " %s", rb_id2name(id));
                else
                    goto unknown_protocol;
            }
            else {
              unknown_protocol:
                rb_str_catf(ret, " UNKNOWN_PROTOCOL(%d)", rai->protocol);
            }
        }
    }

    if (!NIL_P(rai->canonname)) {
        VALUE name = rai->canonname;
        rb_str_catf(ret, " %s", StringValueCStr(name));
    }

    if (!NIL_P(rai->inspectname)) {
        VALUE name = rai->inspectname;
        rb_str_catf(ret, " (%s)", StringValueCStr(name));
    }

    rb_str_buf_cat2(ret, ">");
    return ret;
}

/*
 * call-seq:
 *   addrinfo.inspect_sockaddr => string
 *
 * returns a string which shows the sockaddr in _addrinfo_ with human-readable form.
 *
 *   Addrinfo.tcp("localhost", 80).inspect_sockaddr     #=> "127.0.0.1:80"
 *   Addrinfo.tcp("ip6-localhost", 80).inspect_sockaddr #=> "[::1]:80"
 *   Addrinfo.unix("/tmp/sock").inspect_sockaddr        #=> "/tmp/sock"
 *
 */
VALUE
rsock_addrinfo_inspect_sockaddr(VALUE self)
{
    return inspect_sockaddr(self, rb_str_new("", 0));
}

/* :nodoc: */
static VALUE
addrinfo_mdump(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    VALUE sockaddr, afamily, pfamily, socktype, protocol, canonname, inspectname;
    int afamily_int = ai_get_afamily(rai);
    ID id;

    id = rsock_intern_protocol_family(rai->pfamily);
    if (id == 0)
        rb_raise(rb_eSocket, "unknown protocol family: %d", rai->pfamily);
    pfamily = rb_id2str(id);

    if (rai->socktype == 0)
        socktype = INT2FIX(0);
    else {
        id = rsock_intern_socktype(rai->socktype);
        if (id == 0)
            rb_raise(rb_eSocket, "unknown socktype: %d", rai->socktype);
        socktype = rb_id2str(id);
    }

    if (rai->protocol == 0)
        protocol = INT2FIX(0);
    else if (IS_IP_FAMILY(afamily_int)) {
        id = rsock_intern_ipproto(rai->protocol);
        if (id == 0)
            rb_raise(rb_eSocket, "unknown IP protocol: %d", rai->protocol);
        protocol = rb_id2str(id);
    }
    else {
        rb_raise(rb_eSocket, "unknown protocol: %d", rai->protocol);
    }

    canonname = rai->canonname;

    inspectname = rai->inspectname;

    id = rsock_intern_family(afamily_int);
    if (id == 0)
        rb_raise(rb_eSocket, "unknown address family: %d", afamily_int);
    afamily = rb_id2str(id);

    switch(afamily_int) {
#ifdef HAVE_SYS_UN_H
      case AF_UNIX:
      {
        sockaddr = rb_str_new(rai->addr.un.sun_path, rai_unixsocket_len(rai));
        break;
      }
#endif

      default:
      {
        char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];
        int error;
        error = getnameinfo(&rai->addr.addr, rai->sockaddr_len,
                            hbuf, (socklen_t)sizeof(hbuf), pbuf, (socklen_t)sizeof(pbuf),
                            NI_NUMERICHOST|NI_NUMERICSERV);
        if (error) {
            rsock_raise_socket_error("getnameinfo", error);
        }
        sockaddr = rb_assoc_new(rb_str_new_cstr(hbuf), rb_str_new_cstr(pbuf));
        break;
      }
    }

    return rb_ary_new3(7, afamily, sockaddr, pfamily, socktype, protocol, canonname, inspectname);
}

/* :nodoc: */
static VALUE
addrinfo_mload(VALUE self, VALUE ary)
{
    VALUE v;
    VALUE canonname, inspectname;
    int afamily, pfamily, socktype, protocol;
    union_sockaddr ss;
    socklen_t len;
    rb_addrinfo_t *rai;

    if (check_addrinfo(self))
        rb_raise(rb_eTypeError, "already initialized socket address");

    ary = rb_convert_type(ary, T_ARRAY, "Array", "to_ary");

    v = rb_ary_entry(ary, 0);
    StringValue(v);
    if (rsock_family_to_int(RSTRING_PTR(v), RSTRING_LEN(v), &afamily) == -1)
        rb_raise(rb_eTypeError, "unexpected address family");

    v = rb_ary_entry(ary, 2);
    StringValue(v);
    if (rsock_family_to_int(RSTRING_PTR(v), RSTRING_LEN(v), &pfamily) == -1)
        rb_raise(rb_eTypeError, "unexpected protocol family");

    v = rb_ary_entry(ary, 3);
    if (v == INT2FIX(0))
        socktype = 0;
    else {
        StringValue(v);
        if (rsock_socktype_to_int(RSTRING_PTR(v), RSTRING_LEN(v), &socktype) == -1)
            rb_raise(rb_eTypeError, "unexpected socktype");
    }

    v = rb_ary_entry(ary, 4);
    if (v == INT2FIX(0))
        protocol = 0;
    else {
        StringValue(v);
        if (IS_IP_FAMILY(afamily)) {
            if (rsock_ipproto_to_int(RSTRING_PTR(v), RSTRING_LEN(v), &protocol) == -1)
                rb_raise(rb_eTypeError, "unexpected protocol");
        }
        else {
            rb_raise(rb_eTypeError, "unexpected protocol");
        }
    }

    v = rb_ary_entry(ary, 5);
    if (NIL_P(v))
        canonname = Qnil;
    else {
        StringValue(v);
        canonname = v;
    }

    v = rb_ary_entry(ary, 6);
    if (NIL_P(v))
        inspectname = Qnil;
    else {
        StringValue(v);
        inspectname = v;
    }

    v = rb_ary_entry(ary, 1);
    switch(afamily) {
#ifdef HAVE_SYS_UN_H
      case AF_UNIX:
      {
        struct sockaddr_un uaddr;
        INIT_SOCKADDR_UN(&uaddr, sizeof(struct sockaddr_un));

        StringValue(v);
        if (sizeof(uaddr.sun_path) < (size_t)RSTRING_LEN(v))
            rb_raise(rb_eSocket,
                "too long AF_UNIX path (%"PRIuSIZE" bytes given but %"PRIuSIZE" bytes max)",
                (size_t)RSTRING_LEN(v), sizeof(uaddr.sun_path));
        memcpy(uaddr.sun_path, RSTRING_PTR(v), RSTRING_LEN(v));
        len = (socklen_t)sizeof(uaddr);
        memcpy(&ss, &uaddr, len);
        break;
      }
#endif

      default:
      {
        VALUE pair = rb_convert_type(v, T_ARRAY, "Array", "to_ary");
        struct rb_addrinfo *res;
        int flags = AI_NUMERICHOST;
#ifdef AI_NUMERICSERV
        flags |= AI_NUMERICSERV;
#endif
        res = call_getaddrinfo(rb_ary_entry(pair, 0), rb_ary_entry(pair, 1),
                               INT2NUM(pfamily), INT2NUM(socktype), INT2NUM(protocol),
                               INT2NUM(flags), 1, Qnil);

        len = res->ai->ai_addrlen;
        memcpy(&ss, res->ai->ai_addr, res->ai->ai_addrlen);
        rb_freeaddrinfo(res);
        break;
      }
    }

    DATA_PTR(self) = rai = alloc_addrinfo();
    init_addrinfo(rai, &ss.addr, len,
                  pfamily, socktype, protocol,
                  canonname, inspectname);
    return self;
}

/*
 * call-seq:
 *   addrinfo.afamily => integer
 *
 * returns the address family as an integer.
 *
 *   Addrinfo.tcp("localhost", 80).afamily == Socket::AF_INET #=> true
 *
 */
static VALUE
addrinfo_afamily(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return INT2NUM(ai_get_afamily(rai));
}

/*
 * call-seq:
 *   addrinfo.pfamily => integer
 *
 * returns the protocol family as an integer.
 *
 *   Addrinfo.tcp("localhost", 80).pfamily == Socket::PF_INET #=> true
 *
 */
static VALUE
addrinfo_pfamily(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return INT2NUM(rai->pfamily);
}

/*
 * call-seq:
 *   addrinfo.socktype => integer
 *
 * returns the socket type as an integer.
 *
 *   Addrinfo.tcp("localhost", 80).socktype == Socket::SOCK_STREAM #=> true
 *
 */
static VALUE
addrinfo_socktype(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return INT2NUM(rai->socktype);
}

/*
 * call-seq:
 *   addrinfo.protocol => integer
 *
 * returns the socket type as an integer.
 *
 *   Addrinfo.tcp("localhost", 80).protocol == Socket::IPPROTO_TCP #=> true
 *
 */
static VALUE
addrinfo_protocol(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return INT2NUM(rai->protocol);
}

/*
 * call-seq:
 *   addrinfo.to_sockaddr => string
 *   addrinfo.to_s => string
 *
 * returns the socket address as packed struct sockaddr string.
 *
 *   Addrinfo.tcp("localhost", 80).to_sockaddr
 *   #=> "\x02\x00\x00P\x7F\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00"
 *
 */
static VALUE
addrinfo_to_sockaddr(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    VALUE ret;
    ret = rb_str_new((char*)&rai->addr, rai->sockaddr_len);
    return ret;
}

/*
 * call-seq:
 *   addrinfo.canonname => string or nil
 *
 * returns the canonical name as a string.
 *
 * nil is returned if no canonical name.
 *
 * The canonical name is set by Addrinfo.getaddrinfo when AI_CANONNAME is specified.
 *
 *   list = Addrinfo.getaddrinfo("www.ruby-lang.org", 80, :INET, :STREAM, nil, Socket::AI_CANONNAME)
 *   p list[0] #=> #<Addrinfo: 221.186.184.68:80 TCP carbon.ruby-lang.org (www.ruby-lang.org)>
 *   p list[0].canonname #=> "carbon.ruby-lang.org"
 *
 */
static VALUE
addrinfo_canonname(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return rai->canonname;
}

/*
 * call-seq:
 *   addrinfo.ip? => true or false
 *
 * returns true if addrinfo is internet (IPv4/IPv6) address.
 * returns false otherwise.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ip? #=> true
 *   Addrinfo.tcp("::1", 80).ip?       #=> true
 *   Addrinfo.unix("/tmp/sock").ip?    #=> false
 *
 */
static VALUE
addrinfo_ip_p(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    return IS_IP_FAMILY(family) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   addrinfo.ipv4? => true or false
 *
 * returns true if addrinfo is IPv4 address.
 * returns false otherwise.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ipv4? #=> true
 *   Addrinfo.tcp("::1", 80).ipv4?       #=> false
 *   Addrinfo.unix("/tmp/sock").ipv4?    #=> false
 *
 */
static VALUE
addrinfo_ipv4_p(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    return ai_get_afamily(rai) == AF_INET ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   addrinfo.ipv6? => true or false
 *
 * returns true if addrinfo is IPv6 address.
 * returns false otherwise.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ipv6? #=> false
 *   Addrinfo.tcp("::1", 80).ipv6?       #=> true
 *   Addrinfo.unix("/tmp/sock").ipv6?    #=> false
 *
 */
static VALUE
addrinfo_ipv6_p(VALUE self)
{
#ifdef AF_INET6
    rb_addrinfo_t *rai = get_addrinfo(self);
    return ai_get_afamily(rai) == AF_INET6 ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   addrinfo.unix? => true or false
 *
 * returns true if addrinfo is UNIX address.
 * returns false otherwise.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).unix? #=> false
 *   Addrinfo.tcp("::1", 80).unix?       #=> false
 *   Addrinfo.unix("/tmp/sock").unix?    #=> true
 *
 */
static VALUE
addrinfo_unix_p(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
#ifdef AF_UNIX
    return ai_get_afamily(rai) == AF_UNIX ? Qtrue : Qfalse;
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   addrinfo.getnameinfo        => [nodename, service]
 *   addrinfo.getnameinfo(flags) => [nodename, service]
 *
 * returns nodename and service as a pair of strings.
 * This converts struct sockaddr in addrinfo to textual representation.
 *
 * flags should be bitwise OR of Socket::NI_??? constants.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).getnameinfo #=> ["localhost", "www"]
 *
 *   Addrinfo.tcp("127.0.0.1", 80).getnameinfo(Socket::NI_NUMERICSERV)
 *   #=> ["localhost", "80"]
 */
static VALUE
addrinfo_getnameinfo(int argc, VALUE *argv, VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    VALUE vflags;
    char hbuf[1024], pbuf[1024];
    int flags, error;

    rb_scan_args(argc, argv, "01", &vflags);

    flags = NIL_P(vflags) ? 0 : NUM2INT(vflags);

    if (rai->socktype == SOCK_DGRAM)
        flags |= NI_DGRAM;

    error = getnameinfo(&rai->addr.addr, rai->sockaddr_len,
                        hbuf, (socklen_t)sizeof(hbuf), pbuf, (socklen_t)sizeof(pbuf),
                        flags);
    if (error) {
        rsock_raise_socket_error("getnameinfo", error);
    }

    return rb_assoc_new(rb_str_new2(hbuf), rb_str_new2(pbuf));
}

/*
 * call-seq:
 *   addrinfo.ip_unpack => [addr, port]
 *
 * Returns the IP address and port number as 2-element array.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ip_unpack    #=> ["127.0.0.1", 80]
 *   Addrinfo.tcp("::1", 80).ip_unpack          #=> ["::1", 80]
 */
static VALUE
addrinfo_ip_unpack(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    VALUE vflags;
    VALUE ret, portstr;

    if (!IS_IP_FAMILY(family))
	rb_raise(rb_eSocket, "need IPv4 or IPv6 address");

    vflags = INT2NUM(NI_NUMERICHOST|NI_NUMERICSERV);
    ret = addrinfo_getnameinfo(1, &vflags, self);
    portstr = rb_ary_entry(ret, 1);
    rb_ary_store(ret, 1, INT2NUM(atoi(StringValueCStr(portstr))));
    return ret;
}

/*
 * call-seq:
 *   addrinfo.ip_address => string
 *
 * Returns the IP address as a string.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ip_address    #=> "127.0.0.1"
 *   Addrinfo.tcp("::1", 80).ip_address          #=> "::1"
 */
static VALUE
addrinfo_ip_address(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    VALUE vflags;
    VALUE ret;

    if (!IS_IP_FAMILY(family))
	rb_raise(rb_eSocket, "need IPv4 or IPv6 address");

    vflags = INT2NUM(NI_NUMERICHOST|NI_NUMERICSERV);
    ret = addrinfo_getnameinfo(1, &vflags, self);
    return rb_ary_entry(ret, 0);
}

/*
 * call-seq:
 *   addrinfo.ip_port => port
 *
 * Returns the port number as an integer.
 *
 *   Addrinfo.tcp("127.0.0.1", 80).ip_port    #=> 80
 *   Addrinfo.tcp("::1", 80).ip_port          #=> 80
 */
static VALUE
addrinfo_ip_port(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    int port;

    if (!IS_IP_FAMILY(family)) {
      bad_family:
#ifdef AF_INET6
	rb_raise(rb_eSocket, "need IPv4 or IPv6 address");
#else
	rb_raise(rb_eSocket, "need IPv4 address");
#endif
    }

    switch (family) {
      case AF_INET:
        if (rai->sockaddr_len != sizeof(struct sockaddr_in))
            rb_raise(rb_eSocket, "unexpected sockaddr size for IPv4");
        port = ntohs(rai->addr.in.sin_port);
        break;

#ifdef AF_INET6
      case AF_INET6:
        if (rai->sockaddr_len != sizeof(struct sockaddr_in6))
            rb_raise(rb_eSocket, "unexpected sockaddr size for IPv6");
        port = ntohs(rai->addr.in6.sin6_port);
        break;
#endif

      default:
	goto bad_family;
    }

    return INT2NUM(port);
}

static int
extract_in_addr(VALUE self, uint32_t *addrp)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    if (family != AF_INET) return 0;
    *addrp = ntohl(rai->addr.in.sin_addr.s_addr);
    return 1;
}

/*
 * Returns true for IPv4 private address (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv4_private_p(VALUE self)
{
    uint32_t a;
    if (!extract_in_addr(self, &a)) return Qfalse;
    if ((a & 0xff000000) == 0x0a000000 || /* 10.0.0.0/8 */
        (a & 0xfff00000) == 0xac100000 || /* 172.16.0.0/12 */
        (a & 0xffff0000) == 0xc0a80000)   /* 192.168.0.0/16 */
        return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv4 loopback address (127.0.0.0/8).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv4_loopback_p(VALUE self)
{
    uint32_t a;
    if (!extract_in_addr(self, &a)) return Qfalse;
    if ((a & 0xff000000) == 0x7f000000) /* 127.0.0.0/8 */
        return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv4 multicast address (224.0.0.0/4).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv4_multicast_p(VALUE self)
{
    uint32_t a;
    if (!extract_in_addr(self, &a)) return Qfalse;
    if ((a & 0xf0000000) == 0xe0000000) /* 224.0.0.0/4 */
        return Qtrue;
    return Qfalse;
}

#ifdef INET6

static struct in6_addr *
extract_in6_addr(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    if (family != AF_INET6) return NULL;
    return &rai->addr.in6.sin6_addr;
}

/*
 * Returns true for IPv6 unspecified address (::).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_unspecified_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_UNSPECIFIED(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 loopback address (::1).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_loopback_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_LOOPBACK(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast address (ff00::/8).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_multicast_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MULTICAST(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 link local address (ff80::/10).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_linklocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_LINKLOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 site local address (ffc0::/10).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_sitelocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_SITELOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 unique local address (fc00::/7, RFC4193).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_unique_local_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_UNIQUE_LOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv4-mapped IPv6 address (::ffff:0:0/80).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_v4mapped_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_V4MAPPED(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv4-compatible IPv6 address (::/80).
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_v4compat_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_V4COMPAT(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast node-local scope address.
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_mc_nodelocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MC_NODELOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast link-local scope address.
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_mc_linklocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MC_LINKLOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast site-local scope address.
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_mc_sitelocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MC_SITELOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast organization-local scope address.
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_mc_orglocal_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MC_ORGLOCAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns true for IPv6 multicast global scope address.
 * It returns false otherwise.
 */
static VALUE
addrinfo_ipv6_mc_global_p(VALUE self)
{
    struct in6_addr *addr = extract_in6_addr(self);
    if (addr && IN6_IS_ADDR_MC_GLOBAL(addr)) return Qtrue;
    return Qfalse;
}

/*
 * Returns IPv4 address of IPv4 mapped/compatible IPv6 address.
 * It returns nil if +self+ is not IPv4 mapped/compatible IPv6 address.
 *
 *   Addrinfo.ip("::192.0.2.3").ipv6_to_ipv4      #=> #<Addrinfo: 192.0.2.3>
 *   Addrinfo.ip("::ffff:192.0.2.3").ipv6_to_ipv4 #=> #<Addrinfo: 192.0.2.3>
 *   Addrinfo.ip("::1").ipv6_to_ipv4              #=> nil
 *   Addrinfo.ip("192.0.2.3").ipv6_to_ipv4        #=> nil
 *   Addrinfo.unix("/tmp/sock").ipv6_to_ipv4      #=> nil
 */
static VALUE
addrinfo_ipv6_to_ipv4(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    struct in6_addr *addr;
    int family = ai_get_afamily(rai);
    if (family != AF_INET6) return Qnil;
    addr = &rai->addr.in6.sin6_addr;
    if (IN6_IS_ADDR_V4MAPPED(addr) || IN6_IS_ADDR_V4COMPAT(addr)) {
        struct sockaddr_in sin4;
        INIT_SOCKADDR_IN(&sin4, sizeof(sin4));
        memcpy(&sin4.sin_addr, (char*)addr + sizeof(*addr) - sizeof(sin4.sin_addr), sizeof(sin4.sin_addr));
        return rsock_addrinfo_new((struct sockaddr *)&sin4, (socklen_t)sizeof(sin4),
                                  PF_INET, rai->socktype, rai->protocol,
                                  rai->canonname, rai->inspectname);
    }
    else {
        return Qnil;
    }
}

#endif

#ifdef HAVE_SYS_UN_H
/*
 * call-seq:
 *   addrinfo.unix_path => path
 *
 * Returns the socket path as a string.
 *
 *   Addrinfo.unix("/tmp/sock").unix_path       #=> "/tmp/sock"
 */
static VALUE
addrinfo_unix_path(VALUE self)
{
    rb_addrinfo_t *rai = get_addrinfo(self);
    int family = ai_get_afamily(rai);
    struct sockaddr_un *addr;
    long n;

    if (family != AF_UNIX)
	rb_raise(rb_eSocket, "need AF_UNIX address");

    addr = &rai->addr.un;

    n = rai_unixsocket_len(rai);
    if (n < 0)
        rb_raise(rb_eSocket, "too short AF_UNIX address: %"PRIuSIZE" bytes given for minimum %"PRIuSIZE" bytes.",
                 (size_t)rai->sockaddr_len, offsetof(struct sockaddr_un, sun_path));
    if ((long)sizeof(addr->sun_path) < n)
        rb_raise(rb_eSocket,
            "too long AF_UNIX path (%"PRIuSIZE" bytes given but %"PRIuSIZE" bytes max)",
            (size_t)n, sizeof(addr->sun_path));
    return rb_str_new(addr->sun_path, n);
}
#endif

static ID id_timeout;

/*
 * call-seq:
 *   Addrinfo.getaddrinfo(nodename, service, family, socktype, protocol, flags) => [addrinfo, ...]
 *   Addrinfo.getaddrinfo(nodename, service, family, socktype, protocol)        => [addrinfo, ...]
 *   Addrinfo.getaddrinfo(nodename, service, family, socktype)                  => [addrinfo, ...]
 *   Addrinfo.getaddrinfo(nodename, service, family)                            => [addrinfo, ...]
 *   Addrinfo.getaddrinfo(nodename, service)                                    => [addrinfo, ...]
 *
 * returns a list of addrinfo objects as an array.
 *
 * This method converts nodename (hostname) and service (port) to addrinfo.
 * Since the conversion is not unique, the result is a list of addrinfo objects.
 *
 * nodename or service can be nil if no conversion intended.
 *
 * family, socktype and protocol are hint for preferred protocol.
 * If the result will be used for a socket with SOCK_STREAM,
 * SOCK_STREAM should be specified as socktype.
 * If so, Addrinfo.getaddrinfo returns addrinfo list appropriate for SOCK_STREAM.
 * If they are omitted or nil is given, the result is not restricted.
 *
 * Similarly, PF_INET6 as family restricts for IPv6.
 *
 * flags should be bitwise OR of Socket::AI_??? constants such as follows.
 * Note that the exact list of the constants depends on OS.
 *
 *   AI_PASSIVE      Get address to use with bind()
 *   AI_CANONNAME    Fill in the canonical name
 *   AI_NUMERICHOST  Prevent host name resolution
 *   AI_NUMERICSERV  Prevent service name resolution
 *   AI_V4MAPPED     Accept IPv4-mapped IPv6 addresses
 *   AI_ALL          Allow all addresses
 *   AI_ADDRCONFIG   Accept only if any address is assigned
 *
 * Note that socktype should be specified whenever application knows the usage of the address.
 * Some platform causes an error when socktype is omitted and servname is specified as an integer
 * because some port numbers, 512 for example, are ambiguous without socktype.
 *
 *   Addrinfo.getaddrinfo("www.kame.net", 80, nil, :STREAM)
 *   #=> [#<Addrinfo: 203.178.141.194:80 TCP (www.kame.net)>,
 *   #    #<Addrinfo: [2001:200:dff:fff1:216:3eff:feb1:44d7]:80 TCP (www.kame.net)>]
 *
 */
static VALUE
addrinfo_s_getaddrinfo(int argc, VALUE *argv, VALUE self)
{
    VALUE node, service, family, socktype, protocol, flags, opts, timeout;

    rb_scan_args(argc, argv, "24:", &node, &service, &family, &socktype,
		 &protocol, &flags, &opts);
    rb_get_kwargs(opts, &id_timeout, 0, 1, &timeout);
    if (timeout == Qundef) {
	timeout = Qnil;
    }

    return addrinfo_list_new(node, service, family, socktype, protocol, flags, timeout);
}

/*
 * call-seq:
 *   Addrinfo.ip(host) => addrinfo
 *
 * returns an addrinfo object for IP address.
 *
 * The port, socktype, protocol of the result is filled by zero.
 * So, it is not appropriate to create a socket.
 *
 *   Addrinfo.ip("localhost") #=> #<Addrinfo: 127.0.0.1 (localhost)>
 */
static VALUE
addrinfo_s_ip(VALUE self, VALUE host)
{
    VALUE ret;
    rb_addrinfo_t *rai;
    ret = addrinfo_firstonly_new(host, Qnil,
            INT2NUM(PF_UNSPEC), INT2FIX(0), INT2FIX(0), INT2FIX(0));
    rai = get_addrinfo(ret);
    rai->socktype = 0;
    rai->protocol = 0;
    return ret;
}

/*
 * call-seq:
 *   Addrinfo.tcp(host, port) => addrinfo
 *
 * returns an addrinfo object for TCP address.
 *
 *   Addrinfo.tcp("localhost", "smtp") #=> #<Addrinfo: 127.0.0.1:25 TCP (localhost:smtp)>
 */
static VALUE
addrinfo_s_tcp(VALUE self, VALUE host, VALUE port)
{
    return addrinfo_firstonly_new(host, port,
            INT2NUM(PF_UNSPEC), INT2NUM(SOCK_STREAM), INT2NUM(IPPROTO_TCP), INT2FIX(0));
}

/*
 * call-seq:
 *   Addrinfo.udp(host, port) => addrinfo
 *
 * returns an addrinfo object for UDP address.
 *
 *   Addrinfo.udp("localhost", "daytime") #=> #<Addrinfo: 127.0.0.1:13 UDP (localhost:daytime)>
 */
static VALUE
addrinfo_s_udp(VALUE self, VALUE host, VALUE port)
{
    return addrinfo_firstonly_new(host, port,
            INT2NUM(PF_UNSPEC), INT2NUM(SOCK_DGRAM), INT2NUM(IPPROTO_UDP), INT2FIX(0));
}

#ifdef HAVE_SYS_UN_H

/*
 * call-seq:
 *   Addrinfo.unix(path [, socktype]) => addrinfo
 *
 * returns an addrinfo object for UNIX socket address.
 *
 * _socktype_ specifies the socket type.
 * If it is omitted, :STREAM is used.
 *
 *   Addrinfo.unix("/tmp/sock")         #=> #<Addrinfo: /tmp/sock SOCK_STREAM>
 *   Addrinfo.unix("/tmp/sock", :DGRAM) #=> #<Addrinfo: /tmp/sock SOCK_DGRAM>
 */
static VALUE
addrinfo_s_unix(int argc, VALUE *argv, VALUE self)
{
    VALUE path, vsocktype, addr;
    int socktype;
    rb_addrinfo_t *rai;

    rb_scan_args(argc, argv, "11", &path, &vsocktype);

    if (NIL_P(vsocktype))
        socktype = SOCK_STREAM;
    else
        socktype = rsock_socktype_arg(vsocktype);

    addr = addrinfo_s_allocate(rb_cAddrinfo);
    DATA_PTR(addr) = rai = alloc_addrinfo();
    init_unix_addrinfo(rai, path, socktype);
    return addr;
}

#endif

VALUE
rsock_sockaddr_string_value(volatile VALUE *v)
{
    VALUE val = *v;
    if (IS_ADDRINFO(val)) {
        *v = addrinfo_to_sockaddr(val);
    }
    StringValue(*v);
    return *v;
}

VALUE
rsock_sockaddr_string_value_with_addrinfo(volatile VALUE *v, VALUE *rai_ret)
{
    VALUE val = *v;
    *rai_ret = Qnil;
    if (IS_ADDRINFO(val)) {
        *v = addrinfo_to_sockaddr(val);
        *rai_ret = val;
    }
    StringValue(*v);
    return *v;
}

char *
rsock_sockaddr_string_value_ptr(volatile VALUE *v)
{
    rsock_sockaddr_string_value(v);
    return RSTRING_PTR(*v);
}

VALUE
rb_check_sockaddr_string_type(VALUE val)
{
    if (IS_ADDRINFO(val))
        return addrinfo_to_sockaddr(val);
    return rb_check_string_type(val);
}

VALUE
rsock_fd_socket_addrinfo(int fd, struct sockaddr *addr, socklen_t len)
{
    int family;
    int socktype;
    int ret;
    socklen_t optlen = (socklen_t)sizeof(socktype);

    /* assumes protocol family and address family are identical */
    family = get_afamily(addr, len);

    ret = getsockopt(fd, SOL_SOCKET, SO_TYPE, (void*)&socktype, &optlen);
    if (ret == -1) {
        rb_sys_fail("getsockopt(SO_TYPE)");
    }

    return rsock_addrinfo_new(addr, len, family, socktype, 0, Qnil, Qnil);
}

VALUE
rsock_io_socket_addrinfo(VALUE io, struct sockaddr *addr, socklen_t len)
{
    rb_io_t *fptr;

    switch (TYPE(io)) {
      case T_FIXNUM:
        return rsock_fd_socket_addrinfo(FIX2INT(io), addr, len);

      case T_BIGNUM:
        return rsock_fd_socket_addrinfo(NUM2INT(io), addr, len);

      case T_FILE:
        GetOpenFile(io, fptr);
        return rsock_fd_socket_addrinfo(fptr->fd, addr, len);

      default:
        rb_raise(rb_eTypeError, "neither IO nor file descriptor");
    }

    UNREACHABLE_RETURN(Qnil);
}

/*
 * Addrinfo class
 */
void
rsock_init_addrinfo(void)
{
    /*
     * The Addrinfo class maps <tt>struct addrinfo</tt> to ruby.  This
     * structure identifies an Internet host and a service.
     */
    id_timeout = rb_intern("timeout");

    rb_cAddrinfo = rb_define_class("Addrinfo", rb_cData);
    rb_define_alloc_func(rb_cAddrinfo, addrinfo_s_allocate);
    rb_define_method(rb_cAddrinfo, "initialize", addrinfo_initialize, -1);
    rb_define_method(rb_cAddrinfo, "inspect", addrinfo_inspect, 0);
    rb_define_method(rb_cAddrinfo, "inspect_sockaddr", rsock_addrinfo_inspect_sockaddr, 0);
    rb_define_singleton_method(rb_cAddrinfo, "getaddrinfo", addrinfo_s_getaddrinfo, -1);
    rb_define_singleton_method(rb_cAddrinfo, "ip", addrinfo_s_ip, 1);
    rb_define_singleton_method(rb_cAddrinfo, "tcp", addrinfo_s_tcp, 2);
    rb_define_singleton_method(rb_cAddrinfo, "udp", addrinfo_s_udp, 2);
#ifdef HAVE_SYS_UN_H
    rb_define_singleton_method(rb_cAddrinfo, "unix", addrinfo_s_unix, -1);
#endif

    rb_define_method(rb_cAddrinfo, "afamily", addrinfo_afamily, 0);
    rb_define_method(rb_cAddrinfo, "pfamily", addrinfo_pfamily, 0);
    rb_define_method(rb_cAddrinfo, "socktype", addrinfo_socktype, 0);
    rb_define_method(rb_cAddrinfo, "protocol", addrinfo_protocol, 0);
    rb_define_method(rb_cAddrinfo, "canonname", addrinfo_canonname, 0);

    rb_define_method(rb_cAddrinfo, "ipv4?", addrinfo_ipv4_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6?", addrinfo_ipv6_p, 0);
    rb_define_method(rb_cAddrinfo, "unix?", addrinfo_unix_p, 0);

    rb_define_method(rb_cAddrinfo, "ip?", addrinfo_ip_p, 0);
    rb_define_method(rb_cAddrinfo, "ip_unpack", addrinfo_ip_unpack, 0);
    rb_define_method(rb_cAddrinfo, "ip_address", addrinfo_ip_address, 0);
    rb_define_method(rb_cAddrinfo, "ip_port", addrinfo_ip_port, 0);

    rb_define_method(rb_cAddrinfo, "ipv4_private?", addrinfo_ipv4_private_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv4_loopback?", addrinfo_ipv4_loopback_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv4_multicast?", addrinfo_ipv4_multicast_p, 0);

#ifdef INET6
    rb_define_method(rb_cAddrinfo, "ipv6_unspecified?", addrinfo_ipv6_unspecified_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_loopback?", addrinfo_ipv6_loopback_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_multicast?", addrinfo_ipv6_multicast_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_linklocal?", addrinfo_ipv6_linklocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_sitelocal?", addrinfo_ipv6_sitelocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_unique_local?", addrinfo_ipv6_unique_local_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_v4mapped?", addrinfo_ipv6_v4mapped_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_v4compat?", addrinfo_ipv6_v4compat_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_mc_nodelocal?", addrinfo_ipv6_mc_nodelocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_mc_linklocal?", addrinfo_ipv6_mc_linklocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_mc_sitelocal?", addrinfo_ipv6_mc_sitelocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_mc_orglocal?", addrinfo_ipv6_mc_orglocal_p, 0);
    rb_define_method(rb_cAddrinfo, "ipv6_mc_global?", addrinfo_ipv6_mc_global_p, 0);

    rb_define_method(rb_cAddrinfo, "ipv6_to_ipv4", addrinfo_ipv6_to_ipv4, 0);
#endif

#ifdef HAVE_SYS_UN_H
    rb_define_method(rb_cAddrinfo, "unix_path", addrinfo_unix_path, 0);
#endif

    rb_define_method(rb_cAddrinfo, "to_sockaddr", addrinfo_to_sockaddr, 0);
    rb_define_method(rb_cAddrinfo, "to_s", addrinfo_to_sockaddr, 0); /* compatibility for ruby before 1.9.2 */

    rb_define_method(rb_cAddrinfo, "getnameinfo", addrinfo_getnameinfo, -1);

    rb_define_method(rb_cAddrinfo, "marshal_dump", addrinfo_mdump, 0);
    rb_define_method(rb_cAddrinfo, "marshal_load", addrinfo_mload, 1);

#ifdef HAVE_GETADDRINFO_A
    rb_socket_before_exec_func = rb_getaddrinfo_a_before_exec;
#endif
}
