require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket.for_fd" do
  before :each do
    @server = TCPServer.new(0)
    @s2 = nil
  end

  after :each do
    @socket1.close if @socket1
    @server.close if @server
  end

  it "return a Socket instance wrapped around the descriptor" do
    @s2 = TCPServer.for_fd(@server.fileno)
    @s2.autoclose = false
    @s2.should be_kind_of(TCPServer)
    @s2.fileno.should == @server.fileno
  end

  it 'returns a new socket for a file descriptor' do
    @socket1 = Socket.new(:INET, :DGRAM)
    socket2 = Socket.for_fd(@socket1.fileno)
    socket2.autoclose = false

    socket2.should be_an_instance_of(Socket)
    socket2.fileno.should == @socket1.fileno
  end

  it 'sets the socket into binary mode' do
    @socket1 = Socket.new(:INET, :DGRAM)
    socket2 = Socket.for_fd(@socket1.fileno)
    socket2.autoclose = false

    socket2.binmode?.should be_true
  end
end
