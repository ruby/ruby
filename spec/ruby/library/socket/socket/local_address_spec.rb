require_relative '../spec_helper'

describe 'Socket#local_address' do
  before do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
  end

  after do
    @sock.close
  end

  it 'returns an Addrinfo' do
    @sock.local_address.should be_an_instance_of(Addrinfo)
  end

  describe 'the returned Addrinfo' do
    it 'uses AF_INET as the address family' do
      @sock.local_address.afamily.should == Socket::AF_INET
    end

    it 'uses PF_INET as the protocol family' do
      @sock.local_address.pfamily.should == Socket::PF_INET
    end

    it 'uses SOCK_STREAM as the socket type' do
      @sock.local_address.socktype.should == Socket::SOCK_STREAM
    end

    it 'uses 0.0.0.0 as the IP address' do
      @sock.local_address.ip_address.should == '0.0.0.0'
    end

    platform_is_not :windows do
      it 'uses 0 as the port' do
        @sock.local_address.ip_port.should == 0
      end
    end

    it 'uses 0 as the protocol' do
      @sock.local_address.protocol.should == 0
    end
  end
end
