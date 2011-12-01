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
#define inet_ntop	 rb_w32_inet_ntop

#undef accept
#define accept		 rb_w32_accept

#undef bind
#define bind		 rb_w32_bind

#undef connect
#define connect		 rb_w32_connect

#undef select
#define select		 rb_w32_select

#undef getpeername
#define getpeername	 rb_w32_getpeername

#undef getsockname
#define getsockname	 rb_w32_getsockname

#undef getsockopt
#define getsockopt	 rb_w32_getsockopt

#undef ioctlsocket
#define ioctlsocket	 rb_w32_ioctlsocket

#undef listen
#define listen		 rb_w32_listen

#undef recv
#define recv		 rb_w32_recv

#undef recvfrom
#define recvfrom	 rb_w32_recvfrom

#undef send
#define send		 rb_w32_send

#undef sendto
#define sendto		 rb_w32_sendto

#undef setsockopt
#define setsockopt	 rb_w32_setsockopt

#undef shutdown
#define shutdown	 rb_w32_shutdown

#undef socket
#define socket		 rb_w32_socket

#undef gethostbyaddr
#define gethostbyaddr	 rb_w32_gethostbyaddr

#undef gethostbyname
#define gethostbyname	 rb_w32_gethostbyname

#undef gethostname
#define gethostname	 rb_w32_gethostname

#undef getprotobyname
#define getprotobyname	 rb_w32_getprotobyname

#undef getprotobynumber
#define getprotobynumber rb_w32_getprotobynumber

#undef getservbyname
#define getservbyname	 rb_w32_getservbyname

#undef getservbyport
#define getservbyport	 rb_w32_getservbyport

#undef socketpair
#define socketpair	 rb_w32_socketpair

#undef get_osfhandle
#define get_osfhandle	 rb_w32_get_osfhandle

#undef getcwd
#define getcwd		 rb_w32_getcwd

#undef getenv
#define getenv		 rb_w32_getenv

#undef rename
#define rename		 rb_w32_rename

#undef times
#define times		 rb_w32_times
#endif

#endif
