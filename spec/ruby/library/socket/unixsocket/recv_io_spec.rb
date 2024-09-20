require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe "UNIXSocket#recv_io" do
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

    it "reads an IO object across the socket" do
      @client.send_io(@file)

      @socket = @server.accept
      @io = @socket.recv_io

      @io.read.should == File.read(@send_io_path)
    end

    it "takes an optional class to use" do
      @client.send_io(@file)

      @socket = @server.accept
      @io = @socket.recv_io(File)

      @io.should be_an_instance_of(File)
    end
  end

  describe 'UNIXSocket#recv_io' do
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

    describe 'without a custom class' do
      it 'returns an IO' do
        @client.send_io(@file)

        @io = @server.recv_io
        @io.should be_an_instance_of(IO)
      end
    end

    describe 'with a custom class' do
      it 'returns an instance of the custom class' do
        @client.send_io(@file)

        @io = @server.recv_io(File)
        @io.should be_an_instance_of(File)
      end
    end

    describe 'with a custom mode' do
      it 'opens the IO using the given mode' do
        @client.send_io(@file)

        @io = @server.recv_io(File, File::WRONLY)
        @io.should be_an_instance_of(File)
      end
    end
  end
end
