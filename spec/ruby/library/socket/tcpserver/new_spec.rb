require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer.new" do
  after :each do
    @server.close if @server && !@server.closed?
  end

  it "binds to a host and a port" do
    @server = TCPServer.new('127.0.0.1', 0)
    addr = @server.addr
    addr[0].should == 'AF_INET'
    addr[1].should be_kind_of(Integer)
    # on some platforms (Mac), MRI
    # returns comma at the end.
    addr[2].should =~ /^#{SocketSpecs.hostname}\b/
    addr[3].should == '127.0.0.1'
  end

  it "binds to localhost and a port with either IPv4 or IPv6" do
    @server = TCPServer.new(SocketSpecs.hostname, 0)
    addr = @server.addr
    addr[1].should be_kind_of(Integer)
    if addr[0] == 'AF_INET'
      addr[2].should =~ /^#{SocketSpecs.hostname}\b/
      addr[3].should == '127.0.0.1'
    else
      addr[2].should =~ /^#{SocketSpecs.hostname('::1')}\b/
      addr[3].should == '::1'
    end
  end

  it "binds to INADDR_ANY if the hostname is empty" do
    @server = TCPServer.new('', 0)
    addr = @server.addr
    addr[0].should == 'AF_INET'
    addr[1].should be_kind_of(Integer)
    addr[2].should == '0.0.0.0'
    addr[3].should == '0.0.0.0'
  end

  it "binds to INADDR_ANY if the hostname is empty and the port is a string" do
    @server = TCPServer.new('', '0')
    addr = @server.addr
    addr[0].should == 'AF_INET'
    addr[1].should be_kind_of(Integer)
    addr[2].should == '0.0.0.0'
    addr[3].should == '0.0.0.0'
  end

  it "binds to a port if the port is explicitly nil" do
    @server = TCPServer.new('', nil)
    addr = @server.addr
    addr[0].should == 'AF_INET'
    addr[1].should be_kind_of(Integer)
    addr[2].should == '0.0.0.0'
    addr[3].should == '0.0.0.0'
  end

  it "binds to a port if the port is an empty string" do
    @server = TCPServer.new('', '')
    addr = @server.addr
    addr[0].should == 'AF_INET'
    addr[1].should be_kind_of(Integer)
    addr[2].should == '0.0.0.0'
    addr[3].should == '0.0.0.0'
  end

  it "coerces port to string, then determines port from that number or service name" do
    -> { TCPServer.new(SocketSpecs.hostname, Object.new) }.should raise_error(TypeError)

    port = Object.new
    port.should_receive(:to_str).and_return("0")

    @server = TCPServer.new(SocketSpecs.hostname, port)
    addr = @server.addr
    addr[1].should be_kind_of(Integer)

    # TODO: This should also accept strings like 'https', but I don't know how to
    # pick such a service port that will be able to reliably bind...
  end

  it "has a single argument form and treats it as a port number" do
    @server = TCPServer.new(0)
    addr = @server.addr
    addr[1].should be_kind_of(Integer)
  end

  it "coerces port to a string when it is the only argument" do
    -> { TCPServer.new(Object.new) }.should raise_error(TypeError)

    port = Object.new
    port.should_receive(:to_str).and_return("0")

    @server = TCPServer.new(port)
    addr = @server.addr
    addr[1].should be_kind_of(Integer)
  end

  it "does not use the given block and warns to use TCPServer::open" do
    -> {
      @server = TCPServer.new(0) { raise }
    }.should complain(/warning: TCPServer::new\(\) does not take block; use TCPServer::open\(\) instead/)
  end

  it "raises Errno::EADDRNOTAVAIL when the address is unknown" do
    -> { TCPServer.new("1.2.3.4", 0) }.should raise_error(Errno::EADDRNOTAVAIL)
  end

  # There is no way to make this fail-proof on all machines, because
  # DNS servers like opendns return A records for ANY host, including
  # traditionally invalidly named ones.
  quarantine! do
    it "raises a SocketError when the host is unknown" do
      -> {
        TCPServer.new("--notavalidname", 0)
      }.should raise_error(SocketError)
    end
  end

  it "raises Errno::EADDRINUSE when address is already in use" do
    @server = TCPServer.new('127.0.0.1', 0)
    -> {
      @server = TCPServer.new('127.0.0.1', @server.addr[1])
    }.should raise_error(Errno::EADDRINUSE)
  end

  platform_is_not :windows, :aix do
    # A known bug in AIX.  getsockopt(2) does not properly set
    # the fifth argument for SO_REUSEADDR.
    it "sets SO_REUSEADDR on the resulting server" do
      @server = TCPServer.new('127.0.0.1', 0)
      @server.getsockopt(:SOCKET, :REUSEADDR).data.should_not == "\x00\x00\x00\x00"
      @server.getsockopt(:SOCKET, :REUSEADDR).int.should_not == 0
    end
  end
end
