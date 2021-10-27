require_relative '../fixtures/classes'

describe :socket_local_remote_address, shared: true do
  describe 'using TCPSocket' do
    before :each do
      @s = TCPServer.new('127.0.0.1', 0)
      @a = TCPSocket.new('127.0.0.1', @s.addr[1])
      @b = @s.accept
      @addr = @object.call(@a)
    end

    after :each do
      [@b, @a, @s].each(&:close)
    end

    it 'uses AF_INET as the address family' do
      @addr.afamily.should == Socket::AF_INET
    end

    it 'uses PF_INET as the protocol family' do
      @addr.pfamily.should == Socket::PF_INET
    end

    it 'uses SOCK_STREAM as the socket type' do
      @addr.socktype.should == Socket::SOCK_STREAM
    end

    it 'uses the correct IP address' do
      @addr.ip_address.should == '127.0.0.1'
    end

    it 'uses the correct port' do
      if @method == :local_address
        @addr.ip_port.should != @s.addr[1]
      else
        @addr.ip_port.should == @s.addr[1]
      end
    end

    it 'equals address of peer socket' do
      if @method == :local_address
        @addr.to_s.should == @b.remote_address.to_s
      else
        @addr.to_s.should == @b.local_address.to_s
      end
    end

    it 'returns an Addrinfo' do
      @addr.should be_an_instance_of(Addrinfo)
    end

    it 'uses 0 as the protocol' do
      @addr.protocol.should == 0
    end

    it 'can be used to connect to the server' do
      skip if @method == :local_address
      b = @addr.connect
      begin
        b.remote_address.to_s.should == @addr.to_s
      ensure
        b.close
      end
    end
  end

  guard -> { SocketSpecs.ipv6_available? } do
    describe 'using IPv6' do
      before :each do
        @s = TCPServer.new('::1', 0)
        @a = TCPSocket.new('::1', @s.addr[1])
        @b = @s.accept
        @addr = @object.call(@a)
      end

      after :each do
        [@b, @a, @s].each(&:close)
      end

      it 'uses AF_INET6 as the address family' do
        @addr.afamily.should == Socket::AF_INET6
      end

      it 'uses PF_INET6 as the protocol family' do
        @addr.pfamily.should == Socket::PF_INET6
      end

      it 'uses SOCK_STREAM as the socket type' do
        @addr.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses the correct IP address' do
        @addr.ip_address.should == '::1'
      end

      it 'uses the correct port' do
        if @method == :local_address
          @addr.ip_port.should != @s.addr[1]
        else
          @addr.ip_port.should == @s.addr[1]
        end
      end

      it 'equals address of peer socket' do
        if @method == :local_address
          @addr.to_s.should == @b.remote_address.to_s
        else
          @addr.to_s.should == @b.local_address.to_s
        end
      end

      it 'returns an Addrinfo' do
        @addr.should be_an_instance_of(Addrinfo)
      end

      it 'uses 0 as the protocol' do
        @addr.protocol.should == 0
      end

      it 'can be used to connect to the server' do
        skip if @method == :local_address
        b = @addr.connect
        begin
          b.remote_address.to_s.should == @addr.to_s
        ensure
          b.close
        end
      end
    end
  end

  with_feature :unix_socket do
    describe 'using UNIXSocket' do
      before :each do
        @path = SocketSpecs.socket_path
        @s = UNIXServer.new(@path)
        @a = UNIXSocket.new(@path)
        @b = @s.accept
        @addr = @object.call(@a)
      end

      after :each do
        [@b, @a, @s].each(&:close)
        rm_r(@path)
      end

      it 'uses AF_UNIX as the address family' do
        @addr.afamily.should == Socket::AF_UNIX
      end

      it 'uses PF_UNIX as the protocol family' do
        @addr.pfamily.should == Socket::PF_UNIX
      end

      it 'uses SOCK_STREAM as the socket type' do
        @addr.socktype.should == Socket::SOCK_STREAM
      end

      it 'uses the correct socket path' do
        if @method == :local_address
          @addr.unix_path.should == ""
        else
          @addr.unix_path.should == @path
        end
      end

      it 'equals address of peer socket' do
        if @method == :local_address
          @addr.to_s.should == @b.remote_address.to_s
        else
          @addr.to_s.should == @b.local_address.to_s
        end
      end

      it 'returns an Addrinfo' do
        @addr.should be_an_instance_of(Addrinfo)
      end

      it 'uses 0 as the protocol' do
        @addr.protocol.should == 0
      end

      it 'can be used to connect to the server' do
        skip if @method == :local_address
        b = @addr.connect
        begin
          b.remote_address.to_s.should == @addr.to_s
        ensure
          b.close
        end
      end
    end
  end

  describe 'using UDPSocket' do
    before :each do
      @s = UDPSocket.new
      @s.bind("127.0.0.1", 0)
      @a = UDPSocket.new
      @a.connect("127.0.0.1", @s.addr[1])
      @addr = @object.call(@a)
    end

    after :each do
      [@a, @s].each(&:close)
    end

    it 'uses the correct address family' do
      @addr.afamily.should == Socket::AF_INET
    end

    it 'uses the correct protocol family' do
      @addr.pfamily.should == Socket::PF_INET
    end

    it 'uses SOCK_DGRAM as the socket type' do
      @addr.socktype.should == Socket::SOCK_DGRAM
    end

    it 'uses the correct IP address' do
      @addr.ip_address.should == '127.0.0.1'
    end

    it 'uses the correct port' do
      if @method == :local_address
        @addr.ip_port.should != @s.addr[1]
      else
        @addr.ip_port.should == @s.addr[1]
      end
    end

    it 'returns an Addrinfo' do
      @addr.should be_an_instance_of(Addrinfo)
    end

    it 'uses 0 as the protocol' do
      @addr.protocol.should == 0
    end

    it 'can be used to connect to the peer' do
      b = @addr.connect
      begin
        b.remote_address.to_s.should == @addr.to_s
      ensure
        b.close
      end
    end
  end
end
