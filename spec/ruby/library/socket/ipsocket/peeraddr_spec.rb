require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::IPSocket#peeraddr" do
  before :each do
    @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @client = TCPSocket.new("127.0.0.1", @port)
  end

  after :each do
    @server.close unless @server.closed?
    @client.close unless @client.closed?
    BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  it "raises error if socket is not connected" do
    lambda {
      @server.peeraddr
    }.should raise_error(Errno::ENOTCONN)
  end

  it "returns an array of information on the peer" do
    @client.do_not_reverse_lookup = false
    BasicSocket.do_not_reverse_lookup = false
    addrinfo = @client.peeraddr
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should == @port
    addrinfo[2].should == SocketSpecs.hostname
    addrinfo[3].should == "127.0.0.1"
  end

  it "returns an IP instead of hostname if do_not_reverse_lookup is true" do
    @client.do_not_reverse_lookup = true
    BasicSocket.do_not_reverse_lookup = true
    addrinfo = @client.peeraddr
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should == @port
    addrinfo[2].should == "127.0.0.1"
    addrinfo[3].should == "127.0.0.1"
  end

  it "returns an IP instead of hostname if passed false" do
    addrinfo = @client.peeraddr(false)
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should == @port
    addrinfo[2].should == "127.0.0.1"
    addrinfo[3].should == "127.0.0.1"
  end
end

describe 'Socket::IPSocket#peeraddr' do
  SocketSpecs.each_ip_protocol do |family, ip_address, family_name|
    before do
      @server = TCPServer.new(ip_address, 0)
      @port   = @server.connect_address.ip_port
      @client = TCPSocket.new(ip_address, @port)
    end

    after do
      @client.close
      @server.close
    end

    describe 'without reverse lookups' do
      before do
        @hostname = Socket.getaddrinfo(ip_address, nil)[0][2]
      end

      it 'returns an Array containing address information' do
        @client.peeraddr.should == [family_name, @port, @hostname, ip_address]
      end
    end

    describe 'with reverse lookups' do
      before do
        @hostname = Socket.getaddrinfo(ip_address, nil, nil, 0, 0, 0, true)[0][2]
      end

      describe 'using true as the argument' do
        it 'returns an Array containing address information' do
          @client.peeraddr(true).should == [family_name, @port, @hostname, ip_address]
        end
      end

      describe 'using :hostname as the argument' do
        it 'returns an Array containing address information' do
          @client.peeraddr(:hostname).should == [family_name, @port, @hostname, ip_address]
        end
      end

      describe 'using :cats as the argument' do
        it 'raises ArgumentError' do
          lambda { @client.peeraddr(:cats) }.should raise_error(ArgumentError)
        end
      end
    end

    describe 'with do_not_reverse_lookup disabled on socket level' do
      before do
        @client.do_not_reverse_lookup = false

        @hostname = Socket.getaddrinfo(ip_address, nil, nil, 0, 0, 0, true)[0][2]
        @port     = @client.local_address.ip_port
      end

      after do
        @client.do_not_reverse_lookup = true
      end

      it 'returns an Array containing address information' do
        @client.addr.should == [family_name, @port, @hostname, ip_address]
      end
    end
  end
end
