# frozen_string_literal: true

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
    assert(sock.closed?)
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

  def socks
    sserv = TCPServer.new(0)
    ssock = nil
    t = Thread.new { ssock = sserv.accept }
    csock = TCPSocket.new('localhost', sserv.addr[1])
    t.join
    yield sserv, ssock, csock
  ensure
    ssock.close rescue nil
    csock.close rescue nil
    sserv.close rescue nil
  end

  def test_close_read
    socks do |sserv, ssock, csock|

      # close_read makes subsequent reads raise IOError
      csock.close_read
      assert_raise(IOError) { csock.read(5) }

      # close_read ignores any error from shutting down half of still-open socket
      assert_nothing_raised { csock.close_read }

      # close_read raises if socket is not open
      assert_nothing_raised { csock.close }
      assert_raise(IOError) { csock.close_read }
    end
  end

  def test_close_write
    socks do |sserv, ssock, csock|

      # close_write makes subsequent writes raise IOError
      csock.close_write
      assert_raise(IOError) { csock.write(5) }

      # close_write ignores any error from shutting down half of still-open socket
      assert_nothing_raised { csock.close_write }

      # close_write raises if socket is not open
      assert_nothing_raised { csock.close }
      assert_raise(IOError) { csock.close_write }
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
