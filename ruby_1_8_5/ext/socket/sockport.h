/************************************************

  sockport.h -

  $Author: eban $
  $Date: 2000/08/24 06:29:30 $
  created at: Fri Apr 30 23:19:34 JST 1999

************************************************/

#ifndef SOCKPORT_H
#define SOCKPORT_H

#ifndef SA_LEN
# ifdef HAVE_SA_LEN
#  define SA_LEN(sa) (sa)->sa_len
# else
#  ifdef INET6
#   define SA_LEN(sa) \
	(((sa)->sa_family == AF_INET6) ? sizeof(struct sockaddr_in6) \
				       : sizeof(struct sockaddr))
#  else
    /* by tradition, sizeof(struct sockaddr) covers most of the sockaddrs */
#   define SA_LEN(sa)	(sizeof(struct sockaddr))
#  endif
# endif
#endif

#ifdef HAVE_SA_LEN
# define SET_SA_LEN(sa, len) (sa)->sa_len = (len)
#else
# define SET_SA_LEN(sa, len) (len)
#endif

#ifdef HAVE_SIN_LEN
# define SIN_LEN(si) (si)->sin_len
# define SET_SIN_LEN(si,len) (si)->sin_len = (len)
#else
# define SIN_LEN(si) sizeof(struct sockaddr_in)
# define SET_SIN_LEN(si,len)
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
