require_relative '../spec_helper'

describe 'Addrinfo#ipv6_v4mapped?' do
  it 'returns true for an IPv4 compatible address' do
    Addrinfo.ip('::ffff:192.168.1.1').ipv6_v4mapped?.should == true
  end

  it 'returns false for an IPv4 compatible address' do
    Addrinfo.ip('::192.168.1.1').ipv6_v4mapped?.should == false
    Addrinfo.ip('::127.0.0.1').ipv6_v4mapped?.should == false
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_v4mapped?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_v4mapped?.should == false
  end
end
