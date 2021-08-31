require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'Socket.unpack_sockaddr_un' do
    it 'decodes sockaddr to unix path' do
      sockaddr = Socket.sockaddr_un('/tmp/sock')
      Socket.unpack_sockaddr_un(sockaddr).should == '/tmp/sock'
    end

    it 'returns unix path from a passed Addrinfo' do
      addrinfo = Addrinfo.unix('/tmp/sock')
      Socket.unpack_sockaddr_un(addrinfo).should == '/tmp/sock'
    end

    it 'raises an ArgumentError when the sa_family is not AF_UNIX' do
      sockaddr = Socket.sockaddr_in(0, '127.0.0.1')
      -> { Socket.unpack_sockaddr_un(sockaddr) }.should raise_error(ArgumentError)
    end

    it 'raises an ArgumentError when passed addrinfo is not AF_UNIX' do
      addrinfo = Addrinfo.tcp('127.0.0.1', 0)
      -> { Socket.unpack_sockaddr_un(addrinfo) }.should raise_error(ArgumentError)
    end
  end
end
