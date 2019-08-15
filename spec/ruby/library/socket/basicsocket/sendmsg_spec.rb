require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'BasicSocket#sendmsg' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'using a disconnected socket' do
      before do
        @client = Socket.new(family, :DGRAM)
        @server = Socket.new(family, :DGRAM)

        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      after do
        @client.close
        @server.close
      end

      platform_is_not :windows do
        describe 'without a destination address' do
          it "raises #{SocketSpecs.dest_addr_req_error}" do
            -> { @client.sendmsg('hello') }.should raise_error(SocketSpecs.dest_addr_req_error)
          end
        end
      end

      describe 'with a destination address as a String' do
        it 'returns the amount of sent bytes' do
          @client.sendmsg('hello', 0, @server.getsockname).should == 5
        end
      end

      describe 'with a destination address as an Addrinfo' do
        it 'returns the amount of sent bytes' do
          @client.sendmsg('hello', 0, @server.connect_address).should == 5
        end
      end
    end

    describe 'using a connected UDP socket' do
      before do
        @client = Socket.new(family, :DGRAM)
        @server = Socket.new(family, :DGRAM)

        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      after do
        @client.close
        @server.close
      end

      describe 'without a destination address argument' do
        before do
          @client.connect(@server.getsockname)
        end

        it 'returns the amount of bytes written' do
          @client.sendmsg('hello').should == 5
        end
      end

      describe 'with a destination address argument' do
        before do
          @alt_server = Socket.new(family, :DGRAM)

          @alt_server.bind(Socket.sockaddr_in(0, ip_address))
        end

        after do
          @alt_server.close
        end

        it 'sends the message to the given address instead' do
          @client.sendmsg('hello', 0, @alt_server.getsockname).should == 5

          -> { @server.recv(5) }.should block_caller

          @alt_server.recv(5).should == 'hello'
        end
      end
    end

    platform_is_not :windows do # spurious
      describe 'using a connected TCP socket' do
        before do
          @client = Socket.new(family, :STREAM)
          @server = Socket.new(family, :STREAM)

          @server.bind(Socket.sockaddr_in(0, ip_address))
          @server.listen(1)

          @client.connect(@server.getsockname)
        end

        after do
          @client.close
          @server.close
        end

        it 'blocks when the underlying buffer is full' do
          # Buffer sizes may differ per platform, so sadly this is the only
          # reliable way of testing blocking behaviour.
          -> do
            10.times { @client.sendmsg('hello' * 1_000_000) }
          end.should block_caller
        end
      end
    end
  end
end
