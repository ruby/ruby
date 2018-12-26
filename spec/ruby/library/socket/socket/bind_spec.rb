require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#bind on SOCK_DGRAM socket" do
  before :each do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
    @sockaddr = Socket.pack_sockaddr_in(0, "127.0.0.1")
  end

  after :each do
    @sock.closed?.should be_false
    @sock.close
  end

  it "binds to a port" do
    lambda { @sock.bind(@sockaddr) }.should_not raise_error
  end

  it "returns 0 if successful" do
    @sock.bind(@sockaddr).should == 0
  end

  it "raises Errno::EINVAL when already bound" do
    @sock.bind(@sockaddr)

    lambda { @sock.bind(@sockaddr) }.should raise_error(Errno::EINVAL)
  end

  it "raises Errno::EADDRNOTAVAIL when the specified sockaddr is not available from the local machine" do
    sockaddr1 = Socket.pack_sockaddr_in(0, "4.3.2.1")
    lambda { @sock.bind(sockaddr1) }.should raise_error(Errno::EADDRNOTAVAIL)
  end

  platform_is_not :windows, :cygwin do
    as_user do
      it "raises Errno::EACCES when the current user does not have permission to bind" do
        sockaddr1 = Socket.pack_sockaddr_in(1, "127.0.0.1")
        lambda { @sock.bind(sockaddr1) }.should raise_error(Errno::EACCES)
      end
    end
  end
end

describe "Socket#bind on SOCK_STREAM socket" do
  before :each do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @sockaddr = Socket.pack_sockaddr_in(0, "127.0.0.1")
  end

  after :each do
    @sock.closed?.should be_false
    @sock.close
  end

  it "binds to a port" do
    lambda { @sock.bind(@sockaddr) }.should_not raise_error
  end

  it "returns 0 if successful" do
    @sock.bind(@sockaddr).should == 0
  end

  it "raises Errno::EINVAL when already bound" do
    @sock.bind(@sockaddr)

    lambda { @sock.bind(@sockaddr) }.should raise_error(Errno::EINVAL)
  end

  it "raises Errno::EADDRNOTAVAIL when the specified sockaddr is not available from the local machine" do
    sockaddr1 = Socket.pack_sockaddr_in(0, "4.3.2.1")
    lambda { @sock.bind(sockaddr1) }.should raise_error(Errno::EADDRNOTAVAIL)
  end

  platform_is_not :windows, :cygwin do
    as_user do
      it "raises Errno::EACCES when the current user does not have permission to bind" do
        sockaddr1 = Socket.pack_sockaddr_in(1, "127.0.0.1")
        lambda { @sock.bind(sockaddr1) }.should raise_error(Errno::EACCES)
      end
    end
  end
end

describe 'Socket#bind' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'using a packed socket address' do
      before do
        @socket = Socket.new(family, :DGRAM)
        @sockaddr = Socket.sockaddr_in(0, ip_address)
      end

      after do
        @socket.close
      end

      it 'returns 0 when successfully bound' do
        @socket.bind(@sockaddr).should == 0
      end

      it 'raises Errno::EINVAL when binding to an already bound port' do
        @socket.bind(@sockaddr)

        lambda { @socket.bind(@sockaddr) }.should raise_error(Errno::EINVAL)
      end

      it 'raises Errno::EADDRNOTAVAIL when the specified sockaddr is not available' do
        ip = family == Socket::AF_INET ? '4.3.2.1' : '::2'
        sockaddr1 = Socket.sockaddr_in(0, ip)

        lambda { @socket.bind(sockaddr1) }.should raise_error(Errno::EADDRNOTAVAIL)
      end

      platform_is_not :windows do
        as_user do
          it 'raises Errno::EACCES when the user is not allowed to bind to the port' do
            sockaddr1 = Socket.pack_sockaddr_in(1, ip_address)

            lambda { @socket.bind(sockaddr1) }.should raise_error(Errno::EACCES)
          end
       end
      end
    end

    describe 'using an Addrinfo' do
      before do
        @addr   = Addrinfo.udp(ip_address, 0)
        @socket = Socket.new(@addr.afamily, @addr.socktype)
      end

      after do
        @socket.close
      end

      it 'binds to an Addrinfo' do
        @socket.bind(@addr).should == 0
        @socket.local_address.should be_an_instance_of(Addrinfo)
      end

      it 'uses a new Addrinfo for the local address' do
        @socket.bind(@addr)
        @socket.local_address.should_not == @addr
      end
    end
  end
end
