#ifndef RUBY_SOCKET_H
#define RUBY_SOCKET_H 1

#include "ruby/ruby.h"
#include "ruby/io.h"
#include "ruby/util.h"
#include <stdio.h>
#include <sys/types.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYS_UIO_H
#include <sys/uio.h>
#endif

#ifdef HAVE_XTI_H
#include <xti.h>
#endif

#ifndef _WIN32
#if defined(__BEOS__) && !defined(__HAIKU__) && !defined(BONE)
# include <net/socket.h>
#else
# include <sys/socket.h>
#endif
#include <netinet/in.h>
#ifdef HAVE_NETINET_IN_SYSTM_H
# include <netinet/in_systm.h>
#endif
#ifdef HAVE_NETINET_TCP_H
# include <netinet/tcp.h>
#endif
#ifdef HAVE_NETINET_UDP_H
# include <netinet/udp.h>
#endif
#ifdef HAVE_ARPA_INET_H
# include <arpa/inet.h>
#endif
#include <netdb.h>
#endif
#include <errno.h>
#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#endif

#if defined(HAVE_FCNTL)
#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif
#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#endif
#ifndef EWOULDBLOCK
#define EWOULDBLOCK EAGAIN
#endif
#ifndef HAVE_GETADDRINFO
# include "addrinfo.h"
#endif
#include "sockport.h"

#ifndef NI_MAXHOST
# define NI_MAXHOST 1025
#endif
#ifndef NI_MAXSERV
# define NI_MAXSERV 32
#endif

#ifdef AF_INET6
# define IS_IP_FAMILY(af) ((af) == AF_INET || (af) == AF_INET6)
#else
# define IS_IP_FAMILY(af) ((af) == AF_INET)
#endif

#ifndef HAVE_SOCKADDR_STORAGE
/*
 * RFC 2553: protocol-independent placeholder for socket addresses
 */
#define _SS_MAXSIZE     128
#define _SS_ALIGNSIZE   (sizeof(double))
#define _SS_PAD1SIZE    (_SS_ALIGNSIZE - sizeof(unsigned char) * 2)
#define _SS_PAD2SIZE    (_SS_MAXSIZE - sizeof(unsigned char) * 2 - \
                                _SS_PAD1SIZE - _SS_ALIGNSIZE)

struct sockaddr_storage {
#ifdef HAVE_SA_LEN
        unsigned char ss_len;           /* address length */
        unsigned char ss_family;        /* address family */
#else
        unsigned short ss_family;
#endif
        char    __ss_pad1[_SS_PAD1SIZE];
        double  __ss_align;     /* force desired structure storage alignment */
        char    __ss_pad2[_SS_PAD2SIZE];
};
#endif

#if defined(_AIX)
#ifndef CMSG_SPACE
# define CMSG_SPACE(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + _CMSG_ALIGN(len))
#endif
#ifndef CMSG_LEN
# define CMSG_LEN(len) (_CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
#endif
#endif

#ifdef __BEOS__
#undef close
#define close closesocket
#endif

#define INET_CLIENT 0
#define INET_SERVER 1
#define INET_SOCKS  2

extern int do_not_reverse_lookup;
#define FMODE_NOREVLOOKUP 0x100

extern VALUE rb_cBasicSocket;
extern VALUE rb_cIPSocket;
extern VALUE rb_cTCPSocket;
extern VALUE rb_cTCPServer;
extern VALUE rb_cUDPSocket;
#ifdef AF_UNIX
extern VALUE rb_cUNIXSocket;
extern VALUE rb_cUNIXServer;
#endif
extern VALUE rb_cSocket;
extern VALUE rb_cAddrInfo;

extern VALUE rb_eSocket;

#ifdef SOCKS
extern VALUE rb_cSOCKSSocket;
#ifdef SOCKS5
#include <socks.h>
#else
void SOCKSinit();
int Rconnect();
#endif
#endif

#include "constdefs.h"

#define BLOCKING_REGION(func, arg) (long)rb_thread_blocking_region((func), (arg), RUBY_UBF_IO, 0)

#define SockAddrStringValue(v) sockaddr_string_value(&(v))
#define SockAddrStringValuePtr(v) sockaddr_string_value_ptr(&(v))
VALUE sockaddr_string_value(volatile VALUE *);
char *sockaddr_string_value_ptr(volatile VALUE *);
VALUE rb_check_sockaddr_string_type(VALUE);

NORETURN(void raise_socket_error(const char *, int));

int family_arg(VALUE domain);
int socktype_arg(VALUE type);
int level_arg(VALUE level);
int optname_arg(int level, VALUE optname);
int shutdown_how_arg(VALUE how);

int rb_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
int rb_getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, size_t hostlen, char *serv, size_t servlen, int flags);
struct addrinfo *sock_addrinfo(VALUE host, VALUE port, int socktype, int flags);
struct addrinfo* sock_getaddrinfo(VALUE host, VALUE port, struct addrinfo *hints, int socktype_hack);
VALUE fd_socket_addrinfo(int fd, struct sockaddr *addr, socklen_t len);
VALUE io_socket_addrinfo(VALUE io, struct sockaddr *addr, socklen_t len);

VALUE make_ipaddr(struct sockaddr *addr);
VALUE ipaddr(struct sockaddr *sockaddr, int norevlookup);
VALUE make_hostent(VALUE host, struct addrinfo *addr, VALUE (*ipaddr)(struct sockaddr *, size_t));

const char* unixpath(struct sockaddr_un *sockaddr, socklen_t len);
VALUE unixaddr(struct sockaddr_un *sockaddr, socklen_t len);

int ruby_socket(int domain, int type, int proto);
VALUE init_sock(VALUE sock, int fd);
VALUE sock_s_socketpair(VALUE klass, VALUE domain, VALUE type, VALUE protocol);
VALUE init_inetsock(VALUE sock, VALUE remote_host, VALUE remote_serv, VALUE local_host, VALUE local_serv, int type);
VALUE init_unixsock(VALUE sock, VALUE path, int server);

struct send_arg {
    int fd, flags;
    VALUE mesg;
    struct sockaddr *to;
    socklen_t tolen;
};

VALUE sendto_blocking(void *data);
VALUE send_blocking(void *data);
VALUE bsock_send(int argc, VALUE *argv, VALUE sock);

enum sock_recv_type {
    RECV_RECV,                  /* BasicSocket#recv(no from) */
    RECV_IP,                    /* IPSocket#recvfrom */
    RECV_UNIX,                  /* UNIXSocket#recvfrom */
    RECV_SOCKET                 /* Socket#recvfrom */
};

VALUE s_recvfrom_nonblock(VALUE sock, int argc, VALUE *argv, enum sock_recv_type from);
VALUE s_recvfrom(VALUE sock, int argc, VALUE *argv, enum sock_recv_type from);

int ruby_connect(int fd, const struct sockaddr *sockaddr, int len, int socks);

VALUE sock_listen(VALUE sock, VALUE log);

VALUE s_accept(VALUE klass, int fd, struct sockaddr *sockaddr, socklen_t *len);
VALUE s_accept_nonblock(VALUE klass, rb_io_t *fptr, struct sockaddr *sockaddr, socklen_t *len);

void Init_basicsocket(void);
void Init_ipsocket(void);
void Init_tcpsocket(void);
void Init_tcpserver(void);
void Init_sockssocket(void);
void Init_udpsocket(void);
void Init_unixsocket(void);
void Init_unixserver(void);
void Init_socket_constants(void);
void Init_addrinfo(void);
void Init_socket_init(void);

#endif
