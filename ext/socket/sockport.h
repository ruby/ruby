/************************************************

  sockport.h -

  $Author$
  created at: Fri Apr 30 23:19:34 JST 1999

************************************************/

#ifndef SOCKPORT_H
#define SOCKPORT_H

#ifdef HAVE_STRUCT_SOCKADDR_SA_LEN
# define VALIDATE_SOCKLEN(addr, len) ((addr)->sa_len == (len))
#else
# define VALIDATE_SOCKLEN(addr, len) ((void)(addr), (void)(len), 1)
#endif

#ifdef HAVE_STRUCT_SOCKADDR_SA_LEN
# define SET_SA_LEN(sa, len) (void)((sa)->sa_len = (len))
#else
# define SET_SA_LEN(sa, len) (void)(len)
#endif

/* for strict-aliasing rule */
#ifdef HAVE_STRUCT_SOCKADDR_IN_SIN_LEN
# define SET_SIN_LEN(sa, len) (void)((sa)->sin_len = (len))
#else
# define SET_SIN_LEN(sa, len) SET_SA_LEN((struct sockaddr *)(sa), (len))
#endif

#ifdef HAVE_STRUCT_SOCKADDR_IN6_SIN6_LEN
# define SET_SIN6_LEN(sa, len) (void)((sa)->sin6_len = (len))
#else
# define SET_SIN6_LEN(sa, len) SET_SA_LEN((struct sockaddr *)(sa), (len))
#endif

#define INIT_SOCKADDR(addr, family, len) \
  do { \
    struct sockaddr *init_sockaddr_ptr = (addr); \
    socklen_t init_sockaddr_len = (len); \
    memset(init_sockaddr_ptr, 0, init_sockaddr_len); \
    init_sockaddr_ptr->sa_family = (family); \
    SET_SA_LEN(init_sockaddr_ptr, init_sockaddr_len); \
  } while (0)

#define INIT_SOCKADDR_IN(addr, len) \
  do { \
    struct sockaddr_in *init_sockaddr_ptr = (addr); \
    socklen_t init_sockaddr_len = (len); \
    memset(init_sockaddr_ptr, 0, init_sockaddr_len); \
    init_sockaddr_ptr->sin_family = AF_INET; \
    SET_SIN_LEN(init_sockaddr_ptr, init_sockaddr_len); \
  } while (0)

#define INIT_SOCKADDR_IN6(addr, len) \
  do { \
    struct sockaddr_in6 *init_sockaddr_ptr = (addr); \
    socklen_t init_sockaddr_len = (len); \
    memset(init_sockaddr_ptr, 0, init_sockaddr_len); \
    init_sockaddr_ptr->sin6_family = AF_INET6; \
    SET_SIN6_LEN(init_sockaddr_ptr, init_sockaddr_len); \
  } while (0)


/* for strict-aliasing rule */
#ifdef HAVE_TYPE_STRUCT_SOCKADDR_UN
#  ifdef HAVE_STRUCT_SOCKADDR_IN_SUN_LEN
#    define SET_SUN_LEN(sa, len) (void)((sa)->sun_len = (len))
#  else
#    define SET_SUN_LEN(sa, len) SET_SA_LEN((struct sockaddr *)(sa), (len))
#  endif
#  define INIT_SOCKADDR_UN(addr, len) \
     do { \
         struct sockaddr_un *init_sockaddr_ptr = (addr); \
         socklen_t init_sockaddr_len = (len); \
         memset(init_sockaddr_ptr, 0, init_sockaddr_len); \
         init_sockaddr_ptr->sun_family = AF_UNIX; \
         SET_SUN_LEN(init_sockaddr_ptr, init_sockaddr_len); \
     } while (0)
#endif

#ifndef IN_MULTICAST
# define IN_CLASSD(i)	(((long)(i) & 0xf0000000) == 0xe0000000)
# define IN_MULTICAST(i)	IN_CLASSD(i)
#endif

#ifndef IN_EXPERIMENTAL
# define IN_EXPERIMENTAL(i) ((((long)(i)) & 0xe0000000) == 0xe0000000)
#endif

#ifndef IN_CLASSA_NSHIFT
# define IN_CLASSA_NSHIFT 24
#endif

#ifndef IN_LOOPBACKNET
# define IN_LOOPBACKNET 127
#endif

#ifndef AF_UNSPEC
# define AF_UNSPEC 0
#endif

#ifndef PF_UNSPEC
# define PF_UNSPEC AF_UNSPEC
#endif

#ifndef PF_INET
# define PF_INET AF_INET
#endif

#if defined(HOST_NOT_FOUND) && !defined(h_errno) && !defined(__CYGWIN__)
extern int h_errno;
#endif

#endif
