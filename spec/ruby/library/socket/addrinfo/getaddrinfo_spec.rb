require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo.getaddrinfo' do
  it 'returns an Array of Addrinfo instances' do
    array = Addrinfo.getaddrinfo('127.0.0.1', 80)

    array.should be_an_instance_of(Array)
    array[0].should be_an_instance_of(Addrinfo)
  end

  SocketSpecs.each_ip_protocol do |family, ip_address|
    it 'sets the IP address of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].ip_address.should == ip_address
    end

    it 'sets the port of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].ip_port.should == 80
    end

    it 'sets the address family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].afamily.should == family
    end

    it 'sets the protocol family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo(ip_address, 80)

      array[0].pfamily.should == family
    end
  end

  guard -> { SocketSpecs.ipv6_available? } do
    it 'sets a custom protocol family of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo('::1', 80, Socket::PF_INET6)

      array[0].pfamily.should == Socket::PF_INET6
    end

    it 'sets a corresponding address family based on a custom protocol family' do
      array = Addrinfo.getaddrinfo('::1', 80, Socket::PF_INET6)

      array[0].afamily.should == Socket::AF_INET6
    end
  end

  platform_is_not :windows do
    it 'sets the default socket type of the Addrinfo instances' do
      array    = Addrinfo.getaddrinfo('127.0.0.1', 80)
      possible = [Socket::SOCK_STREAM, Socket::SOCK_DGRAM]

      possible.should include(array[0].socktype)
    end
  end

  it 'sets a custom socket type of the Addrinfo instances' do
    array = Addrinfo.getaddrinfo('127.0.0.1', 80, nil, Socket::SOCK_DGRAM)

    array[0].socktype.should == Socket::SOCK_DGRAM
  end

  platform_is_not :windows do
    it 'sets the default socket protocol of the Addrinfo instances' do
      array    = Addrinfo.getaddrinfo('127.0.0.1', 80)
      possible = [Socket::IPPROTO_TCP, Socket::IPPROTO_UDP]

      possible.should include(array[0].protocol)
    end
  end

  platform_is_not :'solaris2.10' do # i386-solaris
    it 'sets a custom socket protocol of the Addrinfo instances' do
      array = Addrinfo.getaddrinfo('127.0.0.1', 80, nil, nil, Socket::IPPROTO_UDP)

      array[0].protocol.should == Socket::IPPROTO_UDP
    end
  end

  platform_is_not :solaris do
    it 'sets the canonical name when AI_CANONNAME is given as a flag' do
      array = Addrinfo.getaddrinfo('localhost', 80, nil, nil, nil, Socket::AI_CANONNAME)

      array[0].canonname.should be_an_instance_of(String)
    end
  end
end
