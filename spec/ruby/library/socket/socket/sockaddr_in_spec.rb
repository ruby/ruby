require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.sockaddr_in" do
  it "packs and unpacks" do
    sockaddr_in = Socket.sockaddr_in(0, nil)
    port, addr = Socket.unpack_sockaddr_in(sockaddr_in)
    ["127.0.0.1", "::1"].include?(addr).should == true
    port.should == 0

    sockaddr_in = Socket.sockaddr_in(0, '')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [0, '0.0.0.0']

    sockaddr_in = Socket.sockaddr_in(80, '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']

    sockaddr_in = Socket.sockaddr_in('80', '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']

    sockaddr_in = Socket.sockaddr_in(nil, '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [0, '127.0.0.1']

    sockaddr_in = Socket.sockaddr_in(80, Socket::INADDR_ANY)
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '0.0.0.0']
  end

  it 'resolves the service name to a port' do
    sockaddr_in = Socket.sockaddr_in('http', '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']
  end

  describe 'using an IPv4 address' do
    it 'returns a String of 16 bytes' do
      str = Socket.sockaddr_in(80, '127.0.0.1')

      str.should.instance_of?(String)
      str.bytesize.should == 16
    end
  end

  describe 'using an IPv6 address' do
    it 'returns a String of 28 bytes' do
      str = Socket.sockaddr_in(80, '::1')

      str.should.instance_of?(String)
      str.bytesize.should == 28
    end
  end
end
