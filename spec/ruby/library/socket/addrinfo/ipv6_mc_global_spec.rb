require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_global?' do
  it 'returns true for a multi-cast address in the global scope' do
    Addrinfo.ip('ff1e::').should.ipv6_mc_global?
    Addrinfo.ip('fffe::').should.ipv6_mc_global?
    Addrinfo.ip('ff0e::').should.ipv6_mc_global?
    Addrinfo.ip('ff1e::1').should.ipv6_mc_global?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_mc_global?
    Addrinfo.ip('ff1a::').should_not.ipv6_mc_global?
    Addrinfo.ip('ff1f::1').should_not.ipv6_mc_global?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_mc_global?
  end
end
