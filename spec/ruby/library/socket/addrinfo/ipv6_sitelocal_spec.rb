require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Addrinfo#ipv6_sitelocal?' do
    platform_is_not :aix do
      it 'returns true for a site-local address' do
        Addrinfo.ip('feef::').ipv6_sitelocal?.should == true
        Addrinfo.ip('fee0::').ipv6_sitelocal?.should == true
        Addrinfo.ip('fee2::').ipv6_sitelocal?.should == true
        Addrinfo.ip('feef::1').ipv6_sitelocal?.should == true
      end
    end

    it 'returns false for a regular IPv6 address' do
      Addrinfo.ip('::1').ipv6_sitelocal?.should == false
    end

    it 'returns false for an IPv4 address' do
      Addrinfo.ip('127.0.0.1').ipv6_sitelocal?.should == false
    end
  end
end
