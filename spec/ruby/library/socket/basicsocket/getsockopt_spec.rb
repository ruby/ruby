require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#getsockopt" do
  before :each do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  end

  after :each do
    @sock.closed?.should == false
    @sock.close
  end

  platform_is_not :aix do
    # A known bug in AIX.  getsockopt(2) does not properly set
    # the fifth argument for SO_TYPE, SO_OOBINLINE, SO_BROADCAST, etc.

    it "gets a socket option Socket::SO_TYPE" do
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE).to_s
      n.should == [Socket::SOCK_STREAM].pack("i")
    end

    it "gets a socket option Socket::SO_OOBINLINE" do
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should == [0].pack("i")
    end
  end

  it "gets a socket option Socket::SO_LINGER" do
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER).to_s
    if (n.size == 8) # linger struct on some platforms, not just a value
      n.should == [0, 0].pack("ii")
    else
      n.should == [0].pack("i")
    end
  end

  it "gets a socket option Socket::SO_SNDBUF" do
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should > 0
  end

  it "raises a SystemCallError with an invalid socket option" do
    -> { @sock.getsockopt Socket::SOL_SOCKET, -1 }.should.raise(Errno::ENOPROTOOPT)
  end

  it 'returns a Socket::Option using a constant' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)

    opt.should.instance_of?(Socket::Option)
  end

  it 'returns a Socket::Option for a boolean option' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)

    opt.bool.should == false
  end

  it 'returns a Socket::Option for a numeric option' do
    opt = @sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL)

    opt.int.should.is_a?(Integer)
  end

  it 'returns a Socket::Option for a struct option' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER)

    opt.linger.should == [false, 0]
  end

  it 'raises Errno::ENOPROTOOPT when requesting an invalid option' do
    -> { @sock.getsockopt(Socket::SOL_SOCKET, -1) }.should.raise(Errno::ENOPROTOOPT)
  end

  describe 'using Symbols as arguments' do
    it 'returns a Socket::Option for arguments :SOCKET and :TYPE' do
      opt = @sock.getsockopt(:SOCKET, :TYPE)

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_TYPE
    end

    it 'returns a Socket::Option for arguments :IP and :TTL' do
      opt = @sock.getsockopt(:IP, :TTL)

      opt.level.should   == Socket::IPPROTO_IP
      opt.optname.should == Socket::IP_TTL
    end

    it 'returns a Socket::Option for arguments :SOCKET and :REUSEADDR' do
      opt = @sock.getsockopt(:SOCKET, :REUSEADDR)

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_REUSEADDR
    end

    it 'returns a Socket::Option for arguments :SOCKET and :LINGER' do
      opt = @sock.getsockopt(:SOCKET, :LINGER)

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_LINGER
    end

    with_feature :udp_cork do
      it 'returns a Socket::Option for arguments :UDP and :CORK' do
        sock = Socket.new(:INET, :DGRAM)
        begin
          opt  = sock.getsockopt(:UDP, :CORK)

          opt.level.should   == Socket::IPPROTO_UDP
          opt.optname.should == Socket::UDP_CORK
        ensure
          sock.close
        end
      end
    end
  end

  describe 'using Strings as arguments' do
    it 'returns a Socket::Option for arguments "SOCKET" and "TYPE"' do
      opt = @sock.getsockopt("SOCKET", "TYPE")

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_TYPE
    end

    it 'returns a Socket::Option for arguments "IP" and "TTL"' do
      opt = @sock.getsockopt("IP", "TTL")

      opt.level.should   == Socket::IPPROTO_IP
      opt.optname.should == Socket::IP_TTL
    end

    it 'returns a Socket::Option for arguments "SOCKET" and "REUSEADDR"' do
      opt = @sock.getsockopt("SOCKET", "REUSEADDR")

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_REUSEADDR
    end

    it 'returns a Socket::Option for arguments "SOCKET" and "LINGER"' do
      opt = @sock.getsockopt("SOCKET", "LINGER")

      opt.level.should   == Socket::SOL_SOCKET
      opt.optname.should == Socket::SO_LINGER
    end

    with_feature :udp_cork do
      it 'returns a Socket::Option for arguments "UDP" and "CORK"' do
        sock = Socket.new("INET", "DGRAM")
        begin
          opt  = sock.getsockopt("UDP", "CORK")

          opt.level.should   == Socket::IPPROTO_UDP
          opt.optname.should == Socket::UDP_CORK
        ensure
          sock.close
        end
      end
    end
  end

  platform_is_not :windows do
    describe 'using Socket::SO_ERROR' do
      before :each do
        # a TCP port with nothing listening on it: bind one, remember it, release it again
        server = TCPServer.new('127.0.0.1', 0)
        @refused = Socket.sockaddr_in(server.addr[1], '127.0.0.1')
        server.close

        @connecting = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      end

      after :each do
        @connecting.close unless @connecting.closed?
      end

      it 'returns 0 for a socket with no pending error' do
        @connecting.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int.should == 0
      end

      it 'returns the error of a refused non-blocking connect that IO.select reported as writable' do
        begin
          @connecting.connect_nonblock(@refused)
        rescue IO::WaitWritable
          # select(2) reports a non-blocking connect that failed as writable and leaves the
          # error on the socket, for getsockopt(SOL_SOCKET, SO_ERROR) to report
          IO.select(nil, [@connecting], nil, 10).should == [[], [@connecting], []]

          @connecting.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int.should ==
            Errno::ECONNREFUSED::Errno
        rescue Errno::ECONNREFUSED
          # some platforms refuse a loopback connect straight away, and then there is no
          # pending connect for select to report and no error left for getsockopt
        end
      end

      it 'leaves the socket valid until it is closed after a refused non-blocking connect' do
        begin
          @connecting.connect_nonblock(@refused)
        rescue IO::WaitWritable
          IO.select(nil, [@connecting], nil, 10)
          @connecting.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
        rescue Errno::ECONNREFUSED
        end

        @connecting.closed?.should == false
        @connecting.close
        @connecting.closed?.should == true
      end
    end
  end

  describe 'using a String based option' do
    it 'allows unpacking of a boolean option' do
      opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR).to_s

      opt.unpack('i').should == [0]
    end

    it 'allows unpacking of a numeric option' do
      opt   = @sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL).to_s
      array = opt.unpack('i')

      array[0].should.is_a?(Integer)
      array[0].should > 0
    end

    it 'allows unpacking of a struct option' do
      opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER).to_s

      if opt.bytesize == 8
        opt.unpack('ii').should == [0, 0]
      else
        opt.unpack('i').should == [0]
      end
    end
  end
end
