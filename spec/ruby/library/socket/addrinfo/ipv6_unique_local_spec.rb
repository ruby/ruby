require_relative '../spec_helper'

describe 'Addrinfo#ipv6_unique_local?' do
  it 'returns true for an unique local IPv6 address' do
    Addrinfo.ip('fc00::').should.ipv6_unique_local?
    Addrinfo.ip('fd00::').should.ipv6_unique_local?
    Addrinfo.ip('fcff::').should.ipv6_unique_local?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_unique_local?
    Addrinfo.ip('fe00::').should_not.ipv6_unique_local?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_unique_local?
  end
end
