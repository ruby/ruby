require_relative '../spec_helper'

describe "Addrinfo#initialize" do

  describe "with a sockaddr string" do

    describe "without a family" do
      before :each do
        @addrinfo = Addrinfo.new(Socket.sockaddr_in("smtp", "2001:DB8::1"))
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "2001:db8::1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 25
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_UNSPEC
      end

      it 'returns AF_INET as the default address family' do
        addr = Addrinfo.new(Socket.sockaddr_in(80, '127.0.0.1'))

        addr.afamily.should == Socket::AF_INET
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET6
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == 0
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end
    end

    describe "with a family given" do
      before :each do
        @addrinfo = Addrinfo.new(Socket.sockaddr_in("smtp", "2001:DB8::1"), Socket::PF_INET6)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "2001:db8::1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 25
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET6
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET6
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == 0
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end
    end

    describe "with a family and socket type" do
      before :each do
        @addrinfo = Addrinfo.new(Socket.sockaddr_in("smtp", "2001:DB8::1"), Socket::PF_INET6, Socket::SOCK_STREAM)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "2001:db8::1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 25
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET6
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET6
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == Socket::SOCK_STREAM
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end
    end

    describe "with a family, socket type and protocol" do
      before :each do
        @addrinfo = Addrinfo.new(Socket.sockaddr_in("smtp", "2001:DB8::1"), Socket::PF_INET6, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "2001:db8::1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 25
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET6
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET6
      end

      it "returns the specified socket type" do
        @addrinfo.socktype.should == Socket::SOCK_STREAM
      end

      it "returns the specified protocol" do
        @addrinfo.protocol.should == Socket::IPPROTO_TCP
      end
    end

  end

  describe "with a sockaddr array" do

    describe "without a family" do
      before :each do
        @addrinfo = Addrinfo.new(["AF_INET", 46102, "localhost", "127.0.0.1"])
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "127.0.0.1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 46102
      end

      it "returns the Socket::PF_INET pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == 0
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end
    end

    describe 'with a valid IP address' do
      # Uses AF_INET6 since AF_INET is the default, making it a better test
      # that Addrinfo actually sets the family correctly.
      before do
        @sockaddr = ['AF_INET6', 80, 'hostname', '::1']
      end

      it 'returns an Addrinfo with the correct IP' do
        addr = Addrinfo.new(@sockaddr)

        addr.ip_address.should == '::1'
      end

      it 'returns an Addrinfo with the correct address family' do
        addr = Addrinfo.new(@sockaddr)

        addr.afamily.should == Socket::AF_INET6
      end

      it 'returns an Addrinfo with the correct protocol family' do
        addr = Addrinfo.new(@sockaddr)

        addr.pfamily.should == Socket::PF_INET6
      end

      it 'returns an Addrinfo with the correct port' do
        addr = Addrinfo.new(@sockaddr)

        addr.ip_port.should == 80
      end
    end

    describe 'with an invalid IP address' do
      it 'raises SocketError' do
        block = lambda { Addrinfo.new(['AF_INET6', 80, 'hostname', '127.0.0.1']) }

        block.should raise_error(SocketError)
      end
    end

    describe "with a family given" do
      before :each do
        @addrinfo = Addrinfo.new(["AF_INET", 46102, "localhost", "127.0.0.1"], Socket::PF_INET)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "127.0.0.1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 46102
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == 0
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end
    end

    describe "with a family and socket type" do
      before :each do
        @addrinfo = Addrinfo.new(["AF_INET", 46102, "localhost", "127.0.0.1"], Socket::PF_INET, Socket::SOCK_STREAM)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "127.0.0.1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 46102
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == Socket::SOCK_STREAM
      end

      it "returns the 0 protocol" do
        @addrinfo.protocol.should == 0
      end

      [:SOCK_STREAM, :SOCK_DGRAM, :SOCK_RAW].each do |type|
        it "overwrites the socket type #{type}" do
          sockaddr = ['AF_INET', 80, 'hostname', '127.0.0.1']

          value = Socket.const_get(type)
          addr  = Addrinfo.new(sockaddr, nil, value)

          addr.socktype.should == value
        end
      end

      with_feature :sock_packet do
        [:SOCK_SEQPACKET].each do |type|
          it "overwrites the socket type #{type}" do
            sockaddr = ['AF_INET', 80, 'hostname', '127.0.0.1']

            value = Socket.const_get(type)
            addr  = Addrinfo.new(sockaddr, nil, value)

            addr.socktype.should == value
          end
        end
      end

      it "raises SocketError when using SOCK_RDM" do
        sockaddr = ['AF_INET', 80, 'hostname', '127.0.0.1']
        value = Socket::SOCK_RDM
        block = lambda { Addrinfo.new(sockaddr, nil, value) }

        block.should raise_error(SocketError)
      end
    end

    describe "with a family, socket type and protocol" do
      before :each do
        @addrinfo = Addrinfo.new(["AF_INET", 46102, "localhost", "127.0.0.1"], Socket::PF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
      end

      it "stores the ip address from the sockaddr" do
        @addrinfo.ip_address.should == "127.0.0.1"
      end

      it "stores the port number from the sockaddr" do
        @addrinfo.ip_port.should == 46102
      end

      it "returns the Socket::UNSPEC pfamily" do
        @addrinfo.pfamily.should == Socket::PF_INET
      end

      it "returns the INET6 afamily" do
        @addrinfo.afamily.should == Socket::AF_INET
      end

      it "returns the 0 socket type" do
        @addrinfo.socktype.should == Socket::SOCK_STREAM
      end

      it "returns the specified protocol" do
        @addrinfo.protocol.should == Socket::IPPROTO_TCP
      end
    end
  end

  describe 'using an Array with extra arguments' do
    describe 'with the AF_INET6 address family and an explicit protocol family' do
      before do
        @sockaddr = ['AF_INET6', 80, 'hostname', '127.0.0.1']
      end

      it "raises SocketError when using any Socket constant except except AF_INET(6)/PF_INET(6)" do
        Socket.constants.grep(/(^AF_|^PF_)(?!INET)/).each do |constant|
          value = Socket.const_get(constant)
          -> {
            Addrinfo.new(@sockaddr, value)
          }.should raise_error(SocketError)
        end
      end
    end

    describe 'with the AF_INET address family and an explicit socket protocol' do
      before do
        @sockaddr = ['AF_INET', 80, 'hostname', '127.0.0.1']
      end

      describe 'and no socket type is given' do
        valid = [:IPPROTO_IP, :IPPROTO_UDP, :IPPROTO_HOPOPTS]

        valid.each do |type|
          it "overwrites the protocol when using #{type}" do
            value = Socket.const_get(type)
            addr  = Addrinfo.new(@sockaddr, nil, nil, value)

            addr.protocol.should == value
          end
        end

        platform_is_not :windows, :aix, :solaris do
          (Socket.constants.grep(/^IPPROTO/) - valid).each do |type|
            it "raises SocketError when using #{type}" do
              value = Socket.const_get(type)
              block = lambda { Addrinfo.new(@sockaddr, nil, nil, value) }

              block.should raise_error(SocketError)
            end
          end
        end
      end

      describe 'and the socket type is set to SOCK_DGRAM' do
        before do
          @socktype = Socket::SOCK_DGRAM
        end

        valid = [:IPPROTO_IP, :IPPROTO_UDP, :IPPROTO_HOPOPTS]

        valid.each do |type|
          it "overwrites the protocol when using #{type}" do
            value = Socket.const_get(type)
            addr  = Addrinfo.new(@sockaddr, nil, @socktype, value)

            addr.protocol.should == value
          end
        end

        platform_is_not :windows, :aix, :solaris do
          (Socket.constants.grep(/^IPPROTO/) - valid).each do |type|
            it "raises SocketError when using #{type}" do
              value = Socket.const_get(type)
              block = lambda { Addrinfo.new(@sockaddr, nil, @socktype, value) }

              block.should raise_error(SocketError)
            end
          end
        end
      end

      with_feature :sock_packet do
        describe 'and the socket type is set to SOCK_PACKET' do
          before do
            @socktype = Socket::SOCK_PACKET
          end

          Socket.constants.grep(/^IPPROTO/).each do |type|
            it "raises SocketError when using #{type}" do
              value = Socket.const_get(type)
              block = lambda { Addrinfo.new(@sockaddr, nil, @socktype, value) }

              block.should raise_error(SocketError)
            end
          end
        end
      end

      describe 'and the socket type is set to SOCK_RAW' do
        before do
          @socktype = Socket::SOCK_RAW
        end

        Socket.constants.grep(/^IPPROTO/).each do |type|
          it "overwrites the protocol when using #{type}" do
            value = Socket.const_get(type)
            addr  = Addrinfo.new(@sockaddr, nil, @socktype, value)

            addr.protocol.should == value
          end
        end
      end

      describe 'and the socket type is set to SOCK_RDM' do
        before do
          @socktype = Socket::SOCK_RDM
        end

        Socket.constants.grep(/^IPPROTO/).each do |type|
          it "raises SocketError when using #{type}" do
            value = Socket.const_get(type)
            block = lambda { Addrinfo.new(@sockaddr, nil, @socktype, value) }

            block.should raise_error(SocketError)
          end
        end
      end

      platform_is :linux do
        describe 'and the socket type is set to SOCK_SEQPACKET' do
          before do
            @socktype = Socket::SOCK_SEQPACKET
          end

          valid = [:IPPROTO_IP, :IPPROTO_HOPOPTS]

          valid.each do |type|
            it "overwrites the protocol when using #{type}" do
              value = Socket.const_get(type)
              addr  = Addrinfo.new(@sockaddr, nil, @socktype, value)

              addr.protocol.should == value
            end
          end

          (Socket.constants.grep(/^IPPROTO/) - valid).each do |type|
            it "raises SocketError when using #{type}" do
              value = Socket.const_get(type)
              block = lambda { Addrinfo.new(@sockaddr, nil, @socktype, value) }

              block.should raise_error(SocketError)
            end
          end
        end
      end

      describe 'and the socket type is set to SOCK_STREAM' do
        before do
          @socktype = Socket::SOCK_STREAM
        end

        valid = [:IPPROTO_IP, :IPPROTO_TCP, :IPPROTO_HOPOPTS]

        valid.each do |type|
          it "overwrites the protocol when using #{type}" do
            value = Socket.const_get(type)
            addr  = Addrinfo.new(@sockaddr, nil, @socktype, value)

            addr.protocol.should == value
          end
        end

        platform_is_not :windows, :aix, :solaris do
          (Socket.constants.grep(/^IPPROTO/) - valid).each do |type|
            it "raises SocketError when using #{type}" do
              value = Socket.const_get(type)
              block = lambda { Addrinfo.new(@sockaddr, nil, @socktype, value) }

              block.should raise_error(SocketError)
            end
          end
        end
      end
    end
  end

  describe 'with Symbols' do
    before do
      @sockaddr = Socket.sockaddr_in(80, '127.0.0.1')
    end

    it 'returns an Addrinfo with :PF_INET  family' do
      addr = Addrinfo.new(@sockaddr, :PF_INET)

      addr.pfamily.should == Socket::PF_INET
    end

    it 'returns an Addrinfo with :INET  family' do
      addr = Addrinfo.new(@sockaddr, :INET)

      addr.pfamily.should == Socket::PF_INET
    end

    it 'returns an Addrinfo with :SOCK_STREAM as the socket type' do
      addr = Addrinfo.new(@sockaddr, nil, :SOCK_STREAM)

      addr.socktype.should == Socket::SOCK_STREAM
    end

    it 'returns an Addrinfo with :STREAM as the socket type' do
      addr = Addrinfo.new(@sockaddr, nil, :STREAM)

      addr.socktype.should == Socket::SOCK_STREAM
    end
  end

  describe 'with Strings' do
    before do
      @sockaddr = Socket.sockaddr_in(80, '127.0.0.1')
    end

    it 'returns an Addrinfo with "PF_INET"  family' do
      addr = Addrinfo.new(@sockaddr, 'PF_INET')

      addr.pfamily.should == Socket::PF_INET
    end

    it 'returns an Addrinfo with "INET"  family' do
      addr = Addrinfo.new(@sockaddr, 'INET')

      addr.pfamily.should == Socket::PF_INET
    end

    it 'returns an Addrinfo with "SOCK_STREAM" as the socket type' do
      addr = Addrinfo.new(@sockaddr, nil, 'SOCK_STREAM')

      addr.socktype.should == Socket::SOCK_STREAM
    end

    it 'returns an Addrinfo with "STREAM" as the socket type' do
      addr = Addrinfo.new(@sockaddr, nil, 'STREAM')

      addr.socktype.should == Socket::SOCK_STREAM
    end
  end

  with_feature :unix_socket do
    describe 'using separate arguments for a Unix socket' do
      before do
        @sockaddr = Socket.pack_sockaddr_un('socket')
      end

      it 'returns an Addrinfo with the correct unix path' do
        Addrinfo.new(@sockaddr).unix_path.should == 'socket'
      end

      it 'returns an Addrinfo with the correct protocol family' do
        Addrinfo.new(@sockaddr).pfamily.should == Socket::PF_UNSPEC
      end

      it 'returns an Addrinfo with the correct address family' do
        Addrinfo.new(@sockaddr).afamily.should == Socket::AF_UNIX
      end
    end
  end
end
