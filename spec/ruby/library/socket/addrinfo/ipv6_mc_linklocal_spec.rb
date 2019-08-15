require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_linklocal?' do
  it 'returns true for a multi-cast link-local address' do
    Addrinfo.ip('ff12::').ipv6_mc_linklocal?.should == true
    Addrinfo.ip('ff02::').ipv6_mc_linklocal?.should == true
    Addrinfo.ip('fff2::').ipv6_mc_linklocal?.should == true
    Addrinfo.ip('ff12::1').ipv6_mc_linklocal?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_mc_linklocal?.should == false
    Addrinfo.ip('fff1::').ipv6_mc_linklocal?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_mc_linklocal?.should == false
  end
end
