require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket.udp_server_loop' do
  describe 'when no connections are available' do
    it 'blocks the caller' do
      lambda { Socket.udp_server_loop('127.0.0.1', 0) }.should block_caller
    end
  end

  describe 'when a connection is available' do
    before do
      @client = Socket.new(:INET, :DGRAM)
      @port   = 9997
    end

    after do
      @client.close
    end

    it 'yields the message and a Socket::UDPSource' do
      msg, src = nil

      Thread.new do
        Socket.udp_server_loop('127.0.0.1', @port) do |message, source|
          msg = message
          src = source

          break
        end
      end

      # Because this will return even if the server is up and running (it's UDP
      # after all) we'll have to write and wait until "msg" is set.
      @client.connect(Socket.sockaddr_in(@port, '127.0.0.1'))

      SocketSpecs.loop_with_timeout do
        SocketSpecs.wait_until_success { @client.write('hello') }

        break if msg
      end

      msg.should == 'hello'
      src.should be_an_instance_of(Socket::UDPSource)
    end
  end
end
