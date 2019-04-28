require_relative '../../spec_helper'
require 'socket'

MSpec.enable_feature :sock_packet if Socket.const_defined?(:SOCK_PACKET)
MSpec.enable_feature :unix_socket unless PlatformGuard.windows?
MSpec.enable_feature :udp_cork if Socket.const_defined?(:UDP_CORK)
MSpec.enable_feature :tcp_cork if Socket.const_defined?(:TCP_CORK)
MSpec.enable_feature :pktinfo if Socket.const_defined?(:IP_PKTINFO)
MSpec.enable_feature :ipv6_pktinfo if Socket.const_defined?(:IPV6_PKTINFO)
MSpec.enable_feature :ip_mtu if Socket.const_defined?(:IP_MTU)
MSpec.enable_feature :ipv6_nexthop if Socket.const_defined?(:IPV6_NEXTHOP)
MSpec.enable_feature :tcp_info if Socket.const_defined?(:TCP_INFO)
MSpec.enable_feature :ancillary_data if Socket.const_defined?(:AncillaryData)
