require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#getsockopt" do
  before :each do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  end

  after :each do
    @sock.closed?.should be_false
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
    lambda { @sock.getsockopt Socket::SOL_SOCKET, -1 }.should raise_error(Errno::ENOPROTOOPT)
  end

  it 'returns a Socket::Option using a constant' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)

    opt.should be_an_instance_of(Socket::Option)
  end

  it 'returns a Socket::Option for a boolean option' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)

    opt.bool.should == false
  end

  it 'returns a Socket::Option for a numeric option' do
    opt = @sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL)

    opt.int.should be_kind_of(Integer)
  end

  it 'returns a Socket::Option for a struct option' do
    opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER)

    opt.linger.should == [false, 0]
  end

  it 'raises Errno::ENOPROTOOPT when requesting an invalid option' do
    lambda { @sock.getsockopt(Socket::SOL_SOCKET, -1) }.should raise_error(Errno::ENOPROTOOPT)
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

  describe 'using a String based option' do
    it 'allows unpacking of a boolean option' do
      opt = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR).to_s

      opt.unpack('i').should == [0]
    end

    it 'allows unpacking of a numeric option' do
      opt   = @sock.getsockopt(Socket::IPPROTO_IP, Socket::IP_TTL).to_s
      array = opt.unpack('i')

      array[0].should be_kind_of(Integer)
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
