require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_global?' do
  it 'returns true for a multi-cast address in the global scope' do
    Addrinfo.ip('ff1e::').ipv6_mc_global?.should == true
    Addrinfo.ip('fffe::').ipv6_mc_global?.should == true
    Addrinfo.ip('ff0e::').ipv6_mc_global?.should == true
    Addrinfo.ip('ff1e::1').ipv6_mc_global?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_mc_global?.should == false
    Addrinfo.ip('ff1a::').ipv6_mc_global?.should == false
    Addrinfo.ip('ff1f::1').ipv6_mc_global?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_mc_global?.should == false
  end
end
