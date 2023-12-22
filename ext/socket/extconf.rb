# frozen_string_literal: false
require 'mkmf'

AF_INET6_SOCKET_CREATION_TEST = <<EOF
#include <sys/types.h>
#ifndef _WIN32
#include <sys/socket.h>
#endif
int
main(void)
{
  socket(AF_INET6, SOCK_STREAM, 0);
  return 0;
}
EOF

GETADDRINFO_GETNAMEINFO_TEST = <<EOF
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
main(void)
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
  return EXIT_SUCCESS;

 bad:
  if (aitop)
    freeaddrinfo(aitop);
  return EXIT_FAILURE;
}
EOF

RECVMSG_WITH_MSG_PEEK_ALLOCATE_FD_TEST = <<'EOF'
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    int ps[2], sv[2];
    int ret;
    ssize_t ss;
    int s_fd, r_fd;
    struct msghdr s_msg, r_msg;
    union {
        struct cmsghdr hdr;
        char dummy[CMSG_SPACE(sizeof(int))];
    } s_cmsg, r_cmsg;
    struct iovec s_iov, r_iov;
    char s_buf[1], r_buf[1];
    struct stat s_statbuf, r_statbuf;

    ret = pipe(ps);
    if (ret == -1) { perror("pipe"); exit(EXIT_FAILURE); }

    s_fd = ps[0];

    ret = socketpair(AF_UNIX, SOCK_DGRAM, 0, sv);
    if (ret == -1) { perror("socketpair"); exit(EXIT_FAILURE); }

    s_msg.msg_name = NULL;
    s_msg.msg_namelen = 0;
    s_msg.msg_iov = &s_iov;
    s_msg.msg_iovlen = 1;
    s_msg.msg_control = &s_cmsg;
    s_msg.msg_controllen = CMSG_SPACE(sizeof(int));;
    s_msg.msg_flags = 0;

    s_iov.iov_base = &s_buf;
    s_iov.iov_len = sizeof(s_buf);

    s_buf[0] = 'a';

    s_cmsg.hdr.cmsg_len = CMSG_LEN(sizeof(int));
    s_cmsg.hdr.cmsg_level = SOL_SOCKET;
    s_cmsg.hdr.cmsg_type = SCM_RIGHTS;
    memcpy(CMSG_DATA(&s_cmsg.hdr), (char *)&s_fd, sizeof(int));

    ss = sendmsg(sv[0], &s_msg, 0);
    if (ss == -1) { perror("sendmsg"); exit(EXIT_FAILURE); }

    r_msg.msg_name = NULL;
    r_msg.msg_namelen = 0;
    r_msg.msg_iov = &r_iov;
    r_msg.msg_iovlen = 1;
    r_msg.msg_control = &r_cmsg;
    r_msg.msg_controllen = CMSG_SPACE(sizeof(int));
    r_msg.msg_flags = 0;

    r_iov.iov_base = &r_buf;
    r_iov.iov_len = sizeof(r_buf);

    r_buf[0] = '0';

    memset(&r_cmsg, 0xff, CMSG_SPACE(sizeof(int)));

    ss = recvmsg(sv[1], &r_msg, MSG_PEEK);
    if (ss == -1) { perror("recvmsg"); exit(EXIT_FAILURE); }

    if (ss != 1) {
        fprintf(stderr, "unexpected return value from recvmsg: %ld\n", (long)ss);
        exit(EXIT_FAILURE);
    }
    if (r_buf[0] != 'a') {
        fprintf(stderr, "unexpected return data from recvmsg: 0x%02x\n", r_buf[0]);
        exit(EXIT_FAILURE);
    }

    if (r_msg.msg_controllen < CMSG_LEN(sizeof(int))) {
        fprintf(stderr, "unexpected: r_msg.msg_controllen < CMSG_LEN(sizeof(int)) not hold: %ld\n",
                (long)r_msg.msg_controllen);
        exit(EXIT_FAILURE);
    }
    if (r_cmsg.hdr.cmsg_len < CMSG_LEN(sizeof(int))) {
        fprintf(stderr, "unexpected: r_cmsg.hdr.cmsg_len < CMSG_LEN(sizeof(int)) not hold: %ld\n",
                (long)r_cmsg.hdr.cmsg_len);
        exit(EXIT_FAILURE);
    }
    memcpy((char *)&r_fd, CMSG_DATA(&r_cmsg.hdr), sizeof(int));

    if (r_fd < 0) {
        fprintf(stderr, "negative r_fd: %d\n", r_fd);
        exit(EXIT_FAILURE);
    }

    if (r_fd == s_fd) {
        fprintf(stderr, "r_fd and s_fd is same: %d\n", r_fd);
        exit(EXIT_FAILURE);
    }

    ret = fstat(s_fd, &s_statbuf);
    if (ret == -1) { perror("fstat(s_fd)"); exit(EXIT_FAILURE); }

    ret = fstat(r_fd, &r_statbuf);
    if (ret == -1) { perror("fstat(r_fd)"); exit(EXIT_FAILURE); }

    if (s_statbuf.st_dev != r_statbuf.st_dev ||
        s_statbuf.st_ino != r_statbuf.st_ino) {
        fprintf(stderr, "dev/ino doesn't match: s_fd:%ld/%ld r_fd:%ld/%ld\n",
                (long)s_statbuf.st_dev, (long)s_statbuf.st_ino,
                (long)r_statbuf.st_dev, (long)r_statbuf.st_ino);
        exit(EXIT_FAILURE);
    }

    return EXIT_SUCCESS;
}
EOF

def test_recvmsg_with_msg_peek_creates_fds(headers)
  case RUBY_PLATFORM
  when /linux/
    # Linux 2.6.38 allocate fds by recvmsg with MSG_PEEK.
    close_fds = true
  when /bsd|darwin/
    # FreeBSD 8.2.0, NetBSD 5 and MacOS X Snow Leopard doesn't
    # allocate fds by recvmsg with MSG_PEEK.
    # [ruby-dev:44189]
    # http://bugs.ruby-lang.org/issues/5075
    close_fds = false
  when /cygwin/
    # Cygwin doesn't support fd passing.
    # http://cygwin.com/ml/cygwin/2003-09/msg01808.html
    close_fds = false
  else
    close_fds = nil
  end
  if !CROSS_COMPILING
    if checking_for("recvmsg() with MSG_PEEK allocate file descriptors") {
        try_run(cpp_include(headers) + RECVMSG_WITH_MSG_PEEK_ALLOCATE_FD_TEST)
       }
      if close_fds == false
        warn "unexpected fd-passing recvmsg() with MSG_PEEK behavor on #{RUBY_PLATFORM}: fd allocation unexpected."
      elsif close_fds == nil
        puts "info: #{RUBY_PLATFORM} recvmsg() with MSG_PEEK allocates fds on fd-passing."
      end
      close_fds = true
    else
      if close_fds == true
        warn "unexpected fd-passing recvmsg() with MSG_PEEK behavor on #{RUBY_PLATFORM}: fd allocation expected."
      elsif close_fds == nil
        puts "info: #{RUBY_PLATFORM}: recvmsg() with MSG_PEEK doesn't allocates fds on fd-passing."
      end
      close_fds = false
    end
  end
  if close_fds == nil
    abort <<EOS
Fatal: cannot test fd-passing recvmsg() with MSG_PEEK behavor
because cross-compilation for #{RUBY_PLATFORM}.
If recvmsg() with MSG_PEEK allocates fds on fd passing:
--enable-close-fds-by-recvmsg-with-peek
If recvmsg() with MSG_PEEK doesn't allocate fds on fd passing:
--disable-close-fds-by-recvmsg-with-peek
EOS
  end
  close_fds
end

$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"

if /darwin/ =~ RUBY_PLATFORM
  # For IPv6 extension header access on OS X 10.7+ [Bug #8517]
  $CFLAGS << " -D__APPLE_USE_RFC_3542"
end

headers = []
unless $mswin or $mingw
  headers = %w<sys/types.h netdb.h string.h sys/socket.h netinet/in.h>
end

%w[
  sys/uio.h
  xti.h
  netinet/in_systm.h
  netinet/tcp.h
  netinet/tcp_fsm.h
  netinet/udp.h
  arpa/inet.h
  netpacket/packet.h
  net/ethernet.h
  sys/un.h
  afunix.h
  ifaddrs.h
  sys/ioctl.h
  sys/sockio.h
  net/if.h
  sys/param.h
  sys/ucred.h
  ucred.h
  net/if_dl.h
  arpa/nameser.h
  resolv.h
  pthread.h
  sched.h
].each {|h|
  if have_header(h, headers)
    headers << h
  end
}

have_struct_member("struct sockaddr", "sa_len", headers) # 4.4BSD
have_struct_member("struct sockaddr_in", "sin_len", headers) # 4.4BSD
have_struct_member("struct sockaddr_in6", "sin6_len", headers) # 4.4BSD

if have_type("struct sockaddr_un", headers) # POSIX
  have_struct_member("struct sockaddr_un", "sun_len", headers) # 4.4BSD
end

have_type("struct sockaddr_dl", headers) # AF_LINK address.  4.4BSD since Net2

have_type("struct sockaddr_storage", headers)

have_type("struct addrinfo", headers)

def check_socklen(headers)
  def (fmt = "none").%(x)
    x || self
  end
  s = checking_for("RSTRING_SOCKLEN", fmt) do
    if try_static_assert("sizeof(socklen_t) >= sizeof(long)", headers)
      "RSTRING_LEN"
    else
      "RSTRING_LENINT"
    end
  end
  $defs << "-DRSTRING_SOCKLEN=(socklen_t)"+s
end

if have_type("socklen_t", headers)
  check_socklen(headers)
end

have_type("struct in_pktinfo", headers) {|src|
  src.sub(%r'^/\*top\*/', '\&'"\n#if defined(IPPROTO_IP) && defined(IP_PKTINFO)") <<
  "#else\n" << "#error\n" << ">>>>>> no in_pktinfo <<<<<<\n" << "#endif\n"
} and have_struct_member("struct in_pktinfo", "ipi_spec_dst", headers)
have_type("struct in6_pktinfo", headers) {|src|
  src.sub(%r'^/\*top\*/', '\&'"\n#if defined(IPPROTO_IPV6) && defined(IPV6_PKTINFO)") <<
  "#else\n" << "#error\n" << ">>>>>> no in6_pktinfo <<<<<<\n" << "#endif\n"
}

have_type("struct sockcred", headers)
have_type("struct cmsgcred", headers)

have_type("struct ip_mreq", headers) # 4.4BSD
have_type("struct ip_mreqn", headers) # Linux 2.4
have_type("struct ipv6_mreq", headers) # RFC 3493

have_msg_control = nil
have_msg_control = have_struct_member('struct msghdr', 'msg_control', headers) unless $mswin or $mingw
have_struct_member('struct msghdr', 'msg_accrights', headers)

if have_type("struct tcp_info", headers)
  have_const("TCP_ESTABLISHED", headers)
  have_const("TCP_SYN_SENT", headers)
  have_const("TCP_SYN_RECV", headers)
  have_const("TCP_FIN_WAIT1", headers)
  have_const("TCP_FIN_WAIT2", headers)
  have_const("TCP_TIME_WAIT", headers)
  have_const("TCP_CLOSE", headers)
  have_const("TCP_CLOSE_WAIT", headers)
  have_const("TCP_LAST_ACK", headers)
  have_const("TCP_LISTEN", headers)
  have_const("TCP_CLOSING", headers)
  have_struct_member('struct tcp_info', 'tcpi_state', headers)
  if /solaris/ !~ RUBY_PLATFORM
    have_struct_member('struct tcp_info', 'tcpi_ca_state', headers)
  end
  have_struct_member('struct tcp_info', 'tcpi_retransmits', headers)
  have_struct_member('struct tcp_info', 'tcpi_probes', headers)
  have_struct_member('struct tcp_info', 'tcpi_backoff', headers)
  have_struct_member('struct tcp_info', 'tcpi_options', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_wscale', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_wscale', headers)
  have_struct_member('struct tcp_info', 'tcpi_rto', headers)
  have_struct_member('struct tcp_info', 'tcpi_ato', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_mss', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_mss', headers)
  have_struct_member('struct tcp_info', 'tcpi_unacked', headers)
  have_struct_member('struct tcp_info', 'tcpi_sacked', headers)
  have_struct_member('struct tcp_info', 'tcpi_lost', headers)
  have_struct_member('struct tcp_info', 'tcpi_retrans', headers)
  have_struct_member('struct tcp_info', 'tcpi_fackets', headers)
  have_struct_member('struct tcp_info', 'tcpi_last_data_sent', headers)
  have_struct_member('struct tcp_info', 'tcpi_last_ack_sent', headers)
  have_struct_member('struct tcp_info', 'tcpi_last_data_recv', headers)
  have_struct_member('struct tcp_info', 'tcpi_last_ack_recv', headers)
  have_struct_member('struct tcp_info', 'tcpi_pmtu', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_ssthresh', headers)
  have_struct_member('struct tcp_info', 'tcpi_rtt', headers)
  have_struct_member('struct tcp_info', 'tcpi_rttvar', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_ssthresh', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_cwnd', headers)
  have_struct_member('struct tcp_info', 'tcpi_advmss', headers)
  have_struct_member('struct tcp_info', 'tcpi_reordering', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_rtt', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_space', headers)
  have_struct_member('struct tcp_info', 'tcpi_total_retrans', headers)

  # FreeBSD extension
  have_struct_member('struct tcp_info', 'tcpi_snd_wnd', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_bwnd', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_nxt', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_nxt', headers)
  have_struct_member('struct tcp_info', 'tcpi_toe_tid', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_rexmitpack', headers)
  have_struct_member('struct tcp_info', 'tcpi_rcv_ooopack', headers)
  have_struct_member('struct tcp_info', 'tcpi_snd_zerowin', headers)
end

case RUBY_PLATFORM
when /mswin(32|64)|mingw/
  test_func = "WSACleanup"
  have_library("iphlpapi")
  have_library("ws2_32", "WSACleanup", headers)
when /cygwin/
  test_func = "socket(0,0,0)"
when /haiku/
  test_func = "socket(0,0,0)"
  have_library("network", "socket(0,0,0)", headers)
else
  test_func = "socket(0,0,0)"
  have_library("nsl", 't_open("", 0, (struct t_info *)NULL)', headers) # SunOS
  have_library("socket", "socket(0,0,0)", headers) # SunOS
end

if have_func(test_func, headers)

  have_func("sendmsg(0, (struct msghdr *)NULL, 0)", headers) # POSIX
  have_recvmsg = have_func("recvmsg(0, (struct msghdr *)NULL, 0)", headers) # POSIX

  have_func("freehostent((struct hostent *)NULL)", headers) # RFC 2553
  have_func("freeaddrinfo((struct addrinfo *)NULL)", headers) # RFC 2553

  if /haiku/ !~ RUBY_PLATFORM and
     have_func("gai_strerror(0)", headers) # POSIX
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

  have_func("accept4", headers)

  have_func('inet_ntop(0, (const void *)0, (char *)0, 0)', headers) or
    have_func("inet_ntoa(*(struct in_addr *)NULL)", headers)
  have_func('inet_pton(0, "", (void *)0)', headers) or
    have_func('inet_aton("", (struct in_addr *)0)', headers)
  have_func('getservbyport(0, "")', headers)
  have_func("getifaddrs((struct ifaddrs **)NULL)", headers)
  have_struct_member("struct if_data", "ifi_vhid", headers) # FreeBSD

  have_func("getpeereid", headers)

  have_func("getpeerucred(0, (ucred_t **)NULL)", headers) # SunOS

  have_func_decl = proc do |name, headers|
    # check if there is a declaration of <name> by trying to declare
    # both "int <name>(void)" and "void <name>(void)"
    # (at least one attempt should fail if there is a declaration)
    if !checking_for("declaration of #{name}()") {!%w[int void].all? {|ret| try_compile(<<EOF)}}
#{cpp_include(headers)}
#{ret} #{name}(void);
EOF
      $defs << "-DNEED_#{name.tr_cpp}_DECL"
    end
  end
  if have_func('if_indextoname(0, "")', headers)
    have_func_decl["if_indextoname", headers]
  end
  if have_func('if_nametoindex("")', headers)
    have_func_decl["if_nametoindex", headers]
  end

  have_func("hsterror", headers)
  have_func('getipnodebyname("", 0, 0, (int *)0)', headers) # RFC 2553
  have_func('gethostbyname2("", 0)', headers) # RFC 2133
  have_func("socketpair(0, 0, 0, 0)", headers)
  unless have_func("gethostname((char *)0, 0)", headers)
    have_func("uname((struct utsname *)NULL)", headers)
  end

  ipv6 = false
  default_ipv6 = /haiku/ !~ RUBY_PLATFORM
  if enable_config("ipv6", default_ipv6)
    if checking_for("ipv6") {try_link(AF_INET6_SOCKET_CREATION_TEST)}
      $defs << "-DENABLE_IPV6" << "-DINET6"
      ipv6 = true
    end
  end

  if ipv6
    if $mingw
      $CPPFLAGS << " -D_WIN32_WINNT=0x501" unless $CPPFLAGS.include?("_WIN32_WINNT")
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
      elsif have_library("inet6")
        "inet6"
      end
    end or not ipv6lib or abort <<EOS

Fatal: no #{ipv6lib} library found.  cannot continue.
You need to fetch lib#{ipv6lib}.a from appropriate
ipv6 kit and compile beforehand.
EOS
  end

  if !have_macro("IPPROTO_IPV6", headers) && have_const("IPPROTO_IPV6", headers)
    File.read(File.join(File.dirname(__FILE__), "mkconstants.rb")).sub(/\A.*^__END__$/m, '').split(/\r?\n/).grep(/\AIPPROTO_\w*/){$&}.each {|name|
      have_const(name, headers) unless $defs.include?("-DHAVE_CONST_#{name.upcase}")
    }
  end

  if enable_config("close-fds-by-recvmsg-with-peek") {
      have_msg_control && have_recvmsg &&
      have_const('AF_UNIX', headers) && have_const('SCM_RIGHTS', headers) &&
      test_recvmsg_with_msg_peek_creates_fds(headers)
     }
    $defs << "-DFD_PASSING_WORK_WITH_RECVMSG_MSG_PEEK"
  end

  case enable_config("wide-getaddrinfo")
  when true
    getaddr_info_ok = :wide
  when nil, false
    getaddr_info_ok = (:wide if getaddr_info_ok.nil?)
    if have_func("getnameinfo", headers) and have_func("getaddrinfo", headers)
      if CROSS_COMPILING ||
         $mingw || $mswin ||
         checking_for("system getaddrinfo working") {
           try_run(cpp_include(headers) + GETADDRINFO_GETNAMEINFO_TEST)
         }
        getaddr_info_ok = :os
      end
    end
  else
    raise "unexpected enable_config() value"
  end

  if ipv6 and not getaddr_info_ok
    abort <<EOS

Fatal: --enable-ipv6 is specified, and your OS seems to support IPv6 feature.
But your getaddrinfo() and getnameinfo() are appeared to be broken.  Sorry,
you cannot compile IPv6 socket classes with broken these functions.
You can try --enable-wide-getaddrinfo.
EOS
  end

  have_const('AI_ADDRCONFIG', headers)

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
    "raddrinfo.#{$OBJEXT}",
    "ifaddr.#{$OBJEXT}"
  ]

  if getaddr_info_ok == :wide
    if !have_type("struct in6_addr", headers) and have_type("struct in_addr6", headers)
      $defs.pop(2)
      $defs << "-Din_addr6=in6_addr"
    end
    if have_struct_member("struct in6_addr", "s6_addr8", headers)
      $defs[-1] = "-Ds6_addr=s6_addr8"
    end
    if ipv6 == "kame" && have_struct_member("struct in6_addr", "s6_addr32", headers)
      $defs[-1] = "-DFAITH"
    end
    $CPPFLAGS="-I. "+$CPPFLAGS
    $objs += ["getaddrinfo.#{$OBJEXT}"]
    $objs += ["getnameinfo.#{$OBJEXT}"]
    $defs << "-DGETADDRINFO_EMU"
  end

  # workaround for recent Windows SDK
  $defs << "-DIPPROTO_IPV6=IPPROTO_IPV6" if $defs.include?("-DHAVE_CONST_IPPROTO_IPV6") && !have_macro("IPPROTO_IPV6")

  $distcleanfiles << "constants.h" << "constdefs.*"

  if enable_config("socks", ENV["SOCKS_SERVER"])
    if have_library("socks5", "SOCKSinit")
      $defs << "-DSOCKS5" << "-DSOCKS"
    elsif have_library("socksd", "Rconnect") || have_library("socks", "Rconnect")
      $defs << "-DSOCKS"
    end
  end

  hdr = "netinet6/in6.h"
  /darwin/ =~ RUBY_PLATFORM and
  checking_for("if apple's #{hdr} needs s6_addr patch") {!try_compile(<<"SRC", nil, :werror=>true)} and
#include <netinet/in.h>
int t(struct in6_addr *addr) {return IN6_IS_ADDR_UNSPECIFIED(addr);}
SRC
  checking_for("fixing apple's #{hdr}", "%s") do
    file = xpopen(%w"clang -include netinet/in.h -E -xc -", in: IO::NULL) do |f|
      re = %r[^# *\d+ *"(.*/netinet/in\.h)"]
      Logging.message "  grep(#{re})\n"
      f.read[re, 1]
    end
    Logging.message "Substitute from #{file}\n"

    in6 = File.read(file)
    if in6.gsub!(/\*\(const\s+__uint32_t\s+\*\)\(const\s+void\s+\*\)\(&(\(\w+\))->s6_addr\[(\d+)\]\)/) do
        i, r = $2.to_i.divmod(4)
        if r.zero?
          "#$1->__u6_addr.__u6_addr32[#{i}]"
        else
          $&
        end
      end
      FileUtils.mkdir_p(File.dirname(hdr))
      File.write(hdr, in6)
      $distcleanfiles << hdr
      $distcleandirs << File.dirname(hdr)
      "done"
    else
      "not needed"
    end
  end

  have_func("pthread_create")
  have_func("pthread_detach")
  have_func("pthread_attr_setaffinity_np")
  have_func("sched_getcpu")

  $VPATH << '$(topdir)' << '$(top_srcdir)'
  create_makefile("socket")
end
