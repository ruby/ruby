require_relative '../spec_helper'

describe 'Addrinfo#ipv6_mc_orglocal?' do
  it 'returns true for a multi-cast org-local address' do
    Addrinfo.ip('ff18::').ipv6_mc_orglocal?.should == true
    Addrinfo.ip('ff08::').ipv6_mc_orglocal?.should == true
    Addrinfo.ip('fff8::').ipv6_mc_orglocal?.should == true
    Addrinfo.ip('ff18::1').ipv6_mc_orglocal?.should == true
  end

  it 'returns false for a regular IPv6 address' do
    Addrinfo.ip('::1').ipv6_mc_orglocal?.should == false
  end

  it 'returns false for an IPv4 address' do
    Addrinfo.ip('127.0.0.1').ipv6_mc_orglocal?.should == false
  end
end
