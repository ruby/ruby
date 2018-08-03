require_relative '../spec_helper'

describe 'Socket.udp_server_loop_on' do
  before do
    @server = Socket.new(:INET, :DGRAM)

    @server.bind(Socket.sockaddr_in(0, '127.0.0.1'))
  end

  after do
    @server.close
  end

  describe 'when no connections are available' do
    it 'blocks the caller' do
      lambda { Socket.udp_server_loop_on([@server]) }.should block_caller
    end
  end

  describe 'when a connection is available' do
    before do
      @client = Socket.new(:INET, :DGRAM)
    end

    after do
      @client.close
    end

    it 'yields the message and a Socket::UDPSource' do
      msg  = nil
      src  = nil

      @client.connect(@server.getsockname)
      @client.write('hello')

      Socket.udp_server_loop_on([@server]) do |message, source|
        msg = message
        src = source

        break
      end

      msg.should == 'hello'
      src.should be_an_instance_of(Socket::UDPSource)
    end
  end
end
