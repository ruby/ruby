require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "UDPSocket#bind" do
  before :each do
    @socket = UDPSocket.new
  end

  after :each do
    @socket.close unless @socket.closed?
  end

  it "binds the socket to a port" do
    @socket.bind(SocketSpecs.hostname, 0)
    @socket.addr[1].should be_kind_of(Integer)
  end

  it "raises Errno::EINVAL when already bound" do
    @socket.bind(SocketSpecs.hostname, 0)

    -> {
      @socket.bind(SocketSpecs.hostname, @socket.addr[1])
    }.should raise_error(Errno::EINVAL)
  end

  it "receives a hostname and a port" do
    @socket.bind(SocketSpecs.hostname, 0)

    port, host = Socket.unpack_sockaddr_in(@socket.getsockname)

    host.should == "127.0.0.1"
    port.should == @socket.addr[1]
  end

  it "binds to INADDR_ANY if the hostname is empty" do
    @socket.bind("", 0).should == 0
    port, host = Socket.unpack_sockaddr_in(@socket.getsockname)
    host.should == "0.0.0.0"
    port.should == @socket.addr[1]
  end
end

describe 'UDPSocket#bind' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before do
      @socket = UDPSocket.new(family)
    end

    after do
      @socket.close
    end

    it 'binds to an address and port' do
      @socket.bind(ip_address, 0).should == 0

      @socket.local_address.ip_address.should == ip_address
      @socket.local_address.ip_port.should > 0
    end

    it 'binds to an address and port using String arguments' do
      @socket.bind(ip_address, '0').should == 0

      @socket.local_address.ip_address.should == ip_address
      @socket.local_address.ip_port.should > 0
    end

    it 'can receive data after being bound to an address' do
      @socket.bind(ip_address, 0)

      addr   = @socket.connect_address
      client = UDPSocket.new(family)

      client.connect(addr.ip_address, addr.ip_port)
      client.write('hello')

      begin
        @socket.recv(6).should == 'hello'
      ensure
        client.close
      end
    end
  end
end
