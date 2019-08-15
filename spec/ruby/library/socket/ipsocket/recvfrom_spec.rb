require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::IPSocket#recvfrom" do
  before :each do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @client = TCPSocket.new("127.0.0.1", @port)
  end

  after :each do
    @server.close unless @server.closed?
    @client.close unless @client.closed?
  end

  it "reads data from the connection" do
    data = nil
    t = Thread.new do
      client = @server.accept
      begin
        data = client.recvfrom(6)
      ensure
        client.close
      end
    end

    @client.send('hello', 0)
    @client.shutdown rescue nil
    # shutdown may raise Errno::ENOTCONN when sent data is pending.
    t.join

    data.first.should == 'hello'
  end

  it "reads up to len bytes" do
    data = nil
    t = Thread.new do
      client = @server.accept
      begin
        data = client.recvfrom(3)
      ensure
        client.close
      end
    end

    @client.send('hello', 0)
    @client.shutdown rescue nil
    t.join

    data.first.should == 'hel'
  end

  it "returns an array with the data and connection info" do
    data = nil
    t = Thread.new do
      client = @server.accept
      data = client.recvfrom(3)
      client.close
    end

    @client.send('hello', 0)
    @client.shutdown rescue nil
    t.join

    data.size.should == 2
    data.first.should == "hel"
    # This does not apply to every platform, dependant on recvfrom(2)
    # data.last.should == nil
  end
end

describe 'Socket::IPSocket#recvfrom' do
  SocketSpecs.each_ip_protocol do |family, ip_address, family_name|
    before do
      @server = UDPSocket.new(family)
      @client = UDPSocket.new(family)

      @server.bind(ip_address, 0)
      @client.connect(ip_address, @server.connect_address.ip_port)

      @hostname = Socket.getaddrinfo(ip_address, nil)[0][2]
    end

    after do
      @client.close
      @server.close
    end

    it 'returns an Array containing up to N bytes and address information' do
      @client.write('hello')

      port = @client.local_address.ip_port
      ret  = @server.recvfrom(2)

      ret.should == ['he', [family_name, port, @hostname, ip_address]]
    end

    it 'allows specifying of flags when receiving data' do
      @client.write('hello')

      @server.recvfrom(2, Socket::MSG_PEEK)[0].should == 'he'

      @server.recvfrom(2)[0].should == 'he'
    end

    describe 'using reverse lookups' do
      before do
        @server.do_not_reverse_lookup = false

        @hostname = Socket.getaddrinfo(ip_address, nil, 0, 0, 0, 0, true)[0][2]
      end

      it 'includes the hostname in the address Array' do
        @client.write('hello')

        port = @client.local_address.ip_port
        ret  = @server.recvfrom(2)

        ret.should == ['he', [family_name, port, @hostname, ip_address]]
      end
    end
  end
end
