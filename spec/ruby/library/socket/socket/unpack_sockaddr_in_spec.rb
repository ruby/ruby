require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.unpack_sockaddr_in" do
  it "decodes the host name and port number of a packed sockaddr_in" do
    sockaddr = Socket.sockaddr_in 3333, '127.0.0.1'
    Socket.unpack_sockaddr_in(sockaddr).should == [3333, '127.0.0.1']
  end

  it "gets the hostname and port number from a passed Addrinfo" do
    addrinfo = Addrinfo.tcp('127.0.0.1', 3333)
    Socket.unpack_sockaddr_in(addrinfo).should == [3333, '127.0.0.1']
  end

  describe 'using an IPv4 address' do
    it 'returns an Array containing the port and IP address' do
      port = 80
      ip   = '127.0.0.1'
      addr = Socket.pack_sockaddr_in(port, ip)

      Socket.unpack_sockaddr_in(addr).should == [port, ip]
    end
  end

  describe 'using an IPv6 address' do
    it 'returns an Array containing the port and IP address' do
      port = 80
      ip   = '::1'
      addr = Socket.pack_sockaddr_in(port, ip)

      Socket.unpack_sockaddr_in(addr).should == [port, ip]
    end
  end

  with_feature :unix_socket do
    it "raises an ArgumentError when the sin_family is not AF_INET" do
      sockaddr = Socket.sockaddr_un '/tmp/x'
      lambda { Socket.unpack_sockaddr_in sockaddr }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError when passed addrinfo is not AF_INET/AF_INET6" do
      addrinfo = Addrinfo.unix('/tmp/sock')
      lambda { Socket.unpack_sockaddr_in(addrinfo) }.should raise_error(ArgumentError)
    end
  end
end
