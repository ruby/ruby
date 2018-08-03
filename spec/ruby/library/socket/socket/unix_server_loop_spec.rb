require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'Socket.unix_server_loop' do
    before do
      @path = SocketSpecs.socket_path
    end

    after do
      rm_r(@path) if File.file?(@path)
    end

    describe 'when no connections are available' do
      it 'blocks the caller' do
        lambda { Socket.unix_server_loop(@path) }.should block_caller
      end
    end

    describe 'when a connection is available' do
      before do
        @client = nil
      end

      after do
        @sock.close if @sock
        @client.close if @client
      end

      it 'yields a Socket and an Addrinfo' do
        @sock, addr = nil

        thread = Thread.new do
          Socket.unix_server_loop(@path) do |socket, addrinfo|
            @sock = socket
            addr = addrinfo

            break
          end
        end

        @client = SocketSpecs.wait_until_success { Socket.unix(@path) }

        thread.join(2)

        @sock.should be_an_instance_of(Socket)
        addr.should be_an_instance_of(Addrinfo)
      end
    end
  end
end
