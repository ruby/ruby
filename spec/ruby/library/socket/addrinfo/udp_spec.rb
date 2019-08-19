require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo.udp' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    it 'returns an Addrinfo instance' do
      Addrinfo.udp(ip_address, 80).should be_an_instance_of(Addrinfo)
    end

    it 'sets the IP address' do
      Addrinfo.udp(ip_address, 80).ip_address.should == ip_address
    end

    it 'sets the port' do
      Addrinfo.udp(ip_address, 80).ip_port.should == 80
    end

    it 'sets the address family' do
      Addrinfo.udp(ip_address, 80).afamily.should == family
    end

    it 'sets the protocol family' do
      Addrinfo.udp(ip_address, 80).pfamily.should == family
    end

    it 'sets the socket type' do
      Addrinfo.udp(ip_address, 80).socktype.should == Socket::SOCK_DGRAM
    end

    platform_is_not :solaris do
      it 'sets the socket protocol' do
        Addrinfo.udp(ip_address, 80).protocol.should == Socket::IPPROTO_UDP
      end
    end
  end
end
