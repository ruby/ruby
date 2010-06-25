begin
  require "socket"
  require "test/unit"
rescue LoadError
end

class TestBasicSocket < Test::Unit::TestCase
  def inet_stream
    sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    yield sock
  ensure
    assert_raise(IOError) {sock.close}
  end

  def test_getsockopt
    inet_stream do |s|
      n = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)
      assert_equal([Socket::SOCK_STREAM].pack("i"), n)
      n = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
      assert_equal([0].pack("i"), n)
      val = Object.new
      class << val; self end.__send__(:define_method, :to_int) {
        s.close
        Socket::SO_TYPE
      }
      assert_raise(IOError) {
        n = s.getsockopt(Socket::SOL_SOCKET, val)
      }
    end
  end

  def test_setsockopt # [ruby-dev:25039]
    s = nil
    linger = [0, 0].pack("ii")

    val = Object.new
    class << val; self end.__send__(:define_method, :to_str) {
      s.close
      linger
    }
    inet_stream do |s|
      assert_equal(0, s.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, linger))

      assert_raise(IOError) {
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, val)
      }
    end

    val = Object.new
    class << val; self end.__send__(:define_method, :to_int) {
      s.close
      Socket::SO_LINGER
    }
    inet_stream do |s|
      assert_raise(IOError) {
        s.setsockopt(Socket::SOL_SOCKET, val, linger)
      }
    end
  end

  def test_listen
    s = nil
    log = Object.new
    class << log; self end.__send__(:define_method, :to_int) {
      s.close
      2
    }
    inet_stream do |s|
      assert_raise(IOError) {
        s.listen(log)
      }
    end
  end

  def test_getaddrinfo_raises_no_errors_on_port_argument_of_0 # [ruby-core:29427]
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', 0, Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', '0', Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', '00', Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_raise(SocketError, '[ruby-core:29427]'){ Socket.getaddrinfo(nil, nil, Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ TCPServer.open('localhost', 0) {} }
  end
end if defined?(Socket)

class TestSocket < Test::Unit::TestCase
  def test_unpack_sockaddr
    sockaddr_in = Socket.sockaddr_in(80, "")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(sockaddr_in) }
    sockaddr_un = Socket.sockaddr_un("/tmp/s")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in(sockaddr_un) }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in("") }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un("") }
  end
end if defined?(Socket) && Socket.respond_to?(:sockaddr_un)
