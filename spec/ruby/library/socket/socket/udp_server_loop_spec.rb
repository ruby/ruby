require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket.udp_server_loop' do
  describe 'when no connections are available' do
    it 'blocks the caller' do
      -> { Socket.udp_server_loop('127.0.0.1', 0) }.should block_caller
    end
  end

  describe 'when a connection is available' do
    before do
      @client = Socket.new(:INET, :DGRAM)
      SocketSpecs::ServerLoopPortFinder.cleanup
    end

    after do
      @client.close
    end

    it 'yields the message and a Socket::UDPSource' do
      msg, src = nil

      thread = Thread.new do
        SocketSpecs::ServerLoopPortFinder.udp_server_loop('127.0.0.1', 0) do |message, source|
          msg = message
          src = source

          break
        end
      end

      port = SocketSpecs::ServerLoopPortFinder.port

      # Because this will return even if the server is up and running (it's UDP
      # after all) we'll have to write and wait until "msg" is set.
      @client.connect(Socket.sockaddr_in(port, '127.0.0.1'))

      SocketSpecs.loop_with_timeout do
        begin
          @client.write('hello')
        rescue SystemCallError
          sleep 0.01
          :retry
        else
          unless msg
            sleep 0.001
            :retry
          end
        end
      end

      thread.join

      msg.should == 'hello'
      src.should be_an_instance_of(Socket::UDPSource)
    end
  end
end
