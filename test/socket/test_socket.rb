begin
  require "socket"
  require "test/unit"
rescue LoadError
end

class TestSocket < Test::Unit::TestCase
  def test_unpack_sockaddr
    sockaddr_in = Socket.sockaddr_in(80, "")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(sockaddr_in) }
    sockaddr_un = Socket.sockaddr_un("/tmp/s")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in(sockaddr_un) }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in("") }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un("") }
  end if Socket.respond_to?(:sockaddr_un)

  def test_sysaccept
    serv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen 5
    c = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    c.connect(serv.getsockname)
    fd, peeraddr = serv.sysaccept
    assert_equal(c.getsockname, peeraddr.to_sockaddr)
  ensure
    serv.close if serv
    c.close if c
    IO.for_fd(fd).close if fd
  end

  def test_initialize
    Socket.open(Socket::AF_INET, Socket::SOCK_STREAM, 0) {|s|
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(addr) }
    }
    Socket.open("AF_INET", "SOCK_STREAM", 0) {|s|
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(addr) }
    }
    Socket.open(:AF_INET, :SOCK_STREAM, 0) {|s|
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(addr) }
    }
  end

  def test_getaddrinfo
    # This should not send a DNS query because AF_UNIX.
    assert_raise(SocketError) { Socket.getaddrinfo("www.kame.net", 80, "AF_UNIX") }
  end

  def test_getnameinfo
    assert_raise(SocketError) { Socket.getnameinfo(["AF_UNIX", 80, "0.0.0.0"]) }
  end
end if defined?(Socket)
