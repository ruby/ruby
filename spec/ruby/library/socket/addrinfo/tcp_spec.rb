require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo.tcp' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    it 'returns an Addrinfo instance' do
      Addrinfo.tcp(ip_address, 80).should be_an_instance_of(Addrinfo)
    end

    it 'sets the IP address' do
      Addrinfo.tcp(ip_address, 80).ip_address.should == ip_address
    end

    it 'sets the port' do
      Addrinfo.tcp(ip_address, 80).ip_port.should == 80
    end

    it 'sets the address family' do
      Addrinfo.tcp(ip_address, 80).afamily.should == family
    end

    it 'sets the protocol family' do
      Addrinfo.tcp(ip_address, 80).pfamily.should == family
    end

    it 'sets the socket type' do
      Addrinfo.tcp(ip_address, 80).socktype.should == Socket::SOCK_STREAM
    end

    it 'sets the socket protocol' do
      Addrinfo.tcp(ip_address, 80).protocol.should == Socket::IPPROTO_TCP
    end
  end
end
