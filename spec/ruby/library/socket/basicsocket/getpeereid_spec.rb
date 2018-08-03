require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'BasicSocket#getpeereid' do
  with_feature :unix_socket do
    describe 'using a UNIXSocket' do
      before do
        @path = SocketSpecs.socket_path
        @server = UNIXServer.new(@path)
        @client = UNIXSocket.new(@path)
      end

      after do
        @client.close
        @server.close

        rm_r(@path)
      end

      it 'returns an Array with the user and group ID' do
        @client.getpeereid.should == [Process.euid, Process.egid]
      end
    end
  end

  describe 'using an IPSocket' do
    after do
      @sock.close
    end

    it 'raises NoMethodError' do
      @sock = TCPServer.new('127.0.0.1', 0)
      lambda { @sock.getpeereid }.should raise_error(NoMethodError)
    end
  end
end
