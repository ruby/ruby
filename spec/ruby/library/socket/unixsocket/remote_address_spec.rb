require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'UNIXSocket#remote_address' do
    before do
      @path   = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
      @client = UNIXSocket.new(@path)
    end

    after do
      @client.close
      @server.close

      rm_r(@path)
    end

    it 'returns an Addrinfo' do
      @client.remote_address.should be_an_instance_of(Addrinfo)
    end

    describe 'the returned Addrinfo' do
      it 'uses AF_UNIX as the address family' do
        @client.remote_address.afamily.should == Socket::AF_UNIX
      end

      it 'uses PF_UNIX as the protocol family' do
        @client.remote_address.pfamily.should == Socket::PF_UNIX
      end

      it 'uses SOCK_STREAM as the socket type' do
        @client.remote_address.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses the correct socket path' do
        @client.remote_address.unix_path.should == @path
      end

      it 'uses 0 as the protocol' do
        @client.remote_address.protocol.should == 0
      end
    end
  end
end
