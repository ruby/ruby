require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#recvfrom_nonblock' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :DGRAM)
      @client = Socket.new(family, :DGRAM)
    end

    after do
      @client.close
      @server.close
    end

    platform_is_not :windows do
      describe 'using an unbound socket' do
        it 'raises IO::WaitReadable' do
          -> { @server.recvfrom_nonblock(1) }.should raise_error(IO::WaitReadable)
        end
      end
    end

    describe 'using a bound socket' do
      before do
        @server.bind(Socket.sockaddr_in(0, ip_address))
        @client.connect(@server.getsockname)
      end

      describe 'without any data available' do
        it 'raises IO::WaitReadable' do
          -> { @server.recvfrom_nonblock(1) }.should raise_error(IO::WaitReadable)
        end

        it 'returns :wait_readable with exception: false' do
          @server.recvfrom_nonblock(1, exception: false).should == :wait_readable
        end
      end

      describe 'with data available' do
        before do
          @client.write('hello')
        end

        platform_is_not :windows do
          it 'returns an Array containing the data and an Addrinfo' do
            IO.select([@server])
            ret = @server.recvfrom_nonblock(1)

            ret.should be_an_instance_of(Array)
            ret.length.should == 2
          end
        end

        it "allows an output buffer as third argument" do
          @client.write('hello')

          IO.select([@server])
          buffer = +''
          message, = @server.recvfrom_nonblock(5, 0, buffer)

          message.should.equal?(buffer)
          buffer.should == 'hello'
        end

        it "preserves the encoding of the given buffer" do
          @client.write('hello')

          IO.select([@server])
          buffer = ''.encode(Encoding::ISO_8859_1)
          @server.recvfrom_nonblock(5, 0, buffer)

          buffer.encoding.should == Encoding::ISO_8859_1
        end

        describe 'the returned data' do
          it 'is the same as the sent data' do
            5.times do
              @client.write('hello')

              IO.select([@server])
              msg, _ = @server.recvfrom_nonblock(5)

              msg.should == 'hello'
            end
          end
        end

        platform_is_not :windows do
          describe 'the returned Array' do
            before do
              IO.select([@server])
              @array = @server.recvfrom_nonblock(1)
            end

            it 'contains the data at index 0' do
              @array[0].should == 'h'
            end

            it 'contains an Addrinfo at index 1' do
              @array[1].should be_an_instance_of(Addrinfo)
            end
          end

          describe 'the returned Addrinfo' do
            before do
              IO.select([@server])
              @addr = @server.recvfrom_nonblock(1)[1]
            end

            it 'uses AF_INET as the address family' do
              @addr.afamily.should == family
            end

            it 'uses SOCK_DGRAM as the socket type' do
              @addr.socktype.should == Socket::SOCK_DGRAM
            end

            it 'uses PF_INET as the protocol family' do
              @addr.pfamily.should == family
            end

            it 'uses 0 as the protocol' do
              @addr.protocol.should == 0
            end

            it 'uses the IP address of the client' do
              @addr.ip_address.should == ip_address
            end

            it 'uses the port of the client' do
              @addr.ip_port.should == @client.local_address.ip_port
            end
          end
        end
      end
    end
  end
end

describe 'Socket#recvfrom_nonblock' do
  context "when recvfrom(2) returns 0 (if no messages are available to be received and the peer has performed an orderly shutdown)" do
    describe "stream socket" do
      before :each do
        @server = Socket.new Socket::AF_INET, :STREAM, 0
        @sockaddr = Socket.sockaddr_in(0, "127.0.0.1")
        @server.bind(@sockaddr)
        @server.listen(1)

        server_ip    = @server.local_address.ip_port
        @server_addr = Socket.sockaddr_in(server_ip, "127.0.0.1")

        @client = Socket.new(Socket::AF_INET, :STREAM, 0)
      end

      after :each do
        @server.close unless @server.closed?
        @client.close unless @client.closed?
      end

      ruby_version_is ""..."3.3" do
        it "returns an empty String as received data on a closed stream socket" do
          ready = false

          t = Thread.new do
            client, _ = @server.accept

            Thread.pass while !ready
            begin
              client.recvfrom_nonblock(10)
            rescue IO::EAGAINWaitReadable
              retry
            end
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          @client.connect(@server_addr)
          @client.close
          ready = true

          t.value.should.is_a? Array
          t.value[0].should == ""
        end
      end

      ruby_version_is "3.3" do
        it "returns nil on a closed stream socket" do
          ready = false

          t = Thread.new do
            client, _ = @server.accept

            Thread.pass while !ready
            begin
              client.recvfrom_nonblock(10)
            rescue IO::EAGAINWaitReadable
              retry
            end
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          @client.connect(@server_addr)
          @client.close
          ready = true

          t.value.should be_nil
        end
      end
    end
  end
end
