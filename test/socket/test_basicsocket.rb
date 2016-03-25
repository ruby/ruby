begin
  require "socket"
  require "test/unit"
rescue LoadError
end

class TestSocket_BasicSocket < Test::Unit::TestCase
  def inet_stream
    sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    yield sock
  ensure
    assert_raise(IOError) {sock.close}
  end

  def test_getsockopt
    inet_stream do |s|
      begin
        n = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)
        assert_equal([Socket::SOCK_STREAM].pack("i"), n.data)

        n = s.getsockopt("SOL_SOCKET", "SO_TYPE")
        assert_equal([Socket::SOCK_STREAM].pack("i"), n.data)

        n = s.getsockopt(:SOL_SOCKET, :SO_TYPE)
        assert_equal([Socket::SOCK_STREAM].pack("i"), n.data)

        n = s.getsockopt(:SOCKET, :TYPE)
        assert_equal([Socket::SOCK_STREAM].pack("i"), n.data)

        n = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
        assert_equal([0].pack("i"), n.data)
      rescue Minitest::Assertion
        s.close
        if /aix/ =~ RUBY_PLATFORM
          skip "Known bug in getsockopt(2) on AIX"
        end
        raise $!
      end

      val = Object.new
      class << val; self end.send(:define_method, :to_int) {
        s.close
        Socket::SO_TYPE
      }
      assert_raise(IOError) {
        n = s.getsockopt(Socket::SOL_SOCKET, val)
      }
    end
  end

  def test_setsockopt
    s = nil
    linger = [0, 0].pack("ii")

    val = Object.new
    class << val; self end.send(:define_method, :to_str) {
      s.close
      linger
    }
    inet_stream do |sock|
      s = sock
      assert_equal(0, s.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, linger))

      assert_raise(IOError, "[ruby-dev:25039]") {
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, val)
      }
    end

    val = Object.new
    class << val; self end.send(:define_method, :to_int) {
      s.close
      Socket::SO_LINGER
    }
    inet_stream do |sock|
      s = sock
      assert_raise(IOError) {
        s.setsockopt(Socket::SOL_SOCKET, val, linger)
      }
    end
  end

  def test_listen
    s = nil
    log = Object.new
    class << log; self end.send(:define_method, :to_int) {
      s.close
      2
    }
    inet_stream do |sock|
      s = sock
      assert_raise(IOError) {
        s.listen(log)
      }
    end
  end
  def test_for_fd
    assert_raise(Errno::EBADF, '[ruby-core:72418] [Bug #11854]') do
      BasicSocket.for_fd(-1)
    end
    inet_stream do |sock|
      s = BasicSocket.for_fd(sock.fileno)
      assert_instance_of BasicSocket, s
      s.autoclose = false
      sock.close
    end
  end
end if defined?(BasicSocket)
