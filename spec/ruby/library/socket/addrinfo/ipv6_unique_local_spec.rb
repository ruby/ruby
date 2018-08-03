require_relative '../spec_helper'

describe 'Addrinfo#ipv6_unique_local?' do
  it 'returns true for an unique local IPv6 address' do
    Addrinfo.ip('fc00::').ipv6_unique_local?.should == true
    Addrinfo.ip('fd00::').ipv6_unique_local?.should == true
    Addrinfo.ip('fcff::').ipv6_unique_local?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_unique_local?.should == false
    Addrinfo.ip('fe00::').ipv6_unique_local?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_unique_local?.should == false
  end
end
