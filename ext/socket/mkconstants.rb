# frozen_string_literal: false
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
COMMENTS = Hash.new { |h, name| h[name] = name }

DATA.each_line {|s|
  name, default_value, comment = s.chomp.split(/\s+/, 3)
  next unless name && name[0] != ?#

  default_value = nil if default_value == 'nil'

  if h.has_key? name
    warn "#{$.}: warning: duplicate name: #{name}"
    next
  end
  h[name] = default_value
  if comment
    # Stop unintentional references
    COMMENTS[name] = comment.gsub(/\b(Data|Kernel|Process|Set|Socket|Time)\b/, '\\\\\\&')
  end
}
DEFS = h.to_a

def each_const
  DEFS.each {|name, default_value|
    guard = nil
    if /\A(AF_INET6|PF_INET6|IPV6_.*)\z/ =~ name
      # IPv6 is not supported although AF_INET6 is defined on mingw
      guard = "defined(INET6)"
    end
    yield guard, name, default_value
  }
end

def each_name(pat)
  DEFS.each {|name, default_value|
    next if pat !~ name
    yield name
  }
end

erb_new = lambda do |src, safe, trim|
  if ERB.instance_method(:initialize).parameters.assoc(:key) # Ruby 2.6+
    ERB.new(src, trim_mode: trim)
  else
    ERB.new(src, safe, trim)
  end
end

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_const_decls")
% each_const {|guard, name, default_value|
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

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_const_defs_in_guard(name, default_value)")
#if defined(<%=name%>)
    /* <%= COMMENTS[name] %> */
    rb_define_const(rb_cSocket, <%=c_str name%>, INTEGER2NUM(<%=name%>));
    /* <%= COMMENTS[name] %> */
    rb_define_const(rb_mSockConst, <%=c_str name%>, INTEGER2NUM(<%=name%>));
#endif
EOS

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_const_defs")
% each_const {|guard, name, default_value|
%   if guard
#if <%=guard%>
<%= gen_const_defs_in_guard(name, default_value).chomp %>
#endif
%   else
<%= gen_const_defs_in_guard(name, default_value).chomp %>
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

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_decl(funcname, pat, prefix_optional, guard=nil)")
%if guard
#ifdef <%=guard%>
int <%=funcname%>(const char *str, long len, int *valp);
#endif
%else
int <%=funcname%>(const char *str, long len, int *valp);
%end
EOS

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_func_in_guard(funcname, pat, prefix_optional, guard=nil)")
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
        if (!str || !valp) {/* wrong argument */}
        return -1;
    }
}
EOS

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_name_to_int_func(funcname, pat, prefix_optional, guard=nil)")
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

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_hash(hash_var, pat, prefix_pat)")
    <%=hash_var%> = st_init_numtable();
% reverse_each_name_with_prefix_optional(pat, prefix_pat) {|n,s|
#ifdef <%=n%>
    st_insert(<%=hash_var%>, (st_data_t)<%=n%>, (st_data_t)rb_intern2(<%=c_str s%>, <%=s.length%>));
#endif
% }
EOS

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_func(func_name, hash_var)")
ID
<%=func_name%>(int val)
{
    st_data_t name;
    if (st_lookup(<%=hash_var%>, (st_data_t)val, &name))
        return (ID)name;
    return 0;
}
EOS

erb_new.call(<<'EOS', nil, '%').def_method(Object, "gen_int_to_name_decl(func_name, hash_var)")
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

result = erb_new.call(<<'EOS', nil, '%').result(binding)
/* autogenerated file */

<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| vardef }.join("\n") %>

#ifdef HAVE_LONG_LONG
#define INTEGER2NUM(n) \
    (FIXNUM_MAX < (n) ? ULL2NUM(n) : \
     FIXNUM_MIN > (LONG_LONG)(n) ? LL2NUM(n) : \
     LONG2FIX(n))
#else
#define INTEGER2NUM(n) \
    (FIXNUM_MAX < (n) ? ULONG2NUM(n) : \
     FIXNUM_MIN > (long)(n) ? LONG2NUM(n) : \
     LONG2FIX(n))
#endif

static void
init_constants(void)
{
    /*
     * Document-module: Socket::Constants
     *
     * Socket::Constants provides socket-related constants.  All possible
     * socket constants are listed in the documentation but they may not all
     * be present on your platform.
     *
     * If the underlying platform doesn't define a constant the corresponding
     * Ruby constant is not defined.
     *
     */
    rb_mSockConst = rb_define_module_under(rb_cSocket, "Constants");

<%= gen_const_defs %>
<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| gen_hash }.join("\n") %>
}

<%= NAME_TO_INT_DEFS.map {|decl, func| func }.join("\n") %>

<%= INTERN_DEFS.map {|vardef, gen_hash, decl, func| func }.join("\n") %>

EOS

header_result = erb_new.call(<<'EOS', nil, '%').result(binding)
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

SOCK_STREAM	nil	A stream socket provides a sequenced, reliable two-way connection for a byte stream
SOCK_DGRAM	nil	A datagram socket provides connectionless, unreliable messaging
SOCK_RAW	nil	A raw socket provides low-level access for direct access or implementing network protocols
SOCK_RDM	nil	A reliable datagram socket provides reliable delivery of messages
SOCK_SEQPACKET	nil	A sequential packet socket provides sequenced, reliable two-way connection for datagrams
SOCK_PACKET	nil	Device-level packet access
SOCK_NONBLOCK	nil	Set the O_NONBLOCK file status flag on the open file description (see open(2)) referred to by the new file descriptor.
SOCK_CLOEXEC	nil	Set the close-on-exec (FD_CLOEXEC) flag on the new file  descriptor.

AF_UNSPEC	nil	Unspecified protocol, any supported address family
PF_UNSPEC	nil	Unspecified protocol, any supported address family
AF_INET	nil	IPv4 protocol
PF_INET	nil	IPv4 protocol
AF_INET6	nil	IPv6 protocol
PF_INET6	nil	IPv6 protocol
AF_UNIX	nil	UNIX sockets
PF_UNIX	nil	UNIX sockets
AF_AX25	nil	AX.25 protocol
PF_AX25	nil	AX.25 protocol
AF_IPX	nil	IPX protocol
PF_IPX	nil	IPX protocol
AF_APPLETALK	nil	AppleTalk protocol
PF_APPLETALK	nil	AppleTalk protocol
AF_LOCAL	nil	Host-internal protocols
PF_LOCAL	nil	Host-internal protocols
AF_IMPLINK	nil	ARPANET IMP protocol
PF_IMPLINK	nil	ARPANET IMP protocol
AF_PUP	nil	PARC Universal Packet protocol
PF_PUP	nil	PARC Universal Packet protocol
AF_CHAOS	nil	MIT CHAOS protocols
PF_CHAOS	nil	MIT CHAOS protocols
AF_NS	nil	XEROX NS protocols
PF_NS	nil	XEROX NS protocols
AF_ISO	nil	ISO Open Systems Interconnection protocols
PF_ISO	nil	ISO Open Systems Interconnection protocols
AF_OSI	nil	ISO Open Systems Interconnection protocols
PF_OSI	nil	ISO Open Systems Interconnection protocols
AF_ECMA	nil	European Computer Manufacturers protocols
PF_ECMA	nil	European Computer Manufacturers protocols
AF_DATAKIT	nil	Datakit protocol
PF_DATAKIT	nil	Datakit protocol
AF_CCITT	nil	CCITT (now ITU-T) protocols
PF_CCITT	nil	CCITT (now ITU-T) protocols
AF_SNA	nil	IBM SNA protocol
PF_SNA	nil	IBM SNA protocol
AF_DEC	nil	DECnet protocol
PF_DEC	nil	DECnet protocol
AF_DECnet	nil	DECnet protocol
PF_DECnet	nil	DECnet protocol
AF_DLI	nil	DEC Direct Data Link Interface protocol
PF_DLI	nil	DEC Direct Data Link Interface protocol
AF_LAT	nil	Local Area Transport protocol
PF_LAT	nil	Local Area Transport protocol
AF_HYLINK	nil	NSC Hyperchannel protocol
PF_HYLINK	nil	NSC Hyperchannel protocol
AF_ROUTE	nil	Internal routing protocol
PF_ROUTE	nil	Internal routing protocol
AF_LINK	nil	Link layer interface
PF_LINK	nil	Link layer interface
AF_COIP	nil	Connection-oriented IP
PF_COIP	nil	Connection-oriented IP
AF_CNT	nil	Computer Network Technology
PF_CNT	nil	Computer Network Technology
AF_SIP	nil	Simple Internet Protocol
PF_SIP	nil	Simple Internet Protocol
AF_NDRV	nil	Network driver raw access
PF_NDRV	nil	Network driver raw access
AF_ISDN	nil	Integrated Services Digital Network
PF_ISDN	nil	Integrated Services Digital Network
AF_NATM	nil	Native ATM access
PF_NATM	nil	Native ATM access
AF_SYSTEM	nil	Kernel event messages
PF_SYSTEM	nil	Kernel event messages
AF_NETBIOS	nil	NetBIOS
PF_NETBIOS	nil	NetBIOS
AF_PPP	nil	Point-to-Point Protocol
PF_PPP	nil	Point-to-Point Protocol
AF_ATM	nil	Asynchronous Transfer Mode
PF_ATM	nil	Asynchronous Transfer Mode
AF_NETGRAPH	nil	Netgraph sockets
PF_NETGRAPH	nil	Netgraph sockets
AF_MAX	nil	Maximum address family for this platform
PF_MAX	nil	Maximum address family for this platform
AF_PACKET	nil	Direct link-layer access
PF_PACKET	nil	Direct link-layer access

AF_E164	nil	CCITT (ITU-T) E.164 recommendation
PF_XTP	nil	eXpress Transfer Protocol
PF_RTIP	nil	Help Identify RTIP packets
PF_PIP	nil	Help Identify PIP packets
AF_KEY	nil	Key management protocol, originally developed for usage with IPsec
PF_KEY	nil	Key management protocol, originally developed for usage with IPsec
AF_NETLINK	nil	Kernel user interface device
PF_NETLINK	nil	Kernel user interface device
AF_RDS	nil	Reliable Datagram Sockets (RDS) protocol
PF_RDS	nil	Reliable Datagram Sockets (RDS) protocol
AF_PPPOX	nil	Generic PPP transport layer, for setting up L2 tunnels (L2TP and PPPoE)
PF_PPPOX	nil	Generic PPP transport layer, for setting up L2 tunnels (L2TP and PPPoE)
AF_LLC	nil	Logical  link control (IEEE 802.2 LLC) protocol
PF_LLC	nil	Logical  link control (IEEE 802.2 LLC) protocol
AF_IB	nil	InfiniBand native addressing
PF_IB	nil	InfiniBand native addressing
AF_MPLS	nil	Multiprotocol Label Switching
PF_MPLS	nil	Multiprotocol Label Switching
AF_CAN	nil	Controller Area Network automotive bus protocol
PF_CAN	nil	Controller Area Network automotive bus protocol
AF_TIPC	nil	TIPC, "cluster domain sockets" protocol
PF_TIPC	nil	TIPC, "cluster domain sockets" protocol
AF_BLUETOOTH	nil	Bluetooth low-level socket protocol
PF_BLUETOOTH	nil	Bluetooth low-level socket protocol
AF_ALG	nil	Interface to kernel crypto API
PF_ALG	nil	Interface to kernel crypto API
AF_VSOCK	nil	VSOCK (originally "VMWare VSockets") protocol for hypervisor-guest communication
PF_VSOCK	nil	VSOCK (originally "VMWare VSockets") protocol for hypervisor-guest communication
AF_KCM	nil	KCM (kernel connection multiplexor) interface
PF_KCM	nil	KCM (kernel connection multiplexor) interface
AF_XDP	nil	XDP (express data path) interface
PF_XDP	nil	XDP (express data path) interface

MSG_OOB	nil	Process out-of-band data
MSG_PEEK	nil	Peek at incoming message
MSG_DONTROUTE	nil	Send without using the routing tables
MSG_EOR	nil	Data completes record
MSG_TRUNC	nil	Data discarded before delivery
MSG_CTRUNC	nil	Control data lost before delivery
MSG_WAITALL	nil	Wait for full request or error
MSG_DONTWAIT	nil	This message should be non-blocking
MSG_EOF	nil	Data completes connection
MSG_FLUSH	nil	Start of a hold sequence.  Dumps to so_temp
MSG_HOLD	nil	Hold fragment in so_temp
MSG_SEND	nil	Send the packet in so_temp
MSG_HAVEMORE	nil	Data ready to be read
MSG_RCVMORE	nil	Data remains in the current packet
MSG_COMPAT	nil	End of record
MSG_PROXY	nil	Wait for full request
MSG_FIN
MSG_SYN
MSG_CONFIRM	nil	Confirm path validity
MSG_RST
MSG_ERRQUEUE	nil	Fetch message from error queue
MSG_NOSIGNAL	nil	Do not generate SIGPIPE
MSG_MORE	nil	Sender will send more
MSG_FASTOPEN nil Reduce step of the handshake process

SOL_SOCKET	nil	Socket-level options
SOL_IP	nil	IP socket options
SOL_IPX	nil	IPX socket options
SOL_AX25	nil	AX.25 socket options
SOL_ATALK	nil	AppleTalk socket options
SOL_TCP	nil	TCP socket options
SOL_UDP	nil	UDP socket options

IPPROTO_IP	0	Dummy protocol for IP
IPPROTO_ICMP	1	Control message protocol
IPPROTO_IGMP	nil	Group Management Protocol
IPPROTO_GGP	nil	Gateway to Gateway Protocol
IPPROTO_TCP	6	TCP
IPPROTO_EGP	nil	Exterior Gateway Protocol
IPPROTO_PUP	nil	PARC Universal Packet protocol
IPPROTO_UDP	17	UDP
IPPROTO_IDP	nil	XNS IDP
IPPROTO_HELLO	nil	"hello" routing protocol
IPPROTO_ND	nil	Sun net disk protocol
IPPROTO_TP	nil	ISO transport protocol class 4
IPPROTO_XTP	nil	Xpress Transport Protocol
IPPROTO_EON	nil	ISO cnlp
IPPROTO_BIP
IPPROTO_AH	nil	IP6 auth header
IPPROTO_DSTOPTS	nil	IP6 destination option
IPPROTO_ESP	nil	IP6 Encapsulated Security Payload
IPPROTO_FRAGMENT	nil	IP6 fragmentation header
IPPROTO_HOPOPTS	nil	IP6 hop-by-hop options
IPPROTO_ICMPV6	nil	ICMP6
IPPROTO_IPV6	nil	IP6 header
IPPROTO_NONE	nil	IP6 no next header
IPPROTO_ROUTING	nil	IP6 routing header

IPPROTO_RAW	255	Raw IP packet
IPPROTO_MAX	nil	Maximum IPPROTO constant

# Some port configuration
IPPORT_RESERVED		1024	Default minimum address for bind or connect
IPPORT_USERRESERVED	5000	Default maximum address for bind or connect

# Some reserved IP v.4 addresses
INADDR_ANY		0x00000000	A socket bound to INADDR_ANY receives packets from all interfaces and sends from the default IP address
INADDR_BROADCAST	0xffffffff	The network broadcast address
INADDR_LOOPBACK		0x7F000001	The loopback address
INADDR_UNSPEC_GROUP	0xe0000000	The reserved multicast group
INADDR_ALLHOSTS_GROUP	0xe0000001	Multicast group for all systems on this subset
INADDR_MAX_LOCAL_GROUP	0xe00000ff	The last local network multicast group
INADDR_NONE		0xffffffff	A bitmask for matching no valid IP address

# IP [gs]etsockopt options
IP_OPTIONS	nil	IP options to be included in packets
IP_HDRINCL	nil	Header is included with data
IP_TOS	nil	IP type-of-service
IP_TTL	nil	IP time-to-live
IP_RECVOPTS	nil	Receive all IP options with datagram
IP_RECVRETOPTS	nil	Receive all IP options for response
IP_RECVDSTADDR	nil	Receive IP destination address with datagram
IP_RETOPTS	nil	IP options to be included in datagrams
IP_MINTTL	nil	Minimum TTL allowed for received packets
IP_DONTFRAG	nil	Don't fragment packets
IP_SENDSRCADDR	nil	Source address for outgoing UDP datagrams
IP_ONESBCAST	nil	Force outgoing broadcast datagrams to have the undirected broadcast address
IP_RECVTTL	nil	Receive IP TTL with datagrams
IP_RECVIF	nil	Receive interface information with datagrams
IP_RECVSLLA	nil	Receive link-layer address with datagrams
IP_PORTRANGE	nil	Set the port range for sockets with unspecified port numbers
IP_MULTICAST_IF	nil	IP multicast interface
IP_MULTICAST_TTL	nil	IP multicast TTL
IP_MULTICAST_LOOP	nil	IP multicast loopback
IP_ADD_MEMBERSHIP	nil	Add a multicast group membership
IP_DROP_MEMBERSHIP	nil	Drop a multicast group membership
IP_DEFAULT_MULTICAST_TTL	nil	Default multicast TTL
IP_DEFAULT_MULTICAST_LOOP	nil	Default multicast loopback
IP_MAX_MEMBERSHIPS	nil	Maximum number multicast groups a socket can join
IP_ROUTER_ALERT	nil	Notify transit routers to more closely examine the contents of an IP packet
IP_PKTINFO	nil	Receive packet information with datagrams
IP_PKTOPTIONS	nil	Receive packet options with datagrams
IP_MTU_DISCOVER	nil	Path MTU discovery
IP_RECVERR	nil	Enable extended reliable error message passing
IP_RECVTOS	nil	Receive TOS with incoming packets
IP_MTU	nil	The Maximum Transmission Unit of the socket
IP_FREEBIND	nil	Allow binding to nonexistent IP addresses
IP_IPSEC_POLICY	nil	IPsec security policy
IP_XFRM_POLICY
IP_PASSSEC	nil	Retrieve security context with datagram
IP_TRANSPARENT  nil     Transparent proxy
IP_PMTUDISC_DONT	nil	Never send DF frames
IP_PMTUDISC_WANT	nil	Use per-route hints
IP_PMTUDISC_DO	nil	Always send DF frames
IP_UNBLOCK_SOURCE	nil	Unblock IPv4 multicast packets with a give source address
IP_BLOCK_SOURCE	nil	Block IPv4 multicast packets with a give source address
IP_ADD_SOURCE_MEMBERSHIP	nil	Add a multicast group membership
IP_DROP_SOURCE_MEMBERSHIP	nil	Drop a multicast group membership
IP_MSFILTER	nil	Multicast source filtering

MCAST_JOIN_GROUP	nil	Join a multicast group
MCAST_BLOCK_SOURCE	nil	Block multicast packets from this source
MCAST_UNBLOCK_SOURCE	nil	Unblock multicast packets from this source
MCAST_LEAVE_GROUP	nil	Leave a multicast group
MCAST_JOIN_SOURCE_GROUP	nil	Join a multicast source group
MCAST_LEAVE_SOURCE_GROUP	nil	Leave a multicast source group
MCAST_MSFILTER	nil	Multicast source filtering
MCAST_EXCLUDE	nil	Exclusive multicast source filter
MCAST_INCLUDE	nil	Inclusive multicast source filter

SO_DEBUG	nil	Debug info recording
SO_REUSEADDR	nil	Allow local address reuse
SO_REUSEPORT	nil	Allow local address and port reuse
SO_TYPE	nil	Get the socket type
SO_ERROR	nil	Get and clear the error status
SO_DONTROUTE	nil	Use interface addresses
SO_BROADCAST	nil	Permit sending of broadcast messages
SO_SNDBUF	nil	Send buffer size
SO_RCVBUF	nil	Receive buffer size
SO_SNDBUFFORCE  nil     Send buffer size without wmem_max limit (Linux 2.6.14)
SO_RCVBUFFORCE  nil     Receive buffer size without rmem_max limit (Linux 2.6.14)
SO_KEEPALIVE	nil	Keep connections alive
SO_OOBINLINE	nil	Leave received out-of-band data in-line
SO_NO_CHECK	nil	Disable checksums
SO_PRIORITY	nil	The protocol-defined priority for all packets on this socket
SO_LINGER	nil	Linger on close if data is present
SO_PASSCRED	nil	Receive SCM_CREDENTIALS messages
SO_PEERCRED	nil	The credentials of the foreign process connected to this socket
SO_RCVLOWAT	nil	Receive low-water mark
SO_SNDLOWAT	nil	Send low-water mark
SO_RCVTIMEO	nil	Receive timeout
SO_SNDTIMEO	nil	Send timeout
SO_ACCEPTCONN	nil	Socket has had listen() called on it
SO_USELOOPBACK	nil	Bypass hardware when possible
SO_ACCEPTFILTER	nil	There is an accept filter
SO_USER_COOKIE	nil	Setting an identifier for ipfw purpose mainly
SO_DONTTRUNC	nil	Retain unread data
SO_WANTMORE	nil	Give a hint when more data is ready
SO_WANTOOBFLAG	nil	OOB data is wanted in MSG_FLAG on receive
SO_NREAD	nil	Get first packet byte count
SO_NKE	nil	Install socket-level Network Kernel Extension
SO_NOSIGPIPE	nil	Don't SIGPIPE on EPIPE
SO_SECURITY_AUTHENTICATION
SO_SECURITY_ENCRYPTION_TRANSPORT
SO_SECURITY_ENCRYPTION_NETWORK
SO_BINDTODEVICE	nil	Only send packets from the given interface
SO_ATTACH_FILTER	nil	Attach an accept filter
SO_DETACH_FILTER	nil	Detach an accept filter
SO_GET_FILTER   nil     Obtain filter set by SO_ATTACH_FILTER (Linux 3.8)
SO_PEERNAME	nil	Name of the connecting user
SO_TIMESTAMP	nil	Receive timestamp with datagrams (timeval)
SO_TIMESTAMPNS	nil	Receive nanosecond timestamp with datagrams (timespec)
SO_BINTIME	nil	Receive timestamp with datagrams (bintime)
SO_RECVUCRED	nil	Receive user credentials with datagram
SO_MAC_EXEMPT	nil	Mandatory Access Control exemption for unlabeled peers
SO_ALLZONES	nil	Bypass zone boundaries
SO_PEERSEC      nil     Obtain the security credentials (Linux 2.6.2)
SO_PASSSEC      nil     Toggle security context passing (Linux 2.6.18)
SO_MARK         nil     Set the mark for mark-based routing (Linux 2.6.25)
SO_TIMESTAMPING nil     Time stamping of incoming and outgoing packets (Linux 2.6.30)
SO_PROTOCOL     nil     Protocol given for socket() (Linux 2.6.32)
SO_DOMAIN       nil     Domain given for socket() (Linux 2.6.32)
SO_RXQ_OVFL     nil     Toggle cmsg for number of packets dropped (Linux 2.6.33)
SO_WIFI_STATUS  nil     Toggle cmsg for wifi status (Linux 3.3)
SO_PEEK_OFF     nil     Set the peek offset (Linux 3.4)
SO_NOFCS        nil     Set netns of a socket (Linux 3.4)
SO_LOCK_FILTER  nil     Lock the filter attached to a socket (Linux 3.9)
SO_SELECT_ERR_QUEUE     nil     Make select() detect socket error queue with errorfds (Linux 3.10)
SO_BUSY_POLL    nil     Set the threshold in microseconds for low latency polling (Linux 3.11)
SO_MAX_PACING_RATE      nil     Cap the rate computed by transport layer. [bytes per second] (Linux 3.13)
SO_BPF_EXTENSIONS       nil     Query supported BPF extensions (Linux 3.14)
SO_SETFIB       nil     Set the associated routing table for the socket (FreeBSD)
SO_RTABLE               nil     Set the routing table for this socket (OpenBSD)
SO_INCOMING_CPU         nil     Receive the cpu attached to the socket (Linux 3.19)
SO_INCOMING_NAPI_ID     nil     Receive the napi ID attached to a RX queue (Linux 4.12)

SOPRI_INTERACTIVE	nil	Interactive socket priority
SOPRI_NORMAL	nil	Normal socket priority
SOPRI_BACKGROUND	nil	Background socket priority

IPX_TYPE

TCP_NODELAY	nil	Don't delay sending to coalesce packets
TCP_MAXSEG	nil	Set maximum segment size
TCP_CONNECTION_INFO     nil     Retrieve information about this socket (macOS)
TCP_CORK	nil	Don't send partial frames (Linux 2.2, glibc 2.2)
TCP_DEFER_ACCEPT	nil	Don't notify a listening socket until data is ready (Linux 2.4, glibc 2.2)
TCP_INFO	nil	Retrieve information about this socket (Linux 2.4, glibc 2.2)
TCP_KEEPALIVE	nil	Idle time before keepalive probes are sent (macOS)
TCP_KEEPCNT	nil	Maximum number of keepalive probes allowed before dropping a connection (Linux 2.4, glibc 2.2)
TCP_KEEPIDLE	nil	Idle time before keepalive probes are sent (Linux 2.4, glibc 2.2)
TCP_KEEPINTVL	nil	Time between keepalive probes (Linux 2.4, glibc 2.2)
TCP_LINGER2	nil	Lifetime of orphaned FIN_WAIT2 sockets (Linux 2.4, glibc 2.2)
TCP_MD5SIG	nil	Use MD5 digests (RFC2385, Linux 2.6.20, glibc 2.7)
TCP_NOOPT	nil	Don't use TCP options
TCP_NOPUSH	nil	Don't push the last block of write
TCP_QUICKACK	nil	Enable quickack mode (Linux 2.4.4, glibc 2.3)
TCP_SYNCNT	nil	Number of SYN retransmits before a connection is dropped (Linux 2.4, glibc 2.2)
TCP_WINDOW_CLAMP	nil	Clamp the size of the advertised window (Linux 2.4, glibc 2.2)
TCP_FASTOPEN nil Reduce step of the handshake process (Linux 3.7, glibc 2.18)
TCP_CONGESTION  nil     TCP congestion control algorithm (Linux 2.6.13, glibc 2.6)
TCP_COOKIE_TRANSACTIONS nil     TCP Cookie Transactions (Linux 2.6.33, glibc 2.18)
TCP_QUEUE_SEQ   nil     Sequence of a queue for repair mode (Linux 3.5, glibc 2.18)
TCP_REPAIR      nil     Repair mode (Linux 3.5, glibc 2.18)
TCP_REPAIR_OPTIONS      nil     Options for repair mode (Linux 3.5, glibc 2.18)
TCP_REPAIR_QUEUE        nil     Queue for repair mode (Linux 3.5, glibc 2.18)
TCP_THIN_DUPACK nil     Duplicated acknowledgments handling for thin-streams (Linux 2.6.34, glibc 2.18)
TCP_THIN_LINEAR_TIMEOUTS        nil     Linear timeouts for thin-streams (Linux 2.6.34, glibc 2.18)
TCP_TIMESTAMP   nil     TCP timestamp (Linux 3.9, glibc 2.18)
TCP_USER_TIMEOUT        nil     Max timeout before a TCP connection is aborted (Linux 2.6.37, glibc 2.18)

UDP_CORK	nil	Don't send partial frames (Linux 2.5.44, glibc 2.11)

EAI_ADDRFAMILY	nil	Address family for hostname not supported
EAI_AGAIN	nil	Temporary failure in name resolution
EAI_BADFLAGS	nil	Invalid flags
EAI_FAIL	nil	Non-recoverable failure in name resolution
EAI_FAMILY	nil	Address family not supported
EAI_MEMORY	nil	Memory allocation failure
EAI_NODATA	nil	No address associated with hostname
EAI_NONAME	nil	Hostname nor servname, or not known
EAI_OVERFLOW	nil	Argument buffer overflow
EAI_SERVICE	nil	Servname not supported for socket type
EAI_SOCKTYPE	nil	Socket type not supported
EAI_SYSTEM	nil	System error returned in errno
EAI_BADHINTS	nil	Invalid value for hints
EAI_PROTOCOL	nil	Resolved protocol is unknown
EAI_MAX	nil	Maximum error code from getaddrinfo

AI_PASSIVE	nil	Get address to use with bind()
AI_CANONNAME	nil	Fill in the canonical name
AI_NUMERICHOST	nil	Prevent host name resolution
AI_NUMERICSERV	nil	Prevent service name resolution
AI_MASK	nil	Valid flag mask for getaddrinfo (not for application use)
AI_ALL	nil	Allow all addresses
AI_V4MAPPED_CFG	nil	Accept IPv4 mapped addresses if the kernel supports it
AI_ADDRCONFIG	nil	Accept only if any address is assigned
AI_V4MAPPED	nil	Accept IPv4-mapped IPv6 addresses
AI_DEFAULT	nil	Default flags for getaddrinfo

NI_MAXHOST	nil	Maximum length of a hostname
NI_MAXSERV	nil	Maximum length of a service name
NI_NOFQDN	nil	An FQDN is not required for local hosts, return only the local part
NI_NUMERICHOST	nil	Return a numeric address
NI_NAMEREQD	nil	A name is required
NI_NUMERICSERV	nil	Return the service name as a digit string
NI_DGRAM	nil	The service specified is a datagram service (looks up UDP ports)

SHUT_RD		0	Shut down the reading side of the socket
SHUT_WR		1	Shut down the writing side of the socket
SHUT_RDWR	2	Shut down the both sides of the socket

IPV6_JOIN_GROUP	nil	Join a group membership
IPV6_LEAVE_GROUP	nil	Leave a group membership
IPV6_MULTICAST_HOPS	nil	IP6 multicast hops
IPV6_MULTICAST_IF	nil	IP6 multicast interface
IPV6_MULTICAST_LOOP	nil	IP6 multicast loopback
IPV6_UNICAST_HOPS	nil	IP6 unicast hops
IPV6_V6ONLY	nil	Only bind IPv6 with a wildcard bind
IPV6_CHECKSUM	nil	Checksum offset for raw sockets
IPV6_DONTFRAG	nil	Don't fragment packets
IPV6_DSTOPTS	nil	Destination option
IPV6_HOPLIMIT	nil	Hop limit
IPV6_HOPOPTS	nil	Hop-by-hop option
IPV6_NEXTHOP	nil	Next hop address
IPV6_PATHMTU	nil	Retrieve current path MTU
IPV6_PKTINFO	nil	Receive packet information with datagram
IPV6_RECVDSTOPTS	nil	Receive all IP6 options for response
IPV6_RECVHOPLIMIT	nil	Receive hop limit with datagram
IPV6_RECVHOPOPTS	nil	Receive hop-by-hop options
IPV6_RECVPKTINFO	nil	Receive destination IP address and incoming interface
IPV6_RECVRTHDR	nil	Receive routing header
IPV6_RECVTCLASS	nil	Receive traffic class
IPV6_RTHDR	nil	Allows removal of sticky routing headers
IPV6_RTHDRDSTOPTS	nil	Allows removal of sticky destination options header
IPV6_RTHDR_TYPE_0	nil	Routing header type 0
IPV6_RECVPATHMTU	nil	Receive current path MTU with datagram
IPV6_TCLASS	nil	Specify the traffic class
IPV6_USE_MIN_MTU	nil	Use the minimum MTU size

INET_ADDRSTRLEN	16	Maximum length of an IPv4 address string
INET6_ADDRSTRLEN	46	Maximum length of an IPv6 address string
IFNAMSIZ	nil	Maximum interface name size
IF_NAMESIZE	nil	Maximum interface name size

SOMAXCONN	5	Maximum connection requests that may be queued for a socket

SCM_RIGHTS	nil	Access rights
SCM_TIMESTAMP	nil	Timestamp (timeval)
SCM_TIMESTAMPNS	nil	Timespec (timespec)
SCM_TIMESTAMPING        nil     Timestamp (timespec list) (Linux 2.6.30)
SCM_BINTIME	nil	Timestamp (bintime)
SCM_CREDENTIALS	nil	The sender's credentials
SCM_CREDS	nil	Process credentials
SCM_UCRED	nil	User credentials
SCM_WIFI_STATUS nil     Wifi status (Linux 3.3)

LOCAL_PEERCRED	nil	Retrieve peer credentials
LOCAL_CREDS	nil	Pass credentials to receiver
LOCAL_CONNWAIT	nil	Connect blocks until accepted

IFF_802_1Q_VLAN      nil 802.1Q VLAN device
IFF_ALLMULTI         nil receive all multicast packets
IFF_ALTPHYS          nil use alternate physical connection
IFF_AUTOMEDIA        nil auto media select active
IFF_BONDING          nil bonding master or slave
IFF_BRIDGE_PORT      nil device used as bridge port
IFF_BROADCAST        nil broadcast address valid
IFF_CANTCONFIG       nil unconfigurable using ioctl(2)
IFF_DEBUG            nil turn on debugging
IFF_DISABLE_NETPOLL  nil disable netpoll at run-time
IFF_DONT_BRIDGE      nil disallow bridging this ether dev
IFF_DORMANT          nil driver signals dormant
IFF_DRV_OACTIVE      nil tx hardware queue is full
IFF_DRV_RUNNING      nil resources allocated
IFF_DYING            nil interface is winding down
IFF_DYNAMIC          nil dialup device with changing addresses
IFF_EBRIDGE          nil ethernet bridging device
IFF_ECHO             nil echo sent packets
IFF_ISATAP           nil ISATAP interface (RFC4214)
IFF_LINK0            nil per link layer defined bit 0
IFF_LINK1            nil per link layer defined bit 1
IFF_LINK2            nil per link layer defined bit 2
IFF_LIVE_ADDR_CHANGE nil hardware address change when it's running
IFF_LOOPBACK         nil loopback net
IFF_LOWER_UP         nil driver signals L1 up
IFF_MACVLAN_PORT     nil device used as macvlan port
IFF_MASTER           nil master of a load balancer
IFF_MASTER_8023AD    nil bonding master, 802.3ad.
IFF_MASTER_ALB       nil bonding master, balance-alb.
IFF_MASTER_ARPMON    nil bonding master, ARP mon in use
IFF_MONITOR          nil user-requested monitor mode
IFF_MULTICAST        nil supports multicast
IFF_NOARP            nil no address resolution protocol
IFF_NOTRAILERS       nil avoid use of trailers
IFF_OACTIVE          nil transmission in progress
IFF_OVS_DATAPATH     nil device used as Open vSwitch datapath port
IFF_POINTOPOINT      nil point-to-point link
IFF_PORTSEL          nil can set media type
IFF_PPROMISC         nil user-requested promisc mode
IFF_PROMISC          nil receive all packets
IFF_RENAMING         nil interface is being renamed
IFF_ROUTE            nil routing entry installed
IFF_RUNNING          nil resources allocated
IFF_SIMPLEX          nil can't hear own transmissions
IFF_SLAVE            nil slave of a load balancer
IFF_SLAVE_INACTIVE   nil bonding slave not the curr. active
IFF_SLAVE_NEEDARP    nil need ARPs for validation
IFF_SMART            nil interface manages own routes
IFF_STATICARP        nil static ARP
IFF_SUPP_NOFCS       nil sending custom FCS
IFF_TEAM_PORT        nil used as team port
IFF_TX_SKB_SHARING   nil sharing skbs on transmit
IFF_UNICAST_FLT      nil unicast filtering
IFF_UP               nil interface is up
IFF_WAN_HDLC         nil WAN HDLC device
IFF_XMIT_DST_RELEASE nil dev_hard_start_xmit() is allowed to release skb->dst
IFF_VOLATILE         nil volatile flags
IFF_CANTCHANGE       nil flags not changeable
