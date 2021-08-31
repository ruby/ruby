require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'Socket.unix' do
    before do
      @path   = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
      @socket = nil
    end

    after do
      @server.close
      @socket.close if @socket

      rm_r(@path)
    end

    describe 'when no block is given' do
      it 'returns a Socket' do
        @socket = Socket.unix(@path)

        @socket.should be_an_instance_of(Socket)
      end
    end

    describe 'when a block is given' do
      it 'yields a Socket' do
        Socket.unix(@path) do |sock|
          sock.should be_an_instance_of(Socket)
        end
      end

      it 'closes the Socket when the block returns' do
        socket = nil

        Socket.unix(@path) do |sock|
          socket = sock
        end

        socket.should.closed?
      end
    end
  end
end
