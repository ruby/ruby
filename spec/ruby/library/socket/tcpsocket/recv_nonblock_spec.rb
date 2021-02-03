require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPSocket#recv_nonblock" do
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

  it "returns a String read from the socket" do
    @socket = TCPSocket.new @hostname, @server.port
    @socket.write "TCPSocket#recv_nonblock"

    # Wait for the server to echo. This spec is testing the return
    # value, not the non-blocking behavior.
    #
    # TODO: Figure out a good way to test non-blocking.
    IO.select([@socket])
    @socket.recv_nonblock(50).should == "TCPSocket#recv_nonblock"
  end

  it 'writes the read to a buffer from the socket' do
    @socket = TCPSocket.new @hostname, @server.port
    @socket.write "TCPSocket#recv_nonblock"

    # Wait for the server to echo. This spec is testing the return
    # value, not the non-blocking behavior.
    #
    # TODO: Figure out a good way to test non-blocking.
    IO.select([@socket])
    buffer = "".b
    @socket.recv_nonblock(50, 0, buffer)
    buffer.should == 'TCPSocket#recv_nonblock'
  end

  it 'returns :wait_readable in exceptionless mode' do
    @socket = TCPSocket.new @hostname, @server.port
    @socket.recv_nonblock(50, exception: false).should == :wait_readable
  end
end
