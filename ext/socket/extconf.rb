require 'mkmf'
$LDFLAGS = "-L/usr/local/lib" if File.directory?("/usr/local/lib")
$CFLAGS ||= ""
$CFLAGS+=" -Dss_family=__ss_family -Dss_len=__ss_len"

case PLATFORM
when /mswin32/
  test_func = "WSACleanup"
  have_library("wsock32", "WSACleanup")
when /cygwin32/
  test_func = "socket"
when /beos/
  test_func = "socket"
  have_library("net", "socket")
when /i386-os2_emx/
  test_func = "socket"
  have_library("socket", "socket")
else
  test_func = "socket"
  have_library("nsl", "t_open")
  have_library("socket", "socket")
end

$ipv6 = false
if enable_config("ipv6", "yes")
  if try_run(<<EOF)
#include <sys/types.h>
#include <sys/socket.h>
main()
{
  exit(0);
 if (socket(AF_INET6, SOCK_STREAM, 0) < 0)
   exit(1);
 else
   exit(0);
}
EOF
    $CFLAGS+=" -DENABLE_IPV6"
    $ipv6 = true
  end
end

$ipv6type = nil
$ipv6lib = nil
$ipv6libdir = nil
if $ipv6
  if egrep_cpp("yes", <<EOF)
#include <netinet/in.h>
#ifdef IPV6_INRIA_VERSION
yes
#endif
EOF
    $ipv6type = "inria"
    $CFLAGS="-DINET6 "+$CFLAGS
  elsif egrep_cpp("yes", <<EOF)
#include <netinet/in.h>
#ifdef __KAME__
yes
#endif
EOF
    $ipv6type = "kame"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $CFLAGS="-DINET6 "+$CFLAGS
  elsif File.directory? "/usr/inet6"
    $ipv6type = "linux"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/inet6/lib"
    $CFLAGS="-DINET6 -I/usr/inet6/include "+$CFLAGS
  elsif egrep_cpp("yes", <<EOF)
#include <sys/param.h>
#ifdef _TOSHIBA_INET6
yes
#endif
EOF
    $ipv6type = "toshiba"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $CFLAGS="-DINET6 "+$CFLAGS
  elsif egrep_cpp("yes", <<EOF)
#include </usr/local/v6/include/sys/v6config.h>
#ifdef __V6D__
yes
#endif
EOF
    $ipv6type = "v6d"
    $ipv6lib="v6"
    $ipv6libdir="/usr/local/v6/lib"
    $CFLAGS="-DINET6 -I/usr/local/v6/include "+$CFLAGS
  elsif egrep_cpp("yes", <<EOF)
#include <sys/param.h>
#ifdef _ZETA_MINAMI_INET6
yes
#endif
EOF
    $ipv6type = "zeta"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $CFLAGS="-DINET6 "+$CFLAGS
  end
  
  if $ipv6lib
    if File.directory? $ipv6libdir and File.exist? "#{$ipv6libdir}/#{ipv6lib}.a"
      $LDFLAGS += " -L#$ipv6libdir -l#$ipv6lib"
    else
      print <<EOS
Fatal: no #$ipv6lib library found.  cannot continue.
You need to fetch lib#{$ipv6lib}.a from appropriate
ipv6 kit and compile beforehand.
EOS
      exit
    end
  end
end

  if try_link(<<EOF)
#include <sys/types.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
int
main()
{
   struct sockaddr_in sin;

   sin.sin_len;
   return 0;
}
EOF
    $CFLAGS="-DHAVE_SIN_LEN "+$CFLAGS
end

  if try_link(<<EOF)
#include <sys/types.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
int
main()
{
   struct sockaddr sa;

   sa.sa_len;
   return 0;
}
EOF
    $CFLAGS="-DHAVE_SA_LEN "+$CFLAGS
end

$getaddr_info_ok = false
if try_run(<<EOF)
#include <sys/types.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

main()
{
  int passive, gaierr, inet4 = 0, inet6 = 0;
  struct addrinfo hints, *ai, *aitop;
  char straddr[INET6_ADDRSTRLEN], strport[16];

  for (passive = 0; passive <= 1; passive++) {
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = passive ? AI_PASSIVE : 0;
    hints.ai_socktype = SOCK_STREAM;
    if ((gaierr = getaddrinfo(NULL, "54321", &hints, &aitop)) != 0) {
      (void)gai_strerror(gaierr);
      goto bad;
    }
    for (ai = aitop; ai; ai = ai->ai_next) {
      if (ai->ai_addr == NULL ||
          ai->ai_addrlen == 0 ||
          getnameinfo(ai->ai_addr, ai->ai_addrlen,
                      straddr, sizeof(straddr), strport, sizeof(strport),
                      NI_NUMERICHOST|NI_NUMERICSERV) != 0) {
        goto bad;
      }
      if (strcmp(strport, "54321") != 0) {
        goto bad;
      }
      switch (ai->ai_family) {
      case AF_INET:
        if (passive) {
          if (strcmp(straddr, "0.0.0.0") != 0) {
            goto bad;
          }
        } else {
          if (strcmp(straddr, "127.0.0.1") != 0) {
            goto bad;
          }
        }
        inet4++;
        break;
      case AF_INET6:
        if (passive) {
          if (strcmp(straddr, "::") != 0) {
            goto bad;
          }
        } else {
          if (strcmp(straddr, "::1") != 0) {
            goto bad;
          }
        }
        inet6++;
        break;
      case AF_UNSPEC:
        goto bad;
        break;
      default:
        /* another family support? */
        break;
      }
    }
  }

  if (inet6 != 2 || inet4 != 2)
    goto bad;

  if (aitop)
    freeaddrinfo(aitop);
  exit(0);

 bad:
  if (aitop)
    freeaddrinfo(aitop);
  exit(1);
}
EOF
  $getaddr_info_ok = true
end

$objs = ["socket.o"]
    
if $getaddr_info_ok
  have_func("getaddrinfo")
  have_func("getnameinfo")
else
  $objs += "getaddrinfo.o"
  $objs += "getnameinfo.o"
end

have_header("sys/un.h")
if have_func(test_func)
  have_func("inet_aton")
  have_func("hsterror")
  unless have_func("gethostname")
    have_func("uname")
  end
  if ENV["SOCKS_SERVER"]  # test if SOCKSsocket needed
    if have_library("socks", "Rconnect")
      $CFLAGS="-DSOCKS"
    end
  end
  create_makefile("socket")
end
