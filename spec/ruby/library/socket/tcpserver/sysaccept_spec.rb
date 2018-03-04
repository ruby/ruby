require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

require 'socket'

describe "TCPServer#sysaccept" do
  before :each do
    @server = TCPServer.new(SocketSpecs.hostname, 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it 'blocks if no connections' do
    lambda { @server.sysaccept }.should block_caller
  end

  it 'returns file descriptor of an accepted connection' do
    begin
      sock = TCPSocket.new(SocketSpecs.hostname, @port)

      fd = @server.sysaccept

      fd.should be_an_instance_of(Fixnum)
    ensure
      sock.close if sock && !sock.closed?
      IO.for_fd(fd).close if fd
    end
  end
end
