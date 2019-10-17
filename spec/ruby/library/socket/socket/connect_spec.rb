require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#connect' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :STREAM)
      @client = Socket.new(family, :STREAM)

      @server.bind(Socket.sockaddr_in(0, ip_address))
    end

    after do
      @client.close
      @server.close
    end

    it 'returns 0 when connected successfully using a String' do
      @server.listen(1)

      @client.connect(@server.getsockname).should == 0
    end

    it 'returns 0 when connected successfully using an Addrinfo' do
      @server.listen(1)

      @client.connect(@server.connect_address).should == 0
    end

    it 'raises Errno::EISCONN when already connected' do
      @server.listen(1)

      @client.connect(@server.getsockname).should == 0

      -> {
        @client.connect(@server.getsockname)

        # A second call needed if non-blocking sockets become default
        # XXX honestly I don't expect any real code to care about this spec
        # as it's too implementation-dependent and checking for connect()
        # errors is futile anyways because of TOCTOU
        @client.connect(@server.getsockname)
      }.should raise_error(Errno::EISCONN)
    end

    platform_is_not :darwin do
      it 'raises Errno::ECONNREFUSED or Errno::ETIMEDOUT when the connection failed' do
        begin
          @client.connect(@server.getsockname)
        rescue => e
          [Errno::ECONNREFUSED, Errno::ETIMEDOUT].include?(e.class).should == true
        end
      end
    end
  end
end
