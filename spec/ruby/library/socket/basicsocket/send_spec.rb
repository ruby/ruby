require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#send" do
  before :each do
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @socket = TCPSocket.new('127.0.0.1', @port)
  end

  after :each do
    @server.closed?.should be_false
    @socket.closed?.should be_false

    @server.close
    @socket.close
  end

   it "sends a message to another socket and returns the number of bytes sent" do
     data = ""
     t = Thread.new do
       client = @server.accept
       loop do
         got = client.recv(5)
         break if got.empty?
         data << got
       end
       client.close
     end
     Thread.pass while t.status and t.status != "sleep"
     t.status.should_not be_nil

     @socket.send('hello', 0).should == 5
     @socket.shutdown(1) # indicate, that we are done sending
     @socket.recv(10)

     t.join
     data.should == 'hello'
   end

  platform_is_not :solaris, :windows do
    it "accepts flags to specify unusual sending behaviour" do
      data = nil
      peek_data = nil
      t = Thread.new do
        client = @server.accept
        peek_data = client.recv(6, Socket::MSG_PEEK)
        data = client.recv(6)
        client.recv(10) # this recv is important
        client.close
      end
      Thread.pass while t.status and t.status != "sleep"
      t.status.should_not be_nil

      @socket.send('helloU', Socket::MSG_PEEK | Socket::MSG_OOB).should == 6
      @socket.shutdown # indicate, that we are done sending

      t.join
      peek_data.should == "hello"
      data.should == 'hello'
    end
  end

  it "accepts a sockaddr as recipient address" do
     data = ""
     t = Thread.new do
       client = @server.accept
       loop do
         got = client.recv(5)
         break if got.empty?
         data << got
       end
       client.close
     end
     Thread.pass while t.status and t.status != "sleep"
     t.status.should_not be_nil

     sockaddr = Socket.pack_sockaddr_in(@port, "127.0.0.1")
     @socket.send('hello', 0, sockaddr).should == 5
     @socket.shutdown # indicate, that we are done sending

     t.join
     data.should == 'hello'
  end
end

describe 'BasicSocket#send' do
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

      describe 'with an object implementing #to_str' do
        it 'returns the amount of sent bytes' do
          data = mock('message')
          data.should_receive(:to_str).and_return('hello')
          @client.send(data, 0, @server.getsockname).should == 5
        end
      end

      describe 'without a destination address' do
        it "raises #{SocketSpecs.dest_addr_req_error}" do
          -> { @client.send('hello', 0) }.should raise_error(SocketSpecs.dest_addr_req_error)
        end
      end

      describe 'with a destination address as a String' do
        it 'returns the amount of sent bytes' do
          @client.send('hello', 0, @server.getsockname).should == 5
        end

        it 'does not persist the connection after writing to the socket' do
          @client.send('hello', 0, @server.getsockname)

          -> { @client.send('hello', 0) }.should raise_error(SocketSpecs.dest_addr_req_error)
        end
      end

      describe 'with a destination address as an Addrinfo' do
        it 'returns the amount of sent bytes' do
          @client.send('hello', 0, @server.connect_address).should == 5
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
          @client.send('hello', 0).should == 5
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
          @client.send('hello', 0, @alt_server.getsockname).should == 5

          -> { @server.recv(5) }.should block_caller

          @alt_server.recv(5).should == 'hello'
        end

        it 'does not persist the alternative connection after writing to the socket' do
          @client.send('hello', 0, @alt_server.getsockname)

          @client.connect(@server.getsockname)
          @client.send('world', 0)

          @server.recv(5).should == 'world'
        end
      end
    end

    platform_is_not :darwin, :windows do
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

        describe 'using the MSG_OOB flag' do
          it 'sends an out-of-band message' do
            socket, _ = @server.accept
            socket.setsockopt(:SOCKET, :OOBINLINE, true)
            @client.send('a', Socket::MSG_OOB).should == 1
            begin
              socket.recv(10).should == 'a'
            ensure
              socket.close
            end
          end
        end
      end
    end
  end
end
