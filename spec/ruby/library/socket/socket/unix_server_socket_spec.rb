require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'Socket.unix_server_socket' do
    before do
      @path = SocketSpecs.socket_path
    end

    after do
      rm_r(@path)
    end

    describe 'when no block is given' do
      before do
        @socket = nil
      end

      after do
        @socket.close
      end

      it 'returns a Socket' do
        @socket = Socket.unix_server_socket(@path)

        @socket.should be_an_instance_of(Socket)
      end
    end

    describe 'when a block is given' do
      it 'yields a Socket' do
        Socket.unix_server_socket(@path) do |sock|
          sock.should be_an_instance_of(Socket)
        end
      end

      it 'closes the Socket when the block returns' do
        socket = nil

        Socket.unix_server_socket(@path) do |sock|
          socket = sock
        end

        socket.should be_an_instance_of(Socket)
      end
    end
  end
end
