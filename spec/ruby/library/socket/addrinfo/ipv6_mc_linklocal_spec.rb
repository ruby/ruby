require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_linklocal?' do
  it 'returns true for a multi-cast link-local address' do
    Addrinfo.ip('ff12::').should.ipv6_mc_linklocal?
    Addrinfo.ip('ff02::').should.ipv6_mc_linklocal?
    Addrinfo.ip('fff2::').should.ipv6_mc_linklocal?
    Addrinfo.ip('ff12::1').should.ipv6_mc_linklocal?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_mc_linklocal?
    Addrinfo.ip('fff1::').should_not.ipv6_mc_linklocal?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_mc_linklocal?
  end
end
