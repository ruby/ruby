require 'optparse'
require 'erb'

opt = OptionParser.new

opt.def_option('-h', 'help') {
  puts opt
  exit 0
}

opt_o = nil
opt.def_option('-o FILE', 'specify output file') {|filename|
  opt_o = filename
}

C_ESC = {
  "\\" => "\\\\",
  '"' => '\"',
  "\n" => '\n',
}

0x00.upto(0x1f) {|ch| C_ESC[[ch].pack("C")] ||= "\\%03o" % ch }
0x7f.upto(0xff) {|ch| C_ESC[[ch].pack("C")] = "\\%03o" % ch }
C_ESC_PAT = Regexp.union(*C_ESC.keys)

def c_str(str)
  '"' + str.gsub(C_ESC_PAT, C_ESC) + '"'
end

opt.parse!

result = ''

# workaround for NetBSD, OpenBSD and etc.
result << "#define pseudo_AF_FTIP pseudo_AF_RTIP\n"

DEFS = []
DATA.each_line {|s|
  name, default_value = s.scan(/\S+/)
  next unless name && name[0] != ?#
  DEFS << [name, default_value]
}

def each_const
  DEFS.each {|name, default_value|
    if name =~ /\AINADDR_/
      define = "sock_define_uconst"
    else
      define = "sock_define_const"
    end
    guard = nil
    if /\A(AF_INET6|PF_INET6)\z/ =~ name
      # IPv6 is not supported although AF_INET6 is defined on bcc32/mingw
      guard = "defined(INET6)"
    end
    yield guard, define, name, default_value
  }
end

def each_name(pat)
  DEFS.each {|name, default_value|
    next if pat !~ name
    yield name
  }
end

def each_names_with_len(pat)
  h = {}
  DEFS.each {|name, default_value|
    next if pat !~ name
    (h[name.length] ||= []) << name
  }
  h.keys.sort.each {|len|
    yield h[len], len
  }
end

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int(str_var, len_var, retp_var, pat)")
    switch (<%=len_var%>) {
%    each_names_with_len(pat) {|names, len|
      case <%=len%>:
%      names.each {|name|
#ifdef <%=name%>
%       size = name.bytesize
        if (memcmp(<%=str_var%>, <%=c_str name%>, <%=size%>) == 0) { *<%=retp_var%> = <%=name%>; return 0; }
#endif
%      }
        return -1;

%    }
      default:
        return -1;
    }
EOS

MAYBE_ALIAS = [
  ["AF_UNIX", "AF_LOCAL"],
  ["AF_ISO", "AF_OSI"],
  ["AF_E164", "AF_ISDN"],
  ["AF_NS", "AF_IPX"],
]

def each_alias(pat)
  h = {}
  each_name(pat) {|name|
    h[name] = [name]
  }
  MAYBE_ALIAS.each {|names|
    a = []
    names.each {|n|
      a << n if h.delete n
    }
    h[a.first] = a
  }
  h.each_value {|names|
    yield names
  }
end

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name(int_var, pat)")
    switch (<%=int_var%>) {
%    each_alias(pat) {|names|
%      names.each_with_index {|n, i|
%      cond = ["defined(#{n})"]
%      (0...i).each {|j| cond << "(!defined(#{names[j]}) || #{n} != #{names[j]})" }
#if <%=cond.join(" && ")%>
      case <%=n%>: return <%=c_str n%>;
#endif
%      }
%    }
      default:
        return NULL;
    }
EOS

result << ERB.new(<<'EOS', nil, '%').result(binding)
static void
init_constants(VALUE mConst)
{
% each_const {|guard, define, name, default_value|
%   if guard
#if <%=guard%>
%   end
#if defined(<%=name%>)
    <%=define%>(<%=c_str name%>, <%=name%>);
%   if default_value
#else
    <%=define%>(<%=c_str name%>, <%=default_value%>);
%   end
#endif
%   if guard
#endif
%   end

% }
}

static int
family_to_int(char *str, int len, int *valp)
{
<%= gen_name_to_int("str", "len", "valp", /\A[AP]F_/) %>
}

static int
socktype_to_int(char *str, int len, int *valp)
{
<%= gen_name_to_int("str", "len", "valp", /\ASOCK_/) %>
}

static char *
family_to_str(int val)
{
<%= gen_int_to_name("val", /\AAF_/) %>
}

EOS

if opt_o
  File.open(opt_o, 'w') {|f|
    f << result
  }
else
  $stdout << result
end

__END__

SOCK_STREAM
SOCK_DGRAM
SOCK_RAW
SOCK_RDM
SOCK_SEQPACKET
SOCK_PACKET

AF_INET
PF_INET
AF_INET6
PF_INET6
AF_UNIX
PF_UNIX
AF_AX25
PF_AX25
AF_IPX
PF_IPX
AF_APPLETALK
PF_APPLETALK
AF_UNSPEC
PF_UNSPEC
AF_LOCAL
PF_LOCAL
AF_IMPLINK
PF_IMPLINK
AF_PUP
PF_PUP
AF_CHAOS
PF_CHAOS
AF_NS
PF_NS
AF_ISO
PF_ISO
AF_OSI
PF_OSI
AF_ECMA
PF_ECMA
AF_DATAKIT
PF_DATAKIT
AF_CCITT
PF_CCITT
AF_SNA
PF_SNA
AF_DEC
PF_DEC
AF_DLI
PF_DLI
AF_LAT
PF_LAT
AF_HYLINK
PF_HYLINK
AF_ROUTE
PF_ROUTE
AF_LINK
PF_LINK
AF_COIP
PF_COIP
AF_CNT
PF_CNT
AF_SIP
PF_SIP
AF_NDRV
PF_NDRV
AF_ISDN
PF_ISDN
AF_NATM
PF_NATM
AF_SYSTEM
PF_SYSTEM
AF_NETBIOS
PF_NETBIOS
AF_PPP
PF_PPP
AF_ATM
PF_ATM
AF_NETGRAPH
PF_NETGRAPH
AF_MAX
PF_MAX

AF_E164
PF_XTP
PF_RTIP
PF_PIP
PF_KEY

MSG_OOB
MSG_PEEK
MSG_DONTROUTE
MSG_EOR
MSG_TRUNC
MSG_CTRUNC
MSG_WAITALL
MSG_DONTWAIT
MSG_EOF
MSG_FLUSH
MSG_HOLD
MSG_SEND
MSG_HAVEMORE
MSG_RCVMORE
MSG_COMPAT

SOL_SOCKET
SOL_IP
SOL_IPX
SOL_AX25
SOL_ATALK
SOL_TCP
SOL_UDP

IPPROTO_IP	0
IPPROTO_ICMP	1
IPPROTO_IGMP
IPPROTO_GGP
IPPROTO_TCP	6
IPPROTO_EGP
IPPROTO_PUP
IPPROTO_UDP	17
IPPROTO_IDP
IPPROTO_HELLO
IPPROTO_ND
IPPROTO_TP
IPPROTO_XTP
IPPROTO_EON
IPPROTO_BIP
IPPROTO_AH
IPPROTO_DSTOPTS
IPPROTO_ESP
IPPROTO_FRAGMENT
IPPROTO_HOPOPTS
IPPROTO_ICMPV6
IPPROTO_IPV6
IPPROTO_NONE
IPPROTO_ROUTING

IPPROTO_RAW	255
IPPROTO_MAX

# Some port configuration
IPPORT_RESERVED		1024
IPPORT_USERRESERVED	5000

# Some reserved IP v.4 addresses
INADDR_ANY		0x00000000
INADDR_BROADCAST	0xffffffff
INADDR_LOOPBACK		0x7F000001
INADDR_UNSPEC_GROUP	0xe0000000
INADDR_ALLHOSTS_GROUP	0xe0000001
INADDR_MAX_LOCAL_GROUP	0xe00000ff
INADDR_NONE		0xffffffff

# IP [gs]etsockopt options
IP_OPTIONS
IP_HDRINCL
IP_TOS
IP_TTL
IP_RECVOPTS
IP_RECVRETOPTS
IP_RECVDSTADDR
IP_RETOPTS
IP_MULTICAST_IF
IP_MULTICAST_TTL
IP_MULTICAST_LOOP
IP_ADD_MEMBERSHIP
IP_DROP_MEMBERSHIP
IP_DEFAULT_MULTICAST_TTL
IP_DEFAULT_MULTICAST_LOOP
IP_MAX_MEMBERSHIPS

SO_DEBUG
SO_REUSEADDR
SO_REUSEPORT
SO_TYPE
SO_ERROR
SO_DONTROUTE
SO_BROADCAST
SO_SNDBUF
SO_RCVBUF
SO_KEEPALIVE
SO_OOBINLINE
SO_NO_CHECK
SO_PRIORITY
SO_LINGER
SO_PASSCRED
SO_PEERCRED
SO_RCVLOWAT
SO_SNDLOWAT
SO_RCVTIMEO
SO_SNDTIMEO
SO_ACCEPTCONN
SO_USELOOPBACK
SO_ACCEPTFILTER
SO_DONTTRUNC
SO_WANTMORE
SO_WANTOOBFLAG
SO_NREAD
SO_NKE
SO_NOSIGPIPE
SO_SECURITY_AUTHENTICATION
SO_SECURITY_ENCRYPTION_TRANSPORT
SO_SECURITY_ENCRYPTION_NETWORK
SO_BINDTODEVICE
SO_ATTACH_FILTER
SO_DETACH_FILTER
SO_PEERNAME
SO_TIMESTAMP

SOPRI_INTERACTIVE
SOPRI_NORMAL
SOPRI_BACKGROUND

IPX_TYPE

TCP_NODELAY
TCP_MAXSEG

EAI_ADDRFAMILY
EAI_AGAIN
EAI_BADFLAGS
EAI_FAIL
EAI_FAMILY
EAI_MEMORY
EAI_NODATA
EAI_NONAME
EAI_OVERFLOW
EAI_SERVICE
EAI_SOCKTYPE
EAI_SYSTEM
EAI_BADHINTS
EAI_PROTOCOL
EAI_MAX

AI_PASSIVE
AI_CANONNAME
AI_NUMERICHOST
AI_NUMERICSERV
AI_MASK
AI_ALL
AI_V4MAPPED_CFG
AI_ADDRCONFIG
AI_V4MAPPED
AI_DEFAULT

NI_MAXHOST
NI_MAXSERV
NI_NOFQDN
NI_NUMERICHOST
NI_NAMEREQD
NI_NUMERICSERV
NI_DGRAM

SHUT_RD		0
SHUT_WR		1
SHUT_RDWR	2

IPV6_JOIN_GROUP
IPV6_LEAVE_GROUP
IPV6_MULTICAST_HOPS
IPV6_MULTICAST_IF
IPV6_MULTICAST_LOOP
IPV6_UNICAST_HOPS
IPV6_V6ONLY
IPV6_CHECKSUM
IPV6_DONTFRAG
IPV6_DSTOPTS
IPV6_HOPLIMIT
IPV6_HOPOPTS
IPV6_NEXTHOP
IPV6_PATHMTU
IPV6_PKTINFO
IPV6_RECVDSTOPTS
IPV6_RECVHOPLIMIT
IPV6_RECVHOPOPTS
IPV6_RECVPKTINFO
IPV6_RECVRTHDR
IPV6_RECVTCLASS
IPV6_RTHDR
IPV6_RTHDRDSTOPTS
IPV6_RTHDR_TYPE_0
IPV6_RECVPATHMTU
IPV6_TCLASS
IPV6_USE_MIN_MTU

INET_ADDRSTRLEN
INET6_ADDRSTRLEN
