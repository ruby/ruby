require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_nodelocal?' do
  it 'returns true for a multi-cast node-local address' do
    Addrinfo.ip('ff11::').ipv6_mc_nodelocal?.should == true
    Addrinfo.ip('ff01::').ipv6_mc_nodelocal?.should == true
    Addrinfo.ip('fff1::').ipv6_mc_nodelocal?.should == true
    Addrinfo.ip('ff11::1').ipv6_mc_nodelocal?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_mc_nodelocal?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_mc_nodelocal?.should == false
  end
end
