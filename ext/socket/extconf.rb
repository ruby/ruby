require 'mkmf'

case RUBY_PLATFORM
when /bccwin32/
  test_func = "WSACleanup"
  have_library("ws2_32", "WSACleanup")
  have_func("closesocket")
when /mswin32|mingw/
  test_func = "WSACleanup"
  have_library("wsock32", "WSACleanup")
  have_func("closesocket")
when /cygwin/
  test_func = "socket"
when /beos/
  test_func = "socket"
  have_library("net", "socket")
  have_func("closesocket")
when /i386-os2_emx/
  test_func = "socket"
  have_library("socket", "socket")
else
  test_func = "socket"
  have_library("nsl", "t_open")
  have_library("socket", "socket")
end

unless $mswin or $bccwin or $mingw
  headers = %w<sys/types.h netdb.h string.h sys/socket.h netinet/in.h>
end
if /solaris/ =~ RUBY_PLATFORM and !try_compile("")
  # bug of gcc 3.0 on Solaris 8 ?
  headers << "sys/feature_tests.h"
end

$ipv6 = false
default_ipv6 = /cygwin/ !~ RUBY_PLATFORM
if enable_config("ipv6", default_ipv6)
  if checking_for("ipv6") {try_link(<<EOF)}
#include <sys/types.h>
#include <sys/socket.h>
main()
{
  socket(AF_INET6, SOCK_STREAM, 0);
}
EOF
    $CPPFLAGS+=" -DENABLE_IPV6"
    $ipv6 = true
  end
end

$ipv6type = nil
$ipv6lib = nil
$ipv6libdir = nil
$ipv6trylibc = nil
if $ipv6
  if have_macro("IPV6_INRIA_VERSION", "netinet/in.h")
    $ipv6type = "inria"
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  elsif have_macro("__KAME__", "netinet/in.h")
    $ipv6type = "kame"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $ipv6trylibc=true
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  elsif File.directory? "/usr/inet6"
    $ipv6type = "linux"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/inet6/lib"
    $CPPFLAGS="-DINET6 -I/usr/inet6/include "+$CPPFLAGS
  elsif have_macro("_TOSHIBA_INET6", "sys/param.h")
    $ipv6type = "toshiba"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  elsif have_macro("__V6D__", "/usr/local/v6/include/sys/v6config.h")
    $ipv6type = "v6d"
    $ipv6lib="v6"
    $ipv6libdir="/usr/local/v6/lib"
    $CFLAGS="-I/usr/local/v6/include "+$CFLAGS
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  elsif have_macro("_ZETA_MINAMI_INET6", "sys/param.h")
    $ipv6type = "zeta"
    $ipv6lib="inet6"
    $ipv6libdir="/usr/local/v6/lib"
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  else
    $ipv6lib=with_config("ipv6-lib", nil)
    $ipv6libdir=with_config("ipv6-libdir", nil)
    $CPPFLAGS="-DINET6 "+$CPPFLAGS
  end
  
  if $ipv6lib
    if File.directory? $ipv6libdir and File.exist? "#{$ipv6libdir}/lib#{$ipv6lib}.a"
      $LOCAL_LIBS = " -L#$ipv6libdir -l#$ipv6lib"
    elsif !$ipv6trylibc
      abort <<EOS
Fatal: no #$ipv6lib library found.  cannot continue.
You need to fetch lib#{$ipv6lib}.a from appropriate
ipv6 kit and compile beforehand.
EOS
    end
  end
end

if have_struct_member("struct sockaddr_in", "sin_len", headers)
  $defs[-1] = "-DHAVE_SIN_LEN"
end

#   doug's fix, NOW add -Dss_family... only if required!
doug = proc {have_struct_member("struct sockaddr_storage", "ss_family", headers)}
if /mswin32|mingw/ !~ RUBY_PLATFORM and
   (doug[] or
    with_cppflags($CPPFLAGS + " -Dss_family=__ss_family -Dss_len=__ss_len", &doug))
  $defs[-1] = "-DHAVE_SOCKADDR_STORAGE"
end

if have_struct_member("struct sockaddr", "sa_len", headers)
  $defs[-1] = "-DHAVE_SA_LEN "
end

have_header("netinet/tcp.h") if not /cygwin/ =~ RUBY_PLATFORM # for cygwin 1.1.5
have_header("netinet/udp.h")

if have_func("sendmsg") | have_func("recvmsg")
  have_struct_member('struct msghdr', 'msg_control', ['sys/types.h', 'sys/socket.h'])
  have_struct_member('struct msghdr', 'msg_accrights', ['sys/types.h', 'sys/socket.h'])
end

getaddr_info_ok = enable_config("wide-getaddrinfo") do
  checking_for("wide getaddrinfo") {try_run(<<EOF)}
#{cpp_include(headers)}
#include <stdlib.h>

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif
#ifndef EXIT_FAILURE
#define EXIT_FAILURE 1
#endif

#ifndef AF_LOCAL
#define AF_LOCAL AF_UNIX
#endif

main()
{
  int passive, gaierr, inet4 = 0, inet6 = 0;
  struct addrinfo hints, *ai, *aitop;
  char straddr[INET6_ADDRSTRLEN], strport[16];

  for (passive = 0; passive <= 1; passive++) {
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = passive ? AI_PASSIVE : 0;
    hints.ai_socktype = SOCK_STREAM;
    if ((gaierr = getaddrinfo(NULL, "54321", &hints, &aitop)) != 0) {
      (void)gai_strerror(gaierr);
      goto bad;
    }
    for (ai = aitop; ai; ai = ai->ai_next) {
      if (ai->ai_family == AF_LOCAL) continue;
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

  if (!(inet4 == 0 || inet4 == 2))
    goto bad;
  if (!(inet6 == 0 || inet6 == 2))
    goto bad;

  if (aitop)
    freeaddrinfo(aitop);
  exit(EXIT_SUCCESS);

 bad:
  if (aitop)
    freeaddrinfo(aitop);
  exit(EXIT_FAILURE);
}
EOF
end
if $ipv6 and not getaddr_info_ok
  abort <<EOS

Fatal: --enable-ipv6 is specified, and your OS seems to support IPv6 feature.
But your getaddrinfo() and getnameinfo() are appeared to be broken.  Sorry,
you cannot compile IPv6 socket classes with broken these functions.
You can try --enable-wide-getaddrinfo.
EOS
end

case with_config("lookup-order-hack", "UNSPEC")
when "INET"
  $defs << "-DLOOKUP_ORDER_HACK_INET"
when "INET6"
  $defs << "-DLOOKUP_ORDER_HACK_INET6"
when "UNSPEC"
  # nothing special
else
  abort <<EOS

Fatal: invalid value for --with-lookup-order-hack (expected INET, INET6 or UNSPEC)
EOS
end

$objs = ["socket.#{$OBJEXT}"]

unless getaddr_info_ok and have_func("getnameinfo", "netdb.h") and have_func("getaddrinfo", "netdb.h")
  if have_struct_member("struct in6_addr", "s6_addr8", headers)
    $defs[-1] = "-DHAVE_ADDR8"
  end
  $CPPFLAGS="-I. "+$CPPFLAGS
  $objs += ["getaddrinfo.#{$OBJEXT}"]
  $objs += ["getnameinfo.#{$OBJEXT}"]
  have_func("inet_ntop") or have_func("inet_ntoa")
  have_func("inet_pton") or have_func("inet_aton")
  have_func("getservbyport")
  have_header("arpa/inet.h")
  have_header("arpa/nameser.h")
  have_header("resolv.h")
end

unless have_type("socklen_t", headers)
  $defs << "-Dsocklen_t=int"
end

have_header("sys/un.h")
have_header("sys/uio.h")

if have_func(test_func)
  have_func("hsterror")
  have_func("getipnodebyname") or have_func("gethostbyname2")
  have_func("socketpair")
  unless have_func("gethostname")
    have_func("uname")
  end
  if enable_config("socks", ENV["SOCKS_SERVER"])
    if have_library("socks5", "SOCKSinit")
      $defs << "-DSOCKS5" << "-DSOCKS"
    elsif have_library("socks", "Rconnect")
      $defs << "-DSOCKS"
    end
  end
  create_makefile("socket")
end
