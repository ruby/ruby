require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_sitelocal?' do
  it 'returns true for a multi-cast site-local address' do
    Addrinfo.ip('ff15::').ipv6_mc_sitelocal?.should == true
    Addrinfo.ip('ff05::').ipv6_mc_sitelocal?.should == true
    Addrinfo.ip('fff5::').ipv6_mc_sitelocal?.should == true
    Addrinfo.ip('ff15::1').ipv6_mc_sitelocal?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_mc_sitelocal?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_mc_sitelocal?.should == false
  end
end
