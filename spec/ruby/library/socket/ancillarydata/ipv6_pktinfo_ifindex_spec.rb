require_relative '../spec_helper'

with_feature :ancillary_data, :ipv6_pktinfo do
  describe 'Socket::AncillaryData#ipv6_pktinfo_ifindex' do
    it 'returns an Addrinfo' do
      data = Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip('::1'), 4)

      data.ipv6_pktinfo_ifindex.should == 4
    end
  end
end
