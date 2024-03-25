require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "UDPSocket#send" do
  before :each do
    @port = nil
    @server_thread = Thread.new do
      @server = UDPSocket.open
      begin
        @server.bind(nil, 0)
        @port = @server.addr[1]
        begin
          @msg = @server.recvfrom_nonblock(64)
        rescue IO::WaitReadable
          IO.select([@server])
          retry
        end
      ensure
        @server.close if !@server.closed?
      end
    end
    Thread.pass while @server_thread.status and !@port
  end

  after :each do
    @server_thread.join
  end

  it "sends data in ad hoc mode" do
    @socket = UDPSocket.open
    @socket.send("ad hoc", 0, SocketSpecs.hostname, @port)
    @socket.close
    @server_thread.join

    @msg[0].should == "ad hoc"
    @msg[1][0].should == "AF_INET"
    @msg[1][1].should be_kind_of(Integer)
    @msg[1][3].should == "127.0.0.1"
  end

  it "sends data in ad hoc mode (with port given as a String)" do
    @socket = UDPSocket.open
    @socket.send("ad hoc", 0, SocketSpecs.hostname, @port.to_s)
    @socket.close
    @server_thread.join

    @msg[0].should == "ad hoc"
    @msg[1][0].should == "AF_INET"
    @msg[1][1].should be_kind_of(Integer)
    @msg[1][3].should == "127.0.0.1"
  end

  it "sends data in connection mode" do
    @socket = UDPSocket.open
    @socket.connect(SocketSpecs.hostname, @port)
    @socket.send("connection-based", 0)
    @socket.close
    @server_thread.join

    @msg[0].should == "connection-based"
    @msg[1][0].should == "AF_INET"
    @msg[1][1].should be_kind_of(Integer)
    @msg[1][3].should == "127.0.0.1"
  end

  it "raises EMSGSIZE if data is too big" do
    @socket = UDPSocket.open
    begin
      -> do
        @socket.send('1' * 100_000, 0, SocketSpecs.hostname, @port.to_s)
      end.should raise_error(Errno::EMSGSIZE)
    ensure
      @socket.send("ad hoc", 0, SocketSpecs.hostname, @port)
      @socket.close
      @server_thread.join
    end
  end
end

describe 'UDPSocket#send' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = UDPSocket.new(family)
      @client = UDPSocket.new(family)

      @server.bind(ip_address, 0)

      @addr = @server.connect_address
    end

    after do
      @server.close
      @client.close
    end

    describe 'using a disconnected socket' do
      describe 'without a destination address' do
        it "raises #{SocketSpecs.dest_addr_req_error}" do
          -> { @client.send('hello', 0) }.should raise_error(SocketSpecs.dest_addr_req_error)
        end
      end

      describe 'with a destination address as separate arguments' do
        it 'returns the amount of sent bytes' do
          @client.send('hello', 0, @addr.ip_address, @addr.ip_port).should == 5
        end

        it 'does not persist the connection after sending data' do
          @client.send('hello', 0, @addr.ip_address, @addr.ip_port)

          -> { @client.send('hello', 0) }.should raise_error(SocketSpecs.dest_addr_req_error)
        end
      end

      describe 'with a destination address as a single String argument' do
        it 'returns the amount of sent bytes' do
          @client.send('hello', 0, @server.getsockname).should == 5
        end
      end
    end

    describe 'using a connected socket' do
      describe 'without an explicit destination address' do
        before do
          @client.connect(@addr.ip_address, @addr.ip_port)
        end

        it 'returns the amount of bytes written' do
          @client.send('hello', 0).should == 5
        end
      end

      describe 'with an explicit destination address' do
        before do
          @alt_server = UDPSocket.new(family)

          @alt_server.bind(ip_address, 0)
        end

        after do
          @alt_server.close
        end

        it 'sends the data to the given address instead' do
          @client.send('hello', 0, @alt_server.getsockname).should == 5

          -> { @server.recv(5) }.should block_caller

          @alt_server.recv(5).should == 'hello'
        end
      end
    end
  end
end
