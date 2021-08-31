require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_orglocal?' do
  it 'returns true for a multi-cast org-local address' do
    Addrinfo.ip('ff18::').should.ipv6_mc_orglocal?
    Addrinfo.ip('ff08::').should.ipv6_mc_orglocal?
    Addrinfo.ip('fff8::').should.ipv6_mc_orglocal?
    Addrinfo.ip('ff18::1').should.ipv6_mc_orglocal?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_mc_orglocal?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_mc_orglocal?
  end
end
