require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Socket#recvfrom' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = Socket.new(family, :DGRAM)
      @client = Socket.new(family, :DGRAM)
    end

    after do
      @client.close
      @server.close
    end

    describe 'using an unbound socket' do
      it 'blocks the caller' do
        -> { @server.recvfrom(1) }.should block_caller
      end
    end

    describe 'using a bound socket' do
      before do
        @server.bind(Socket.sockaddr_in(0, ip_address))
        @client.connect(@server.getsockname)
      end

      describe 'without any data available' do
        it 'blocks the caller' do
          -> { @server.recvfrom(1) }.should block_caller
        end
      end

      describe 'with data available' do
        before do
          @client.write('hello')
        end

        it 'returns an Array containing the data and an Addrinfo' do
          ret = @server.recvfrom(1)

          ret.should be_an_instance_of(Array)
          ret.length.should == 2
        end

        describe 'the returned Array' do
          before do
            @array = @server.recvfrom(1)
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
            @addr = @server.recvfrom(1)[1]
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

describe 'Socket#recvfrom' do
  context "when recvfrom(2) returns 0 (if no messages are available to be received and the peer has performed an orderly shutdown)" do
    describe "stream socket" do
      before :each do
        @server = Socket.new Socket::AF_INET, :STREAM, 0
        sockaddr = Socket.sockaddr_in(0, "127.0.0.1")
        @server.bind(sockaddr)
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
          t = Thread.new do
            client, _ = @server.accept
            client.recvfrom(10)
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          @client.connect(@server_addr)
          @client.close

          t.value.should.is_a? Array
          t.value[0].should == ""
        end
      end

      ruby_version_is "3.3" do
        it "returns nil on a closed stream socket" do
          t = Thread.new do
            client, _ = @server.accept
            client.recvfrom(10)
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          @client.connect(@server_addr)
          @client.close

          t.value.should be_nil
        end
      end
    end

    describe "datagram socket" do
      SocketSpecs.each_ip_protocol do |family, ip_address|
        before :each do
          @server = Socket.new(family, :DGRAM)
          @client = Socket.new(family, :DGRAM)
        end

        after :each do
          @server.close unless @server.closed?
          @client.close unless @client.closed?
        end

        it "returns an empty String as received data" do
          @server.bind(Socket.sockaddr_in(0, ip_address))
          @client.connect(@server.getsockname)

          @client.send('', 0)
          message = @server.recvfrom(1)

          message.should.is_a? Array
          message[0].should == ""
        end
      end
    end
  end
end
