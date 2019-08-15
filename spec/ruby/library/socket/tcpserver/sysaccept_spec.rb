require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer#sysaccept" do
  before :each do
    @server = TCPServer.new(SocketSpecs.hostname, 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it 'blocks if no connections' do
    -> { @server.sysaccept }.should block_caller
  end

  it 'returns file descriptor of an accepted connection' do
    begin
      sock = TCPSocket.new(SocketSpecs.hostname, @port)

      fd = @server.sysaccept

      fd.should be_kind_of(Integer)
    ensure
      sock.close if sock && !sock.closed?
      IO.for_fd(fd).close if fd
    end
  end
end

describe 'TCPServer#sysaccept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
    end

    after do
      @server.close
    end

    describe 'without a connected client' do
      it 'blocks the caller' do
        -> { @server.sysaccept }.should block_caller
      end
    end

    describe 'with a connected client' do
      before do
        @client = TCPSocket.new(ip_address, @server.connect_address.ip_port)
      end

      after do
        Socket.for_fd(@fd).close if @fd
        @client.close
      end

      it 'returns a new file descriptor as an Integer' do
        @fd = @server.sysaccept

        @fd.should be_kind_of(Integer)
        @fd.should_not == @client.fileno
      end
    end
  end
end
