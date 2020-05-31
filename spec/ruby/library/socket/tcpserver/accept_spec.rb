require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer#accept" do
  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
  end

  it "accepts a connection and returns a TCPSocket" do
    data = nil
    t = Thread.new do
      client = @server.accept
      client.should be_kind_of(TCPSocket)
      data = client.read(5)
      client << "goodbye"
      client.close
    end
    Thread.pass while t.status and t.status != "sleep"

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write('hello')
    socket.shutdown(1) # we are done with sending
    socket.read.should == 'goodbye'
    t.join
    data.should == 'hello'
    socket.close
  end

  it "can be interrupted by Thread#kill" do
    t = Thread.new { @server.accept }

    Thread.pass while t.status and t.status != "sleep"

    # kill thread, ensure it dies in a reasonable amount of time
    t.kill
    a = 0
    while t.alive? and a < 5000
      sleep 0.001
      a += 1
    end
    a.should < 5000
  end

  it "can be interrupted by Thread#raise" do
    t = Thread.new {
      -> {
        @server.accept
      }.should raise_error(Exception, "interrupted")
    }

    Thread.pass while t.status and t.status != "sleep"
    t.raise Exception, "interrupted"
    t.join
  end

  it "is automatically retried when interrupted by SIGVTALRM" do
    t = Thread.new do
      client = @server.accept
      value = client.read(2)
      client.close
      value
    end

    Thread.pass while t.status and t.status != "sleep"
    # Thread#backtrace uses SIGVTALRM on TruffleRuby and potentially other implementations.
    # Sending a signal to a thread is not possible with Ruby APIs.
    t.backtrace.join("\n").should.include?("in `accept'")

    socket = TCPSocket.new('127.0.0.1', @port)
    socket.write("OK")
    socket.close

    t.value.should == "OK"
  end

  it "raises an IOError if the socket is closed" do
    @server.close
    -> { @server.accept }.should raise_error(IOError)
  end
end

describe 'TCPServer#accept' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @server = TCPServer.new(ip_address, 0)
    end

    after do
      @server.close
    end

    describe 'without a connected client' do
      it 'blocks the caller' do
        -> { @server.accept }.should block_caller
      end
    end

    describe 'with a connected client' do
      before do
        @client = TCPSocket.new(ip_address, @server.connect_address.ip_port)
      end

      after do
        @socket.close if @socket
        @client.close
      end

      it 'returns a TCPSocket' do
        @socket = @server.accept
        @socket.should be_an_instance_of(TCPSocket)
      end
    end
  end
end
