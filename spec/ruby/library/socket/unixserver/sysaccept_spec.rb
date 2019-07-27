require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'UNIXServer#sysaccept' do
    before do
      @path   = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
    end

    after do
      @server.close

      rm_r(@path)
    end

    describe 'without a client' do
      it 'blocks the calling thread' do
        -> { @server.sysaccept }.should block_caller
      end
    end

    describe 'with a client' do
      before do
        @client = UNIXSocket.new(@path)
      end

      after do
        Socket.for_fd(@fd).close if @fd
        @client.close
      end

      describe 'without any data' do
        it 'returns an Integer' do
          @fd = @server.sysaccept
          @fd.should be_kind_of(Integer)
        end
      end

      describe 'with data available' do
        before do
          @client.write('hello')
        end

        it 'returns an Integer' do
          @fd = @server.sysaccept
          @fd.should be_kind_of(Integer)
        end
      end
    end
  end
end
