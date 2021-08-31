require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Addrinfo#ipv6_linklocal?' do
    platform_is_not :aix do
      it 'returns true for a link-local address' do
        Addrinfo.ip('fe80::').should.ipv6_linklocal?
        Addrinfo.ip('fe81::').should.ipv6_linklocal?
        Addrinfo.ip('fe8f::').should.ipv6_linklocal?
        Addrinfo.ip('fe80::1').should.ipv6_linklocal?
      end
    end

    it 'returns false for a regular address' do
      Addrinfo.ip('::1').should_not.ipv6_linklocal?
    end

    it 'returns false for an IPv4 address' do
      Addrinfo.ip('127.0.0.1').should_not.ipv6_linklocal?
    end
  end
end
