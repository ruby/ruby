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

opt_H = nil
opt.def_option('-H FILE', 'specify output header file') {|filename|
  opt_H = filename
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
  '"' + str.gsub(C_ESC_PAT) {|s| C_ESC[s]} + '"'
end

opt.parse!



h = {}
DATA.each_line {|s|
  name, default_value = s.scan(/\S+/)
  next unless name && name[0] != ?#
  if h.has_key? name
    warn "#{$.}: warning: duplicate name: #{name}"
    next
  end
  h[name] = default_value
}
DEFS = h.to_a

def each_const
  DEFS.each {|name, default_value|
    if name =~ /\AINADDR_/
      make_value = "UINT2NUM"
    else
      make_value = "INT2NUM"
    end
    guard = nil
    if /\A(AF_INET6|PF_INET6|IPV6_.*)\z/ =~ name
      # IPv6 is not supported although AF_INET6 is defined on bcc32/mingw
      guard = "defined(INET6)"
    end
    yield guard, make_value, name, default_value
  }
end

def each_name(pat)
  DEFS.each {|name, default_value|
    next if pat !~ name
    yield name
  }
end

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_const_decls")
% each_const {|guard, make_value, name, default_value|
#if !defined(<%=name%>)
# if defined(HAVE_CONST_<%=name.upcase%>)
#  define <%=name%> <%=name%>
%if default_value
# else
#  define <%=name%> <%=default_value%>
%end
# endif
#endif
% }
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_const_defs_in_guard(make_value, name, default_value)")
#if defined(<%=name%>)
    /* <%=name%>: */
    rb_define_const(rb_cSocket, <%=c_str name%>, <%=make_value%>(<%=name%>));
    /* <%=name%>: */
    rb_define_const(rb_mSockConst, <%=c_str name%>, <%=make_value%>(<%=name%>));
#endif
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_const_defs")
% each_const {|guard, make_value, name, default_value|
%   if guard
#if <%=guard%>
<%= gen_const_defs_in_guard(make_value, name, default_value).chomp %>
#endif
%   else
<%= gen_const_defs_in_guard(make_value, name, default_value).chomp %>
%   end
% }
EOS

def reverse_each_name(pat)
  DEFS.reverse_each {|name, default_value|
    next if pat !~ name
    yield name
  }
end

def each_names_with_len(pat, prefix_optional=nil)
  h = {}
  DEFS.each {|name, default_value|
    next if pat !~ name
    (h[name.length] ||= []) << [name, name]
  }
  if prefix_optional
    if Regexp === prefix_optional
      prefix_pat = prefix_optional
    else
      prefix_pat = /\A#{Regexp.escape prefix_optional}/
    end
    DEFS.each {|const, default_value|
      next if pat !~ const
      next if prefix_pat !~ const
      name = $'
      (h[name.length] ||= []) << [name, const]
    }
  end
  hh = {}
  h.each {|len, pairs|
    pairs.each {|name, const|
      raise "name crash: #{name}" if hh[name]
      hh[name] = true
    }
  }
  h.keys.sort.each {|len|
    yield h[len], len
  }
end

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_decl(funcname, pat, prefix_optional, guard=nil)")
%if guard
#ifdef <%=guard%>
int <%=funcname%>(const char *str, long len, int *valp);
#endif
%else
int <%=funcname%>(const char *str, long len, int *valp);
%end
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_func_in_guard(funcname, pat, prefix_optional, guard=nil)")
int
<%=funcname%>(const char *str, long len, int *valp)
{
    switch (len) {
%    each_names_with_len(pat, prefix_optional) {|pairs, len|
      case <%=len%>:
%      pairs.each {|name, const|
#ifdef <%=const%>
        if (memcmp(str, <%=c_str name%>, <%=len%>) == 0) { *valp = <%=const%>; return 0; }
#endif
%      }
        return -1;

%    }
      default:
        return -1;
    }
}
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_func(funcname, pat, prefix_optional, guard=nil)")
%if guard
#ifdef <%=guard%>
<%=gen_name_to_int_func_in_guard(funcname, pat, prefix_optional, guard)%>
#endif
%else
<%=gen_name_to_int_func_in_guard(funcname, pat, prefix_optional, guard)%>
%end
EOS

NAME_TO_INT_DEFS = []
def def_name_to_int(funcname, pat, prefix_optional, guard=nil)
  decl = gen_name_to_int_decl(funcname, pat, prefix_optional, guard)
  func = gen_name_to_int_func(funcname, pat, prefix_optional, guard)
  NAME_TO_INT_DEFS << [decl, func]
end

def reverse_each_name_with_prefix_optional(pat, prefix_pat)
  reverse_each_name(pat) {|n|
    yield n, n
  }
  if prefix_pat
    reverse_each_name(pat) {|n|
      next if prefix_pat !~ n
      yield n, $'
    }
  end
end

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_hash(hash_var, pat, prefix_pat)")
    <%=hash_var%> = st_init_numtable();
% reverse_each_name_with_prefix_optional(pat, prefix_pat) {|n,s|
#ifdef <%=n%>
    st_insert(<%=hash_var%>, (st_data_t)<%=n%>, (st_data_t)rb_intern2(<%=c_str s%>, <%=s.length%>));
#endif
% }
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_func(func_name, hash_var)")
ID
<%=func_name%>(int val)
{
    st_data_t name;
    if (st_lookup(<%=hash_var%>, (st_data_t)val, &name))
        return (ID)name;
    return 0;
}
EOS

ERB.new(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_decl(func_name, hash_var)")
ID <%=func_name%>(int val);
EOS

INTERN_DEFS = []
def def_intern(func_name, pat, prefix_optional=nil)
  prefix_pat = nil
  if prefix_optional
    if Regexp === prefix_optional
      prefix_pat = prefix_optional
    else
      prefix_pat = /\A#{Regexp.escape prefix_optional}/
    end
  end
  hash_var = "#{func_name}_hash"
  vardef = "static st_table *#{hash_var};"
  gen_hash = gen_int_to_name_hash(hash_var, pat, prefix_pat)
  decl = gen_int_to_name_decl(func_name, hash_var)
  func = gen_int_to_name_func(func_name, hash_var)
  INTERN_DEFS << [vardef, gen_hash, decl, func]
end

def_name_to_int("rsock_family_to_int", /\A(AF_|PF_)/, "AF_")
def_name_to_int("rsock_socktype_to_int", /\ASOCK_/, "SOCK_")
def_name_to_int("rsock_ipproto_to_int", /\AIPPROTO_/, "IPPROTO_")
def_name_to_int("rsock_unknown_level_to_int", /\ASOL_SOCKET\z/, "SOL_")
def_name_to_int("rsock_ip_level_to_int", /\A(SOL_SOCKET\z|IPPROTO_)/, /\A(SOL_|IPPROTO_)/)
def_name_to_int("rsock_so_optname_to_int", /\ASO_/, "SO_")
def_name_to_int("rsock_ip_optname_to_int", /\AIP_/, "IP_")
def_name_to_int("rsock_ipv6_optname_to_int", /\AIPV6_/, "IPV6_", "IPPROTO_IPV6")
def_name_to_int("rsock_tcp_optname_to_int", /\ATCP_/, "TCP_")
def_name_to_int("rsock_udp_optname_to_int", /\AUDP_/, "UDP_")
def_name_to_int("rsock_shutdown_how_to_int", /\ASHUT_/, "SHUT_")
def_name_to_int("rsock_scm_optname_to_int", /\ASCM_/, "SCM_")

def_intern('rsock_intern_family',  /\AAF_/)
def_intern('rsock_intern_family_noprefix',  /\AAF_/, "AF_")
def_intern('rsock_intern_protocol_family',  /\APF_/)
def_intern('rsock_intern_socktype',  /\ASOCK_/)
def_intern('rsock_intern_ipproto',  /\AIPPROTO_/)
def_intern('rsock_intern_iplevel',  /\A(SOL_SOCKET\z|IPPROTO_)/, /\A(SOL_|IPPROTO_)/)
def_intern('rsock_intern_so_optname',  /\ASO_/, "SO_")
def_intern('rsock_intern_ip_optname',  /\AIP_/, "IP_")
def_intern('rsock_intern_ipv6_optname',  /\AIPV6_/, "IPV6_")
def_intern('rsock_intern_tcp_optname',  /\ATCP_/, "TCP_")
def_intern('rsock_intern_udp_optname',  /\AUDP_/, "UDP_")
def_intern('rsock_intern_scm_optname',  /\ASCM_/, "SCM_")
def_intern('rsock_intern_local_optname',  /\ALOCAL_/, "LOCAL_")

result = ERB.new(<<'EOS', nil, '%').result(binding)
/* autogenerated file */

<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| vardef }.join("\n") %>

/*
 * Document-module: ::Socket::Constants
 *
 * Socket::Constants provides socket related constants.
 * Following lists possible constants.
 * If underlying platform doesn't define a constant,
 * the corresponding Ruby constant is not defined.
 *
 */
static void
init_constants(void)
{
    rb_mSockConst = rb_define_module_under(rb_cSocket, "Constants");

<%= gen_const_defs %>
<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| gen_hash }.join("\n") %>
}

<%= NAME_TO_INT_DEFS.map {|decl, func| func }.join("\n") %>

<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| func }.join("\n") %>

EOS

header_result = ERB.new(<<'EOS', nil, '%').result(binding)
/* autogenerated file */
<%= gen_const_decls %>
<%= NAME_TO_INT_DEFS.map {|decl, func| decl }.join("\n") %>
<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| decl }.join("\n") %>
EOS

if opt_H
  File.open(opt_H, 'w') {|f|
    f << header_result
  }
else
  result = header_result + result
end

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

AF_UNSPEC
PF_UNSPEC
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
AF_PACKET
PF_PACKET

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
MSG_PROXY
MSG_FIN
MSG_SYN
MSG_CONFIRM
MSG_RST
MSG_ERRQUEUE
MSG_NOSIGNAL
MSG_MORE

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
IP_MINTTL
IP_DONTFRAG
IP_SENDSRCADDR
IP_ONESBCAST
IP_RECVTTL
IP_RECVIF
IP_RECVSLLA
IP_PORTRANGE
IP_MULTICAST_IF
IP_MULTICAST_TTL
IP_MULTICAST_LOOP
IP_ADD_MEMBERSHIP
IP_DROP_MEMBERSHIP
IP_DEFAULT_MULTICAST_TTL
IP_DEFAULT_MULTICAST_LOOP
IP_MAX_MEMBERSHIPS
IP_ROUTER_ALERT
IP_PKTINFO
IP_PKTOPTIONS
IP_MTU_DISCOVER
IP_RECVERR
IP_RECVTOS
IP_MTU
IP_FREEBIND
IP_IPSEC_POLICY
IP_XFRM_POLICY
IP_PASSSEC
IP_PMTUDISC_DONT
IP_PMTUDISC_WANT
IP_PMTUDISC_DO
IP_UNBLOCK_SOURCE
IP_BLOCK_SOURCE
IP_ADD_SOURCE_MEMBERSHIP
IP_DROP_SOURCE_MEMBERSHIP
IP_MSFILTER

MCAST_JOIN_GROUP
MCAST_BLOCK_SOURCE
MCAST_UNBLOCK_SOURCE
MCAST_LEAVE_GROUP
MCAST_JOIN_SOURCE_GROUP
MCAST_LEAVE_SOURCE_GROUP
MCAST_MSFILTER
MCAST_EXCLUDE
MCAST_INCLUDE

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
SO_TIMESTAMPNS
SO_BINTIME
SO_RECVUCRED
SO_MAC_EXEMPT
SO_ALLZONES

SOPRI_INTERACTIVE
SOPRI_NORMAL
SOPRI_BACKGROUND

IPX_TYPE

TCP_NODELAY
TCP_MAXSEG
TCP_CORK
TCP_DEFER_ACCEPT
TCP_INFO
TCP_KEEPCNT
TCP_KEEPIDLE
TCP_KEEPINTVL
TCP_LINGER2
TCP_MD5SIG
TCP_NOOPT
TCP_NOPUSH
TCP_QUICKACK
TCP_SYNCNT
TCP_WINDOW_CLAMP

UDP_CORK

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

INET_ADDRSTRLEN 16
INET6_ADDRSTRLEN
IFNAMSIZ

SOMAXCONN

SCM_RIGHTS
SCM_TIMESTAMP
SCM_TIMESTAMPNS
SCM_BINTIME
SCM_CREDENTIALS
SCM_CREDS
SCM_UCRED

LOCAL_PEERCRED
LOCAL_CREDS
LOCAL_CONNWAIT
