require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/new'

describe 'TCPSocket#initialize' do
  it_behaves_like :tcpsocket_new, :new

  describe "with a running server" do
    before :each do
      @server = SocketSpecs::SpecTCPServer.new
      @hostname = @server.hostname
    end

    after :each do
      if @socket
        @socket.write "QUIT"
        @socket.close
      end
      @server.shutdown
    end

    it "does not use the given block and warns to use TCPSocket::open" do
      -> {
        @socket = TCPSocket.new(@hostname, @server.port, nil) { raise }
      }.should complain(/warning: TCPSocket::new\(\) does not take block; use TCPSocket::open\(\) instead/)
    end
  end
end

describe 'TCPSocket#initialize' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'when no server is listening on the given address' do
      it 'raises Errno::ECONNREFUSED' do
        -> { TCPSocket.new(ip_address, 666) }.should raise_error(Errno::ECONNREFUSED)
      end
    end

    describe 'when a server is listening on the given address' do
      before do
        @server = TCPServer.new(ip_address, 0)
        @port   = @server.connect_address.ip_port
      end

      after do
        @client.close if @client
        @server.close
      end

      it 'returns a TCPSocket when using an Integer as the port' do
        @client = TCPSocket.new(ip_address, @port)
        @client.should be_an_instance_of(TCPSocket)
      end

      it 'returns a TCPSocket when using a String as the port' do
        @client = TCPSocket.new(ip_address, @port.to_s)
        @client.should be_an_instance_of(TCPSocket)
      end

      it 'raises SocketError when the port number is a non numeric String' do
        -> { TCPSocket.new(ip_address, 'cats') }.should raise_error(SocketError)
      end

      it 'set the socket to binmode' do
        @client = TCPSocket.new(ip_address, @port)
        @client.binmode?.should be_true
      end

      it 'connects to the right address' do
        @client = TCPSocket.new(ip_address, @port)

        @client.remote_address.ip_address.should == @server.local_address.ip_address
        @client.remote_address.ip_port.should    == @server.local_address.ip_port
      end

      platform_is_not :windows do
        it "creates a socket which is set to nonblocking" do
          require 'io/nonblock'
          @client = TCPSocket.new(ip_address, @port)
          @client.should.nonblock?
        end
      end

      it "creates a socket which is set to close on exec" do
        @client = TCPSocket.new(ip_address, @port)
        @client.should.close_on_exec?
      end

      describe 'using a local address and service' do
        it 'binds the client socket to the local address and service' do
          @client = TCPSocket.new(ip_address, @port, ip_address, 0)

          @client.local_address.ip_address.should == ip_address

          @client.local_address.ip_port.should > 0
          @client.local_address.ip_port.should_not == @port
        end
      end
    end
  end
end
