#ifndef RUBY_SOCKET_H
#define RUBY_SOCKET_H 1

#include "ruby/config.h"
#include RUBY_EXTCONF_H

#if defined(__sun) || defined(_AIX)
/* (Recent?)  Solaris' <nfs/nfs.h> have conflicting definition of T_DATA.  Let
 * us honour system definition by undefining ours.
 *
 * See also [ruby-core:4261]
 */
# include "ruby/ruby.h"
# undef T_DATA
#endif

#include <errno.h>
#include <stdio.h>

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_UNISTD_H
#  include <unistd.h>
#endif

#ifdef HAVE_SYS_UIO_H
#  include <sys/uio.h>
#endif

#ifdef HAVE_XTI_H
#  include <xti.h>
#endif

#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <iphlpapi.h>
#  if defined(_MSC_VER)
#    undef HAVE_TYPE_STRUCT_SOCKADDR_DL
#  endif
#else
#  include <sys/socket.h>
#  include <netinet/in.h>
#  ifdef HAVE_NETINET_IN_SYSTM_H
#    include <netinet/in_systm.h>
#  endif
#  ifdef HAVE_NETINET_TCP_H
#    include <netinet/tcp.h>
#  endif
#  ifdef HAVE_NETINET_TCP_FSM_H
#    include <netinet/tcp_fsm.h>
#  endif
#  ifdef HAVE_NETINET_UDP_H
#    include <netinet/udp.h>
#  endif
#  ifdef HAVE_ARPA_INET_H
#    include <arpa/inet.h>
#  endif
#  include <netdb.h>
#endif

#ifdef HAVE_NETPACKET_PACKET_H
#  include <netpacket/packet.h>
#endif

#ifdef HAVE_NET_ETHERNET_H
#  include <net/ethernet.h>
#endif

#ifdef HAVE_SYS_UN_H
#  include <sys/un.h>
#endif

#ifdef HAVE_AFUNIX_H
// Windows doesn't have sys/un.h, but it does have afunix.h just to be special:
#  include <afunix.h>
#endif

#if defined(HAVE_FCNTL)
#  ifdef HAVE_SYS_SELECT_H
#    include <sys/select.h>
#  endif
#  ifdef HAVE_SYS_TYPES_H
#    include <sys/types.h>
#  endif
#  ifdef HAVE_SYS_TIME_H
#    include <sys/time.h>
#  endif
#  ifdef HAVE_FCNTL_H
#    include <fcntl.h>
#  endif
#endif

#ifdef HAVE_IFADDRS_H
#  ifdef __HAIKU__
#    define _BSD_SOURCE
#  endif
#  include <ifaddrs.h>
#endif

#ifdef HAVE_SYS_IOCTL_H
#  include <sys/ioctl.h>
#endif

#ifdef HAVE_SYS_SOCKIO_H
#  include <sys/sockio.h>
#endif

#ifdef HAVE_NET_IF_H
#  include <net/if.h>
#endif

#ifdef HAVE_SYS_PARAM_H
#  include <sys/param.h>
#endif

#ifdef HAVE_SYS_UCRED_H
#  include <sys/ucred.h>
#endif

#ifdef HAVE_UCRED_H
#  include <ucred.h>
#endif

#ifdef HAVE_NET_IF_DL_H
#  include <net/if_dl.h>
#endif

#ifdef SOCKS5
#  include <socks.h>
#endif

#ifndef HAVE_GETADDRINFO
#  include "addrinfo.h"
#endif

#include "internal.h"
#include "internal/array.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/io.h"
#include "internal/thread.h"
#include "internal/vm.h"
#include "ruby/io.h"
#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "sockport.h"
#include "ruby/fiber/scheduler.h"

#ifndef HAVE_TYPE_SOCKLEN_T
typedef int socklen_t;
#endif

#ifdef NEED_IF_INDEXTONAME_DECL
char *if_indextoname(unsigned int, char *);
#endif
#ifdef NEED_IF_NAMETOINDEX_DECL
unsigned int if_nametoindex(const char *);
#endif

#define SOCKLEN_MAX \
  (0 < (socklen_t)-1 ? \
   ~(socklen_t)0 : \
   (((((socklen_t)1) << (sizeof(socklen_t) * CHAR_BIT - 2)) - 1) * 2 + 1))

#ifndef RSTRING_SOCKLEN
#  define RSTRING_SOCKLEN (socklen_t)RSTRING_LENINT
#endif

#ifndef EWOULDBLOCK
#  define EWOULDBLOCK EAGAIN
#endif

/*
 * workaround for NetBSD, OpenBSD and etc.
 * The problem is since 4.4BSD-Lite.
 * FreeBSD fix the problem at FreeBSD 2.2.0.
 * NetBSD fix the problem at NetBSD 3.0 by kern/29624.
 * OpenBSD fix the problem at OpenBSD 3.8.
 */
#define pseudo_AF_FTIP pseudo_AF_RTIP


#ifndef NI_MAXHOST
#  define NI_MAXHOST 1025
#endif
#ifndef NI_MAXSERV
#  define NI_MAXSERV 32
#endif

#ifdef AF_INET6
#  define IS_IP_FAMILY(af) ((af) == AF_INET || (af) == AF_INET6)
#else
#  define IS_IP_FAMILY(af) ((af) == AF_INET)
#endif

#ifndef IN6_IS_ADDR_UNIQUE_LOCAL
#  define IN6_IS_ADDR_UNIQUE_LOCAL(a) (((a)->s6_addr[0] == 0xfc) || ((a)->s6_addr[0] == 0xfd))
#endif

#ifndef HAVE_TYPE_STRUCT_SOCKADDR_STORAGE
/*
 * RFC 2553: protocol-independent placeholder for socket addresses
 */
#  define _SS_MAXSIZE     128
#  define _SS_ALIGNSIZE   (sizeof(double))
#  define _SS_PAD1SIZE    (_SS_ALIGNSIZE - sizeof(unsigned char) * 2)
#  define _SS_PAD2SIZE    (_SS_MAXSIZE - sizeof(unsigned char) * 2 - \
                                _SS_PAD1SIZE - _SS_ALIGNSIZE)

struct sockaddr_storage {
#  ifdef HAVE_STRUCT_SOCKADDR_SA_LEN
        unsigned char ss_len;           /* address length */
        unsigned char ss_family;        /* address family */
#  else
        unsigned short ss_family;
#  endif
        char    __ss_pad1[_SS_PAD1SIZE];
        double  __ss_align;     /* force desired structure storage alignment */
        char    __ss_pad2[_SS_PAD2SIZE];
};
#endif

typedef union {
  struct sockaddr addr;
  struct sockaddr_in in;
#ifdef AF_INET6
  struct sockaddr_in6 in6;
#endif
#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
  struct sockaddr_un un;
#endif
#ifdef HAVE_TYPE_STRUCT_SOCKADDR_DL
  struct sockaddr_dl dl; /* AF_LINK */
#endif
  struct sockaddr_storage storage;
  char place_holder[2048]; /* sockaddr_storage is not enough for Unix domain sockets on SunOS and Darwin. */
} union_sockaddr;

#ifdef __APPLE__
/*
 * CMSG_ macros are broken on 64bit darwin, because __DARWIN_ALIGN
 * aligns up to __darwin_size_t which is 64bit, but CMSG_DATA is
 * 32bit-aligned.
 */
#  undef __DARWIN_ALIGNBYTES
#  define __DARWIN_ALIGNBYTES (sizeof(unsigned int) - 1)
#endif

#if defined(_AIX)
#  ifndef CMSG_SPACE
#    define CMSG_SPACE(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + _CMSG_ALIGN(len))
#  endif
#  ifndef CMSG_LEN
#    define CMSG_LEN(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
#  endif
#endif

#define INET_CLIENT 0
#define INET_SERVER 1
#define INET_SOCKS  2

extern int rsock_do_not_reverse_lookup;
#define FMODE_NOREVLOOKUP 0x100

/* common socket families only */
#define FMODE_UNIX        0x00200000
#define FMODE_INET        0x00400000
#define FMODE_INET6       0x00800000
#define FMODE_SOCK        (FMODE_UNIX|FMODE_INET|FMODE_INET6)

extern VALUE rb_cBasicSocket;
extern VALUE rb_cIPSocket;
extern VALUE rb_cTCPSocket;
extern VALUE rb_cTCPServer;
extern VALUE rb_cUDPSocket;
#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
extern VALUE rb_cUNIXSocket;
extern VALUE rb_cUNIXServer;
#endif
extern VALUE rb_cSocket;
extern VALUE rb_cAddrinfo;
extern VALUE rb_cSockOpt;

extern VALUE rb_eSocket;

#ifdef SOCKS
extern VALUE rb_cSOCKSSocket;
#  ifndef SOCKS5
void SOCKSinit();
int Rconnect();
#  endif
#endif

#include "constdefs.h"

#define BLOCKING_REGION_FD(func, arg) (long)rb_thread_io_blocking_region((func), (arg), (arg)->fd)

#define SockAddrStringValue(v) rsock_sockaddr_string_value(&(v))
#define SockAddrStringValuePtr(v) rsock_sockaddr_string_value_ptr(&(v))
#define SockAddrStringValueWithAddrinfo(v, rai_ret) rsock_sockaddr_string_value_with_addrinfo(&(v), &(rai_ret))
VALUE rsock_sockaddr_string_value(volatile VALUE *);
char *rsock_sockaddr_string_value_ptr(volatile VALUE *);
VALUE rsock_sockaddr_string_value_with_addrinfo(volatile VALUE *v, VALUE *ai_ret);

VALUE rb_check_sockaddr_string_type(VALUE);

NORETURN(void rsock_raise_socket_error(const char *, int));

int rsock_family_arg(VALUE domain);
int rsock_socktype_arg(VALUE type);
int rsock_level_arg(int family, VALUE level);
int rsock_optname_arg(int family, int level, VALUE optname);
int rsock_cmsg_type_arg(int family, int level, VALUE type);
int rsock_shutdown_how_arg(VALUE how);

int rsock_getfamily(rb_io_t *fptr);

struct rb_addrinfo {
  struct addrinfo *ai;
  int allocated_by_malloc;
};
void rb_freeaddrinfo(struct rb_addrinfo *ai);
VALUE rsock_freeaddrinfo(VALUE arg);
int rb_getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, size_t hostlen, char *serv, size_t servlen, int flags);
int rsock_fd_family(int fd);
struct rb_addrinfo *rsock_addrinfo(VALUE host, VALUE port, int family, int socktype, int flags);
struct rb_addrinfo *rsock_getaddrinfo(VALUE host, VALUE port, struct addrinfo *hints, int socktype_hack);

VALUE rsock_fd_socket_addrinfo(int fd, struct sockaddr *addr, socklen_t len);
VALUE rsock_io_socket_addrinfo(VALUE io, struct sockaddr *addr, socklen_t len);

VALUE rsock_addrinfo_new(struct sockaddr *addr, socklen_t len, int family, int socktype, int protocol, VALUE canonname, VALUE inspectname);
VALUE rsock_addrinfo_inspect_sockaddr(VALUE rai);

VALUE rsock_make_ipaddr(struct sockaddr *addr, socklen_t addrlen);
VALUE rsock_ipaddr(struct sockaddr *sockaddr, socklen_t sockaddrlen, int norevlookup);
VALUE rsock_make_hostent(VALUE host, struct rb_addrinfo *addr, VALUE (*ipaddr)(struct sockaddr *, socklen_t));
VALUE rsock_inspect_sockaddr(struct sockaddr *addr, socklen_t socklen, VALUE ret);
socklen_t rsock_sockaddr_len(struct sockaddr *addr);
VALUE rsock_sockaddr_obj(struct sockaddr *addr, socklen_t len);

int rsock_revlookup_flag(VALUE revlookup, int *norevlookup);

#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
VALUE rsock_unixpath_str(struct sockaddr_un *sockaddr, socklen_t len);
VALUE rsock_unixaddr(struct sockaddr_un *sockaddr, socklen_t len);
socklen_t rsock_unix_sockaddr_len(VALUE path);
#endif

int rsock_socket(int domain, int type, int proto);
int rsock_detect_cloexec(int fd);
VALUE rsock_init_sock(VALUE sock, int fd);
VALUE rsock_sock_s_socketpair(int argc, VALUE *argv, VALUE klass);
VALUE rsock_init_inetsock(VALUE sock, VALUE remote_host, VALUE remote_serv, VALUE local_host, VALUE local_serv, int type, VALUE resolv_timeout, VALUE connect_timeout);
VALUE rsock_init_unixsock(VALUE sock, VALUE path, int server);

struct rsock_send_arg {
    int fd, flags;
    VALUE mesg;
    struct sockaddr *to;
    socklen_t tolen;
};

VALUE rsock_sendto_blocking(void *data);
VALUE rsock_send_blocking(void *data);
VALUE rsock_bsock_send(int argc, VALUE *argv, VALUE sock);

enum sock_recv_type {
    RECV_RECV,                  /* BasicSocket#recv(no from) */
    RECV_IP,                    /* IPSocket#recvfrom */
    RECV_UNIX,                  /* UNIXSocket#recvfrom */
    RECV_SOCKET                 /* Socket#recvfrom */
};

VALUE rsock_s_recvfrom_nonblock(VALUE sock, VALUE len, VALUE flg, VALUE str,
                                VALUE ex, enum sock_recv_type from);
VALUE rsock_s_recvfrom(VALUE sock, int argc, VALUE *argv, enum sock_recv_type from);

int rsock_connect(int fd, const struct sockaddr *sockaddr, int len, int socks, struct timeval *timeout);

VALUE rsock_s_accept(VALUE klass, VALUE io, struct sockaddr *sockaddr, socklen_t *len);
VALUE rsock_s_accept_nonblock(VALUE klass, VALUE ex, rb_io_t *fptr,
                              struct sockaddr *sockaddr, socklen_t *len);
VALUE rsock_sock_listen(VALUE sock, VALUE log);

VALUE rsock_sockopt_new(int family, int level, int optname, VALUE data);

#if defined(HAVE_SENDMSG)
VALUE rsock_bsock_sendmsg(VALUE sock, VALUE data, VALUE flags,
                          VALUE dest_sockaddr, VALUE controls);
VALUE rsock_bsock_sendmsg_nonblock(VALUE sock, VALUE data, VALUE flags,
                             VALUE dest_sockaddr, VALUE controls, VALUE ex);
#else
#define rsock_bsock_sendmsg rb_f_notimplement
#define rsock_bsock_sendmsg_nonblock rb_f_notimplement
#endif

#if defined(HAVE_RECVMSG)
VALUE rsock_bsock_recvmsg(VALUE sock, VALUE dlen, VALUE clen, VALUE flags,
                          VALUE scm_rights);
VALUE rsock_bsock_recvmsg_nonblock(VALUE sock, VALUE dlen, VALUE clen,
                                   VALUE flags, VALUE scm_rights, VALUE ex);
ssize_t rsock_recvmsg(int socket, struct msghdr *message, int flags);
#else
#define rsock_bsock_recvmsg rb_f_notimplement
#define rsock_bsock_recvmsg_nonblock rb_f_notimplement
#endif

#ifdef HAVE_STRUCT_MSGHDR_MSG_CONTROL
void rsock_discard_cmsg_resource(struct msghdr *mh, int msg_peek_p);
#endif

void rsock_init_basicsocket(void);
void rsock_init_ipsocket(void);
void rsock_init_tcpsocket(void);
void rsock_init_tcpserver(void);
void rsock_init_sockssocket(void);
void rsock_init_udpsocket(void);
void rsock_init_unixsocket(void);
void rsock_init_unixserver(void);
void rsock_init_socket_constants(void);
void rsock_init_ancdata(void);
void rsock_init_addrinfo(void);
void rsock_init_sockopt(void);
void rsock_init_sockifaddr(void);
void rsock_init_socket_init(void);

NORETURN(void rsock_syserr_fail_host_port(int err, const char *, VALUE, VALUE));
NORETURN(void rsock_syserr_fail_path(int err, const char *, VALUE));
NORETURN(void rsock_syserr_fail_sockaddr(int err, const char *mesg, struct sockaddr *addr, socklen_t len));
NORETURN(void rsock_syserr_fail_raddrinfo(int err, const char *mesg, VALUE rai));
NORETURN(void rsock_syserr_fail_raddrinfo_or_sockaddr(int err, const char *mesg, VALUE addr, VALUE rai));

NORETURN(void rsock_sys_fail_host_port(const char *, VALUE, VALUE));
NORETURN(void rsock_sys_fail_path(const char *, VALUE));
NORETURN(void rsock_sys_fail_sockaddr(const char *, struct sockaddr *addr, socklen_t len));
NORETURN(void rsock_sys_fail_raddrinfo(const char *, VALUE rai));
NORETURN(void rsock_sys_fail_raddrinfo_or_sockaddr(const char *, VALUE addr, VALUE rai));

#if defined(__MINGW32__) || defined(_WIN32)
#define RSOCK_WAIT_BEFORE_BLOCKING
#endif

/*
 * some OSes may support MSG_DONTWAIT inconsistently depending on socket
 * type, we only expect Linux to support it consistently for all socket types.
 */
#if defined(MSG_DONTWAIT) && defined(__linux__)
#  define MSG_DONTWAIT_RELIABLE 1
#else
#  define MSG_DONTWAIT_RELIABLE 0
#endif

VALUE rsock_read_nonblock(VALUE sock, VALUE length, VALUE buf, VALUE ex);
VALUE rsock_write_nonblock(VALUE sock, VALUE buf, VALUE ex);

void rsock_make_fd_nonblock(int fd);

#if !defined HAVE_INET_NTOP && ! defined _WIN32
const char *inet_ntop(int, const void *, char *, size_t);
#elif defined __MINGW32__
# define inet_ntop(f,a,n,l)      rb_w32_inet_ntop(f,a,n,l)
#elif defined _MSC_VER && RUBY_MSVCRT_VERSION < 90
const char *WSAAPI inet_ntop(int, const void *, char *, size_t);
#endif

#endif
