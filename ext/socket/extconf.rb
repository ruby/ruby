require 'mkmf'

case RUBY_PLATFORM
when /(ms|bcc)win32|mingw/
  test_func = "WSACleanup"
  have_library("ws2_32", "WSACleanup")
when /cygwin/
  test_func = "socket"
when /beos/
  test_func = "socket"
  have_library("net", "socket")
when /haiku/
  test_func = "socket"
  have_library("network", "socket")
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
if have_header("arpa/inet.h")
  headers << "arpa/inet.h"
end

ipv6 = false
default_ipv6 = /mswin|cygwin|beos|haiku/ !~ RUBY_PLATFORM
if enable_config("ipv6", default_ipv6)
  if checking_for("ipv6") {try_link(<<EOF)}
#include <sys/types.h>
#ifndef _WIN32
#include <sys/socket.h>
#endif
int
main()
{
  socket(AF_INET6, SOCK_STREAM, 0);
}
EOF
    $defs << "-DENABLE_IPV6" << "-DINET6"
    ipv6 = true
  end
end

if ipv6
  if $mingw
    $CPPFLAGS << " -D_WIN32_WINNT=0x501"
  end
  ipv6lib = nil
  class << (fmt = "unknown")
    def %(s) s || self end
  end
  idirs, ldirs = dir_config("inet6", %w[/usr/inet6 /usr/local/v6].find {|d| File.directory?(d)})
  checking_for("ipv6 type", fmt) do
    if have_macro("IPV6_INRIA_VERSION", "netinet/in.h")
      "inria"
    elsif have_macro("__KAME__", "netinet/in.h")
      have_library(ipv6lib = "inet6")
      "kame"
    elsif have_macro("_TOSHIBA_INET6", "sys/param.h")
      have_library(ipv6lib = "inet6") and "toshiba"
    elsif have_macro("__V6D__", "sys/v6config.h")
      have_library(ipv6lib = "v6") and "v6d"
    elsif have_macro("_ZETA_MINAMI_INET6", "sys/param.h")
      have_library(ipv6lib = "inet6") and "zeta"
    elsif ipv6lib = with_config("ipv6-lib")
      warn <<EOS
--with-ipv6-lib and --with-ipv6-libdir option will be obsolete, use
--with-inet6lib and --with-inet6-{include,lib} options instead.
EOS
      find_library(ipv6lib, nil, with_config("ipv6-libdir", ldirs)) and
        ipv6lib
    elsif have_library("inet6")
      "inet6"
    end
  end or not ipv6lib or abort <<EOS

Fatal: no #{ipv6lib} library found.  cannot continue.
You need to fetch lib#{ipv6lib}.a from appropriate
ipv6 kit and compile beforehand.
EOS
end

if have_struct_member("struct sockaddr_in", "sin_len", headers)
  $defs[-1] = "-DHAVE_SIN_LEN"
end

#   doug's fix, NOW add -Dss_family... only if required!
doug = proc {have_struct_member("struct sockaddr_storage", "ss_family", headers)}
if (doug[] or
    with_cppflags($CPPFLAGS + " -Dss_family=__ss_family", &doug))
  $defs[-1] = "-DHAVE_SOCKADDR_STORAGE"
  doug = proc {have_struct_member("struct sockaddr_storage", "ss_len", headers)}
  doug[] or with_cppflags($CPPFLAGS + " -Dss_len=__ss_len", &doug)
end

if have_struct_member("struct sockaddr", "sa_len", headers)
  $defs[-1] = "-DHAVE_SA_LEN "
end

have_header("netinet/tcp.h") if /cygwin/ !~ RUBY_PLATFORM # for cygwin 1.1.5
have_header("netinet/udp.h")

if !have_macro("IPPROTO_IPV6", headers) && have_const("IPPROTO_IPV6", headers)
  IO.read(File.join(File.dirname(__FILE__), "mkconstants.rb")).sub(/\A.*^__END__$/m, '').split(/\r?\n/).grep(/\AIPPROTO_\w*/){$&}.each {|name|
    have_const(name, headers) unless $defs.include?("-DHAVE_CONST_#{name.upcase}")
  }
end

if (have_func("sendmsg") | have_func("recvmsg")) && /64-darwin/ !~ RUBY_PLATFORM
  # CMSG_ macros are broken on 64bit darwin, because of use of __DARWIN_ALIGN.
  have_struct_member('struct msghdr', 'msg_control', ['sys/types.h', 'sys/socket.h'])
  have_struct_member('struct msghdr', 'msg_accrights', ['sys/types.h', 'sys/socket.h'])
end

getaddr_info_ok = (enable_config("wide-getaddrinfo") && :wide) ||
  (checking_for("wide getaddrinfo") {try_run(<<EOF)} && :os)
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

int
main()
{
  int passive, gaierr, inet4 = 0, inet6 = 0;
  struct addrinfo hints, *ai, *aitop;
  char straddr[INET6_ADDRSTRLEN], strport[16];
#ifdef _WIN32
  WSADATA retdata;

  WSAStartup(MAKEWORD(2, 0), &retdata);
#endif

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
      if (ai->ai_addr == NULL)
        goto bad;
#if defined(_AIX)
      if (ai->ai_family == AF_INET6 && passive) {
        inet6++;
        continue;
      }
      ai->ai_addr->sa_len = ai->ai_addrlen;
      ai->ai_addr->sa_family = ai->ai_family;
#endif
      if (ai->ai_addrlen == 0 ||
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
if ipv6 and not getaddr_info_ok
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

have_type("struct addrinfo", headers)
have_func("freehostent")
have_func("freeaddrinfo")
if /haiku/ !~ RUBY_PLATFORM and have_func("gai_strerror")
  if checking_for("gai_strerror() returns const pointer") {!try_compile(<<EOF)}
#{cpp_include(headers)}
#include <stdlib.h>
void
conftest_gai_strerror_is_const()
{
    *gai_strerror(0) = 0;
}
EOF
    $defs << "-DGAI_STRERROR_CONST"
  end
end

$objs = [
  "init.#{$OBJEXT}",
  "constants.#{$OBJEXT}",
  "basicsocket.#{$OBJEXT}",
  "socket.#{$OBJEXT}",
  "ipsocket.#{$OBJEXT}",
  "tcpsocket.#{$OBJEXT}",
  "tcpserver.#{$OBJEXT}",
  "sockssocket.#{$OBJEXT}",
  "udpsocket.#{$OBJEXT}",
  "unixsocket.#{$OBJEXT}",
  "unixserver.#{$OBJEXT}",
  "option.#{$OBJEXT}",
  "ancdata.#{$OBJEXT}",
  "raddrinfo.#{$OBJEXT}"
]

if getaddr_info_ok == :wide or
    !have_func("getnameinfo", headers) or !have_func("getaddrinfo", headers)
  if have_struct_member("struct in6_addr", "s6_addr8", headers)
    $defs[-1] = "s6_addr=s6_addr8"
  end
  if ipv6 == "kame" && have_struct_member("struct in6_addr", "s6_addr32", headers)
    $defs[-1] = "-DFAITH"
  end
  $CPPFLAGS="-I. "+$CPPFLAGS
  $objs += ["getaddrinfo.#{$OBJEXT}"]
  $objs += ["getnameinfo.#{$OBJEXT}"]
  $defs << "-DGETADDRINFO_EMU"
  have_func("inet_ntop") or have_func("inet_ntoa")
  have_func("inet_pton") or have_func("inet_aton")
  have_func("getservbyport")
  have_header("arpa/nameser.h")
  have_header("resolv.h")
end

have_header("ifaddrs.h")
have_func("getifaddrs")
have_header("sys/ioctl.h")
have_header("sys/sockio.h")
have_header("net/if.h", headers)

have_header("sys/param.h", headers)
have_header("sys/ucred.h", headers)

unless have_type("socklen_t", headers)
  $defs << "-Dsocklen_t=int"
end

have_header("sys/un.h")
have_header("sys/uio.h")
have_type("struct in_pktinfo", headers) {|src|
  src.sub(%r'^/\*top\*/', '\1'"\n#if defined(IPPROTO_IP) && defined(IP_PKTINFO)") <<
  "#else\n" << "#error\n" << ">>>>>> no in_pktinfo <<<<<<\n" << "#endif\n"
} and have_struct_member("struct in_pktinfo", "ipi_spec_dst", headers)
have_type("struct in6_pktinfo", headers) {|src|
  src.sub(%r'^/\*top\*/', '\1'"\n#if defined(IPPROTO_IPV6) && defined(IPV6_PKTINFO)") <<
  "#else\n" << "#error\n" << ">>>>>> no in6_pktinfo <<<<<<\n" << "#endif\n"
}

have_type("struct sockcred", headers)
have_type("struct cmsgcred", headers)

have_func("getpeereid")

have_header("ucred.h", headers)
have_func("getpeerucred")

# workaround for recent Windows SDK
$defs << "-DIPPROTO_IPV6=IPPROTO_IPV6" if $defs.include?("-DHAVE_CONST_IPPROTO_IPV6") && !have_macro("IPPROTO_IPV6")

$distcleanfiles << "constants.h" << "constdefs.*"

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
