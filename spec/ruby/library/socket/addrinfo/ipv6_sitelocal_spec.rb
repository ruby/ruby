require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Addrinfo#ipv6_sitelocal?' do
    platform_is_not :aix do
      it 'returns true for a site-local address' do
        Addrinfo.ip('feef::').should.ipv6_sitelocal?
        Addrinfo.ip('fee0::').should.ipv6_sitelocal?
        Addrinfo.ip('fee2::').should.ipv6_sitelocal?
        Addrinfo.ip('feef::1').should.ipv6_sitelocal?
      end
    end

    it 'returns false for a regular IPv6 address' do
      Addrinfo.ip('::1').should_not.ipv6_sitelocal?
    end

    it 'returns false for an IPv4 address' do
      Addrinfo.ip('127.0.0.1').should_not.ipv6_sitelocal?
    end
  end
end
