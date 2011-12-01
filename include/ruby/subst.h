#ifndef RUBY_SUBST_H
#define RUBY_SUBST_H 1

#undef snprintf
#undef vsnprintf
#define snprintf ruby_snprintf
#define vsnprintf ruby_vsnprintf

#ifdef BROKEN_CLOSE
#undef getpeername
#define getpeername ruby_getpeername
#undef getsockname
#define getsockname ruby_getsockname
#undef shutdown
#define shutdown ruby_shutdown
#undef close
#define close ruby_close
#endif

#ifdef _WIN32
#undef inet_ntop
#define inet_ntop(f,a,n,l)      rb_w32_inet_ntop(f,a,n,l)

#undef accept
#define accept(s, a, l)		rb_w32_accept(s, a, l)

#undef bind
#define bind(s, a, l)		rb_w32_bind(s, a, l)

#undef connect
#define connect(s, a, l)	rb_w32_connect(s, a, l)

#undef select
#define select(n, r, w, e, t)	rb_w32_select(n, r, w, e, t)

#undef getpeername
#define getpeername(s, a, l)	rb_w32_getpeername(s, a, l)

#undef getsockname
#define getsockname(s, a, l)	rb_w32_getsockname(s, a, l)

#undef getsockopt
#define getsockopt(s, v, n, o, l) rb_w32_getsockopt(s, v, n, o, l)

#undef ioctlsocket
#define ioctlsocket(s, c, a)	rb_w32_ioctlsocket(s, c, a)

#undef listen
#define listen(s, b)		rb_w32_listen(s, b)

#undef recv
#define recv(s, b, l, f)	rb_w32_recv(s, b, l, f)

#undef recvfrom
#define recvfrom(s, b, l, f, fr, frl) rb_w32_recvfrom(s, b, l, f, fr, frl)

#undef send
#define send(s, b, l, f)	rb_w32_send(s, b, l, f)

#undef sendto
#define sendto(s, b, l, f, t, tl) rb_w32_sendto(s, b, l, f, t, tl)

#undef setsockopt
#define setsockopt(s, v, n, o, l) rb_w32_setsockopt(s, v, n, o, l)

#undef shutdown
#define shutdown(s, h)		rb_w32_shutdown(s, h)

#undef socket
#define socket(s, t, p)		rb_w32_socket(s, t, p)

#undef gethostbyaddr
#define gethostbyaddr(a, l, t)	rb_w32_gethostbyaddr(a, l, t)

#undef gethostbyname
#define gethostbyname(n)	rb_w32_gethostbyname(n)

#undef gethostname
#define gethostname(n, l)	rb_w32_gethostname(n, l)

#undef getprotobyname
#define getprotobyname(n)	rb_w32_getprotobyname(n)

#undef getprotobynumber
#define getprotobynumber(n)	rb_w32_getprotobynumber(n)

#undef getservbyname
#define getservbyname(n, p)	rb_w32_getservbyname(n, p)

#undef getservbyport
#define getservbyport(p, pr)	rb_w32_getservbyport(p, pr)

#undef socketpair
#define socketpair(a, t, p, s)	rb_w32_socketpair(a, t, p, s)

#undef get_osfhandle
#define get_osfhandle(h)	rb_w32_get_osfhandle(h)

#undef getcwd
#define getcwd(b, s)		rb_w32_getcwd(b, s)

#undef getenv
#define getenv(n)		rb_w32_getenv(n)

#undef rename
#define rename(o, n)		rb_w32_rename(o, n)

#undef times
#define times(t)		rb_w32_times(t)
#endif

#endif
