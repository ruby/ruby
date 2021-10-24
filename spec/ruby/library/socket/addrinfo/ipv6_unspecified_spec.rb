require_relative '../spec_helper'

describe 'Addrinfo#ipv6_unspecified?' do
  it 'returns true for an unspecified IPv6 address' do
    Addrinfo.ip('::').should.ipv6_unspecified?
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').should_not.ipv6_unspecified?
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').should_not.ipv6_unspecified?
  end
end
