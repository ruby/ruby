require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_nodelocal?' do
  it 'returns true for a multi-cast node-local address' do
    Addrinfo.ip('ff11::').should.ipv6_mc_nodelocal?
    Addrinfo.ip('ff01::').should.ipv6_mc_nodelocal?
    Addrinfo.ip('fff1::').should.ipv6_mc_nodelocal?
    Addrinfo.ip('ff11::1').should.ipv6_mc_nodelocal?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_mc_nodelocal?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_mc_nodelocal?
  end
end
