require_relative '../../spec_helper'
require 'socket'

# We force enable all features on Linux because anyway Linux implements all these features,
# and we want a constant number of spec examples across Ruby implementations, even if they don't define these constants.
MSpec.enable_feature :sock_packet    if platform_is(:linux) || Socket.const_defined?(:SOCK_PACKET)
MSpec.enable_feature :udp_cork       if platform_is(:linux) || Socket.const_defined?(:UDP_CORK)
MSpec.enable_feature :tcp_cork       if platform_is(:linux) || Socket.const_defined?(:TCP_CORK)
MSpec.enable_feature :pktinfo        if platform_is(:linux) || Socket.const_defined?(:IP_PKTINFO)
MSpec.enable_feature :ipv6_pktinfo   if platform_is(:linux) || Socket.const_defined?(:IPV6_PKTINFO)
MSpec.enable_feature :ip_mtu         if platform_is(:linux) || Socket.const_defined?(:IP_MTU)
MSpec.enable_feature :ipv6_nexthop   if platform_is(:linux) || Socket.const_defined?(:IPV6_NEXTHOP)
MSpec.enable_feature :tcp_info       if platform_is(:linux) || Socket.const_defined?(:TCP_INFO)
MSpec.enable_feature :ancillary_data if platform_is(:linux) || Socket.const_defined?(:AncillaryData)
