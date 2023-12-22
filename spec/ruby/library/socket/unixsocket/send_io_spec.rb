require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe "UNIXSocket#send_io" do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
      @client = UNIXSocket.open(@path)

      @send_io_path = File.expand_path('../../fixtures/send_io.txt', __FILE__)
      @file = File.open(@send_io_path)
    end

    after :each do
      @io.close if @io
      @socket.close if @socket

      @file.close
      @client.close
      @server.close
      SocketSpecs.rm_socket @path
    end

    it "sends the fd for an IO object across the socket" do
      @client.send_io(@file)

      @socket = @server.accept
      @io = @socket.recv_io

      @io.read.should == File.read(@send_io_path)
    end
  end

  describe 'UNIXSocket#send_io' do
    before do
      @file = File.open('/dev/null', 'w')
      @client, @server = UNIXSocket.socketpair
    end

    after do
      @client.close
      @server.close
      @io.close if @io
      @file.close
    end

    it 'sends an IO object' do
      @client.send_io(@file)

      @io = @server.recv_io
      @io.should be_an_instance_of(IO)
    end
  end
end
