require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Addrinfo#ipv6_linklocal?' do
    platform_is_not :aix do
      it 'returns true for a link-local address' do
        Addrinfo.ip('fe80::').ipv6_linklocal?.should == true
        Addrinfo.ip('fe81::').ipv6_linklocal?.should == true
        Addrinfo.ip('fe8f::').ipv6_linklocal?.should == true
        Addrinfo.ip('fe80::1').ipv6_linklocal?.should == true
      end
    end

    it 'returns false for a regular address' do
      Addrinfo.ip('::1').ipv6_linklocal?.should == false
    end

    it 'returns false for an IPv4 address' do
      Addrinfo.ip('127.0.0.1').ipv6_linklocal?.should == false
    end
  end
end
