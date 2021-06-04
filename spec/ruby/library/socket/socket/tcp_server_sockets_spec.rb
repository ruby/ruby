require_relative '../spec_helper'

describe 'Socket.tcp_server_sockets' do
  describe 'without a block' do
    before do
      @sockets = nil
    end

    after do
      @sockets.each(&:close)
    end

    it 'returns an Array of Socket objects' do
      @sockets = Socket.tcp_server_sockets(0)

      @sockets.should be_an_instance_of(Array)
      @sockets[0].should be_an_instance_of(Socket)
    end
  end

  describe 'with a block' do
    it 'yields the sockets to the supplied block' do
      Socket.tcp_server_sockets(0) do |sockets|
        sockets.should be_an_instance_of(Array)
        sockets[0].should be_an_instance_of(Socket)
      end
    end

    it 'closes all sockets after the block returns' do
      sockets = nil

      Socket.tcp_server_sockets(0) { |socks| sockets = socks }

      sockets.each do |socket|
        socket.should.closed?
      end
    end
  end
end
