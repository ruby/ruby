require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#setsockopt" do

  before :each do
    @sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  end

  after :each do
    @sock.close unless @sock.closed?
  end

  it "sets the socket linger to 0" do
    linger = [0, 0].pack("ii")
    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, linger).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER).to_s

    if (n.size == 8) # linger struct on some platforms, not just a value
      n.should == [0, 0].pack("ii")
    else
      n.should == [0].pack("i")
    end
  end

  it "sets the socket linger to some positive value" do
    linger = [64, 64].pack("ii")
    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, linger).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER).to_s
    if (n.size == 8) # linger struct on some platforms, not just a value
      a = n.unpack('ii')
      a[0].should_not == 0
      a[1].should == 64
    else
      n.should == [64].pack("i")
    end
  end

  platform_is_not :windows do
    it "raises EINVAL if passed wrong linger value" do
      -> do
        @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, 0)
      end.should raise_error(Errno::EINVAL)
    end
  end

  platform_is_not :aix do
    # A known bug in AIX.  getsockopt(2) does not properly set
    # the fifth argument for SO_TYPE, SO_OOBINLINE, SO_BROADCAST, etc.

    it "sets the socket option Socket::SO_OOBINLINE" do
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, true).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, false).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, 1).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, 0).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, 2).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")

      platform_is_not :windows do
        -> {
          @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "")
        }.should raise_error(SystemCallError)
      end

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "blah").should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")

      platform_is_not :windows do
        -> {
          @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "0")
        }.should raise_error(SystemCallError)
      end

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "\x00\x00\x00\x00").should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should == [0].pack("i")

      platform_is_not :windows do
        -> {
          @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "1")
        }.should raise_error(SystemCallError)
      end

      platform_is_not :windows do
        -> {
          @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, "\x00\x00\x00")
        }.should raise_error(SystemCallError)
      end

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, [1].pack('i')).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, [0].pack('i')).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should == [0].pack("i")

      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, [1000].pack('i')).should == 0
      n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE).to_s
      n.should_not == [0].pack("i")
    end
  end

  it "sets the socket option Socket::SO_SNDBUF" do
    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 4000).should == 0
    sndbuf = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    # might not always be possible to set to exact size
    sndbuf.unpack('i')[0].should >= 4000

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, true).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= 1

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, nil).should == 0
    }.should raise_error(TypeError)

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 1).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= 1

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 2).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= 2

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "")
    }.should raise_error(SystemCallError)

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "bla")
    }.should raise_error(SystemCallError)

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "0")
    }.should raise_error(SystemCallError)

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "1")
    }.should raise_error(SystemCallError)

    -> {
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "\x00\x00\x00")
    }.should raise_error(SystemCallError)

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, "\x00\x00\x01\x00").should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= "\x00\x00\x01\x00".unpack('i')[0]

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, [4000].pack('i')).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= 4000

    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, [1000].pack('i')).should == 0
    n = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF).to_s
    n.unpack('i')[0].should >= 1000
  end

  platform_is_not :aix do
    describe 'accepts Socket::Option as argument' do
      it 'boolean' do
        option = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
        @sock.setsockopt(option).should == 0
        @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).bool.should == true
      end

      it 'int' do
        option = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
        @sock.setsockopt(option).should == 0
        @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).bool.should == true
      end
    end
  end

  platform_is :aix do
    describe 'accepts Socket::Option as argument' do
      it 'boolean' do
        option = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
        @sock.setsockopt(option).should == 0
      end

      it 'int' do
        option = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
        @sock.setsockopt(option).should == 0
      end
    end
  end

  describe 'accepts Socket::Option as argument' do
    it 'linger' do
      option = Socket::Option.linger(true, 10)
      @sock.setsockopt(option).should == 0
      onoff, seconds = @sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER).linger
      seconds.should == 10
      # Both results can be produced depending on the OS and value of Socket::SO_LINGER
      [true, Socket::SO_LINGER].should include(onoff)
    end
  end
end

describe 'BasicSocket#setsockopt' do
  describe 'using a STREAM socket' do
    before do
      @socket = Socket.new(:INET, :STREAM)
    end

    after do
      @socket.close
    end

    describe 'using separate arguments with Symbols' do
      it 'raises TypeError when the first argument is nil' do
        -> { @socket.setsockopt(nil, :REUSEADDR, true) }.should raise_error(TypeError)
      end

      it 'sets a boolean option' do
        @socket.setsockopt(:SOCKET, :REUSEADDR, true).should == 0
        @socket.getsockopt(:SOCKET, :REUSEADDR).bool.should == true
      end

      it 'sets an integer option' do
        @socket.setsockopt(:IP, :TTL, 255).should == 0
        @socket.getsockopt(:IP, :TTL).int.should == 255
      end

      guard -> { SocketSpecs.ipv6_available? } do
        it 'sets an IPv6 boolean option' do
          socket = Socket.new(:INET6, :STREAM)
          begin
            socket.setsockopt(:IPV6, :V6ONLY, true).should == 0
            socket.getsockopt(:IPV6, :V6ONLY).bool.should == true
          ensure
            socket.close
          end
        end
      end

      platform_is_not :windows do
        it 'raises Errno::EINVAL when setting an invalid option value' do
          -> { @socket.setsockopt(:SOCKET, :OOBINLINE, 'bla') }.should raise_error(Errno::EINVAL)
        end
      end
    end

    describe 'using separate arguments with Symbols' do
      it 'sets a boolean option' do
        @socket.setsockopt('SOCKET', 'REUSEADDR', true).should == 0
        @socket.getsockopt(:SOCKET, :REUSEADDR).bool.should == true
      end

      it 'sets an integer option' do
        @socket.setsockopt('IP', 'TTL', 255).should == 0
        @socket.getsockopt(:IP, :TTL).int.should == 255
      end
    end

    describe 'using separate arguments with constants' do
      it 'sets a boolean option' do
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true).should == 0
        @socket.getsockopt(:SOCKET, :REUSEADDR).bool.should == true
      end

      it 'sets an integer option' do
        @socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, 255).should == 0
        @socket.getsockopt(:IP, :TTL).int.should == 255
      end
    end

    describe 'using separate arguments with custom objects' do
      it 'sets a boolean option' do
        level = mock(:level)
        name  = mock(:name)

        level.stub!(:to_str).and_return('SOCKET')
        name.stub!(:to_str).and_return('REUSEADDR')

        @socket.setsockopt(level, name, true).should == 0
      end
    end

    describe 'using a Socket::Option as the first argument' do
      it 'sets a boolean option' do
        @socket.setsockopt(Socket::Option.bool(:INET, :SOCKET, :REUSEADDR, true)).should == 0
        @socket.getsockopt(:SOCKET, :REUSEADDR).bool.should == true
      end

      it 'sets an integer option' do
        @socket.setsockopt(Socket::Option.int(:INET, :IP, :TTL, 255)).should == 0
        @socket.getsockopt(:IP, :TTL).int.should == 255
      end

      it 'raises ArgumentError when passing 2 arguments' do
        option = Socket::Option.bool(:INET, :SOCKET, :REUSEADDR, true)
        -> { @socket.setsockopt(option, :REUSEADDR) }.should raise_error(ArgumentError)
      end

      it 'raises TypeError when passing 3 arguments' do
        option = Socket::Option.bool(:INET, :SOCKET, :REUSEADDR, true)
        -> { @socket.setsockopt(option, :REUSEADDR, true) }.should raise_error(TypeError)
      end
    end
  end

  with_feature :unix_socket do
    describe 'using a UNIX socket' do
      before do
        @path = SocketSpecs.socket_path
        @server = UNIXServer.new(@path)
      end

      after do
        @server.close
        rm_r @path
      end

      it 'sets a boolean option' do
        @server.setsockopt(:SOCKET, :REUSEADDR, true)
        @server.getsockopt(:SOCKET, :REUSEADDR).bool.should == true
      end
    end
  end
end
