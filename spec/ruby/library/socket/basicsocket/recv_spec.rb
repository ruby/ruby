# encoding: binary
require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#recv" do

  before :each do
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
    ScratchPad.clear
  end

  it "receives a specified number of bytes of a message from another socket"  do
    t = Thread.new do
      client = @server.accept
      ScratchPad.record client.recv(10)
      client.recv(1) # this recv is important
      client.close
    end
    Thread.pass while t.status and t.status != "sleep"
    t.status.should_not be_nil

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.send('hello', 0)
    socket.close

    t.join
    ScratchPad.recorded.should == 'hello'
  end

  it "accepts flags to specify unusual receiving behaviour" do
    t = Thread.new do
      client = @server.accept

      # in-band data (TCP), doesn't receive the flag.
      ScratchPad.record client.recv(10)

      # this recv is important (TODO: explain)
      client.recv(10)
      client.close
    end
    Thread.pass while t.status and t.status != "sleep"
    t.status.should_not be_nil

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.send('helloU', Socket::MSG_OOB)
    socket.shutdown(1)
    t.join
    socket.close
    ScratchPad.recorded.should == 'hello'
  end

  it "gets lines delimited with a custom separator"  do
    t = Thread.new do
      client = @server.accept
      ScratchPad.record client.gets("\377")

      # this call is important (TODO: explain)
      client.gets(nil)
      client.close
    end
    Thread.pass while t.status and t.status != "sleep"
    t.status.should_not be_nil

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write("firstline\377secondline\377")
    socket.close

    t.join
    ScratchPad.recorded.should == "firstline\377"
  end

  it "allows an output buffer as third argument" do
    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write("data")

    client = @server.accept
    buffer = +"foo"
    begin
      client.recv(4, 0, buffer).should.equal?(buffer)
    ensure
      client.close
    end
    buffer.should == "data"

    socket.close
  end

  it "preserves the encoding of the given buffer" do
    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write("data")

    client = @server.accept
    buffer = ''.encode(Encoding::ISO_8859_1)
    begin
      client.recv(4, 0, buffer)
    ensure
      client.close
    end
    buffer.encoding.should == Encoding::ISO_8859_1

    socket.close
  end
end

describe 'BasicSocket#recv' do
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
        -> { @server.recv(4) }.should block_caller
      end
    end

    describe 'using a bound socket' do
      before do
        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      describe 'without any data available' do
        it 'blocks the caller' do
          -> { @server.recv(4) }.should block_caller
        end
      end

      describe 'with data available' do
        before do
          @client.connect(@server.getsockname)
        end

        it 'reads the given amount of bytes' do
          @client.write('hello')

          @server.recv(2).should == 'he'
        end

        it 'reads the given amount of bytes when it exceeds the data size' do
          @client.write('he')

          @server.recv(6).should == 'he'
        end

        it 'blocks the caller when called twice without new data being available' do
          @client.write('hello')

          @server.recv(2).should == 'he'

          -> { @server.recv(4) }.should block_caller
        end

        it 'takes a peek at the data when using the MSG_PEEK flag' do
          @client.write('hello')

          @server.recv(2, Socket::MSG_PEEK).should == 'he'
          @server.recv(2).should == 'he'
        end
      end
    end
  end
end

describe "BasicSocket#recv" do
  context "when recvfrom(2) returns 0 (if no messages are available to be received and the peer has performed an orderly shutdown)" do
    describe "stream socket" do
      before :each do
        @server = TCPServer.new('127.0.0.1', 0)
        @port = @server.addr[1]
      end

      after :each do
        @server.close unless @server.closed?
      end

      ruby_version_is ""..."3.3" do
        it "returns an empty String on a closed stream socket" do
          t = Thread.new do
            client = @server.accept
            client.recv(10)
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          socket = TCPSocket.new('127.0.0.1', @port)
          socket.close

          t.value.should == ""
        end
      end

      ruby_version_is "3.3" do
        it "returns nil on a closed stream socket" do
          t = Thread.new do
            client = @server.accept
            client.recv(10)
          ensure
            client.close if client
          end

          Thread.pass while t.status and t.status != "sleep"
          t.status.should_not be_nil

          socket = TCPSocket.new('127.0.0.1', @port)
          socket.close

          t.value.should be_nil
        end
      end
    end

    describe "datagram socket" do
      SocketSpecs.each_ip_protocol do |family, ip_address|
        before :each do
          @server = UDPSocket.new(family)
          @client = UDPSocket.new(family)
        end

        after :each do
          @server.close unless @server.closed?
          @client.close unless @client.closed?
        end

        it "returns empty String" do
          @server.bind(ip_address, 0)
          addr = @server.connect_address
          @client.connect(addr.ip_address, addr.ip_port)

          @client.send('', 0)

          @server.recv(1).should == ""
        end
      end
    end
  end
end
