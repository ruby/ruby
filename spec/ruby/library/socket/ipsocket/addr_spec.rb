require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::IPSocket#addr" do
  before :each do
    @do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    @socket = TCPServer.new("127.0.0.1", 0)
  end

  after :each do
    @socket.close unless @socket.closed?
    BasicSocket.do_not_reverse_lookup = @do_not_reverse_lookup
  end

  it "returns an array with the socket's information" do
    @socket.do_not_reverse_lookup = false
    BasicSocket.do_not_reverse_lookup = false
    addrinfo = @socket.addr
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should be_kind_of(Integer)
    addrinfo[2].should == SocketSpecs.hostname
    addrinfo[3].should == "127.0.0.1"
  end

  it "returns an address in the array if do_not_reverse_lookup is true" do
    @socket.do_not_reverse_lookup = true
    BasicSocket.do_not_reverse_lookup = true
    addrinfo = @socket.addr
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should be_kind_of(Integer)
    addrinfo[2].should == "127.0.0.1"
    addrinfo[3].should == "127.0.0.1"
  end

  it "returns an address in the array if passed false" do
    addrinfo = @socket.addr(false)
    addrinfo[0].should == "AF_INET"
    addrinfo[1].should be_kind_of(Integer)
    addrinfo[2].should == "127.0.0.1"
    addrinfo[3].should == "127.0.0.1"
  end
end

describe 'Socket::IPSocket#addr' do
  SocketSpecs.each_ip_protocol do |family, ip_address, family_name|
    before do
      @server = TCPServer.new(ip_address, 0)
      @port = @server.connect_address.ip_port
    end

    after do
      @server.close
    end

    describe 'without reverse lookups' do
      before do
        @hostname = Socket.getaddrinfo(ip_address, nil)[0][2]
      end

      it 'returns an Array containing address information' do
        @server.addr.should == [family_name, @port, @hostname, ip_address]
      end
    end

    describe 'with reverse lookups' do
      before do
        @hostname = Socket.getaddrinfo(ip_address, nil, nil, 0, 0, 0, true)[0][2]
      end

      describe 'using true as the argument' do
        it 'returns an Array containing address information' do
          @server.addr(true).should == [family_name, @port, @hostname, ip_address]
        end
      end

      describe 'using :hostname as the argument' do
        it 'returns an Array containing address information' do
          @server.addr(:hostname).should == [family_name, @port, @hostname, ip_address]
        end
      end

      describe 'using :cats as the argument' do
        it 'raises ArgumentError' do
          lambda { @server.addr(:cats) }.should raise_error(ArgumentError)
        end
      end
    end

    describe 'with do_not_reverse_lookup disabled on socket level' do
      before do
        @server.do_not_reverse_lookup = false

        @hostname = Socket.getaddrinfo(ip_address, nil, nil, 0, 0, 0, true)[0][2]
      end

      after do
        @server.do_not_reverse_lookup = true
      end

      it 'returns an Array containing address information' do
        @server.addr.should == [family_name, @port, @hostname, ip_address]
      end
    end
  end
end
