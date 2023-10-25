require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_sitelocal?' do
  it 'returns true for a multi-cast site-local address' do
    Addrinfo.ip('ff15::').should.ipv6_mc_sitelocal?
    Addrinfo.ip('ff05::').should.ipv6_mc_sitelocal?
    Addrinfo.ip('fff5::').should.ipv6_mc_sitelocal?
    Addrinfo.ip('ff15::1').should.ipv6_mc_sitelocal?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_mc_sitelocal?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_mc_sitelocal?
  end
end
