require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket.do_not_reverse_lookup" do
  before :each do
    @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @socket = TCPSocket.new('127.0.0.1', @port)
  end

  after :each do
    @server.close unless @server.closed?
    @socket.close unless @socket.closed?
    BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  it "defaults to true" do
    BasicSocket.do_not_reverse_lookup.should be_true
  end

  it "causes 'peeraddr' to avoid name lookups" do
    @socket.do_not_reverse_lookup = true
    BasicSocket.do_not_reverse_lookup = true
    @socket.peeraddr.should == ["AF_INET", @port, "127.0.0.1", "127.0.0.1"]
  end

  it "looks for hostnames when set to false" do
    @socket.do_not_reverse_lookup = false
    BasicSocket.do_not_reverse_lookup = false
    @socket.peeraddr[2].should == SocketSpecs.hostname
  end

  it "looks for numeric addresses when set to true" do
    @socket.do_not_reverse_lookup = true
    BasicSocket.do_not_reverse_lookup = true
    @socket.peeraddr[2].should == "127.0.0.1"
  end
end

describe :socket_do_not_reverse_lookup, shared: true do
  it "inherits from BasicSocket.do_not_reverse_lookup when the socket is created" do
    @socket = @method.call
    reverse = BasicSocket.do_not_reverse_lookup
    @socket.do_not_reverse_lookup.should == reverse

    BasicSocket.do_not_reverse_lookup = !reverse
    @socket.do_not_reverse_lookup.should == reverse
  end

  it "is true when BasicSocket.do_not_reverse_lookup is true" do
    BasicSocket.do_not_reverse_lookup = true
    @socket = @method.call
    @socket.do_not_reverse_lookup.should == true
  end

  it "is false when BasicSocket.do_not_reverse_lookup is false" do
    BasicSocket.do_not_reverse_lookup = false
    @socket = @method.call
    @socket.do_not_reverse_lookup.should == false
  end

  it "can be changed with #do_not_reverse_lookup=" do
    @socket = @method.call
    reverse = @socket.do_not_reverse_lookup
    @socket.do_not_reverse_lookup = !reverse
    @socket.do_not_reverse_lookup.should == !reverse
  end
end

describe "BasicSocket#do_not_reverse_lookup" do
  before :each do
    @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
  end

  after :each do
    @server.close unless @server.closed?
    @socket.close if @socket && !@socket.closed?
    BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  describe "for an TCPSocket.new socket" do
    it_behaves_like :socket_do_not_reverse_lookup, -> {
      TCPSocket.new('127.0.0.1', @port)
    }
  end

  describe "for an TCPServer#accept socket" do
    before :each do
      @client = TCPSocket.new('127.0.0.1', @port)
    end

    after :each do
      @client.close if @client && !@client.closed?
    end

    it_behaves_like :socket_do_not_reverse_lookup, -> {
      @server.accept
    }
  end
end
