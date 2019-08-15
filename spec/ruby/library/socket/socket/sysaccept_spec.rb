require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#sysaccept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server   = Socket.new(family, :STREAM)
      @sockaddr = Socket.sockaddr_in(0, ip_address)
    end

    after do
      @server.close
    end

    platform_is :linux do # hangs on other platforms
      describe 'using an unbound socket'  do
        it 'raises Errno::EINVAL' do
          -> { @server.sysaccept }.should raise_error(Errno::EINVAL)
        end
      end

      describe "using a bound socket that's not listening" do
        before do
          @server.bind(@sockaddr)
        end

        it 'raises Errno::EINVAL' do
          -> { @server.sysaccept }.should raise_error(Errno::EINVAL)
        end
      end
    end

    describe "using a bound socket that's listening" do
      before do
        @server.bind(@sockaddr)
        @server.listen(1)

        server_ip    = @server.local_address.ip_port
        @server_addr = Socket.sockaddr_in(server_ip, ip_address)
      end

      after do
        Socket.for_fd(@fd).close if @fd
      end

      describe 'without a connected client' do
        before do
          @client = Socket.new(family, :STREAM)
        end

        after do
          @client.close
        end

        it 'blocks the caller until a connection is available' do
          thread = Thread.new do
            @fd, _ = @server.sysaccept
          end

          @client.connect(@server_addr)

          thread.value.should be_an_instance_of(Array)
        end
      end

      describe 'with a connected client' do
        before do
          @client = Socket.new(family, :STREAM)
          @client.connect(@server.getsockname)
        end

        after do
          @client.close
        end

        it 'returns an Array containing an Integer and an Addrinfo' do
          @fd, addrinfo = @server.sysaccept

          @fd.should be_kind_of(Integer)
          addrinfo.should be_an_instance_of(Addrinfo)
        end

        it 'returns a new file descriptor' do
          @fd, _ = @server.sysaccept

          @fd.should_not == @client.fileno
        end
      end
    end
  end
end
