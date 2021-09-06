# frozen_string_literal: true

begin
  require "socket"
  require "test/unit"
  require "io/nonblock"
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
      rescue Test::Unit::AssertionFailedError
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
    sserv = TCPServer.new('localhost', 0)
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

  def test_read_write_nonblock
    socks do |sserv, ssock, csock|
      set_nb = true
      buf = String.new
      if ssock.respond_to?(:nonblock?)
        csock.nonblock = ssock.nonblock = false

        # Linux may use MSG_DONTWAIT to avoid setting O_NONBLOCK
        if RUBY_PLATFORM.match?(/linux/) && Socket.const_defined?(:MSG_DONTWAIT)
          set_nb = false
        end
      end
      assert_equal :wait_readable, ssock.read_nonblock(1, buf, exception: false)
      assert_equal 5, csock.write_nonblock('hello')
      IO.select([ssock])
      assert_same buf, ssock.read_nonblock(5, buf, exception: false)
      assert_equal 'hello', buf
      buf = '*' * 16384
      n = 0

      case w = csock.write_nonblock(buf, exception: false)
      when Integer
        n += w
      when :wait_writable
        break
      end while true

      assert_equal :wait_writable, w
      assert_raise(IO::WaitWritable) { loop { csock.write_nonblock(buf) } }
      assert_operator n, :>, 0
      assert_not_predicate(csock, :nonblock?, '[Feature #13362]') unless set_nb
      csock.close

      case r = ssock.read_nonblock(16384, buf, exception: false)
      when String
        next
      when nil
        break
      when :wait_readable
        IO.select([ssock], nil, nil, 10) or
          flunk 'socket did not become readable'
      else
        flunk "unexpected read_nonblock return: #{r.inspect}"
      end while true

      assert_raise(EOFError) { ssock.read_nonblock(1) }

      assert_not_predicate(ssock, :nonblock?) unless set_nb
    end
  end

  def test_read_nonblock_mix_buffered
    socks do |sserv, ssock, csock|
      ssock.write("hello\nworld\n")
      assert_equal "hello\n", csock.gets
      IO.select([csock], nil, nil, 10) or
        flunk 'socket did not become readable'
      assert_equal "world\n", csock.read_nonblock(8)
    end
  end

  def test_write_nonblock_buffered
    socks do |sserv, ssock, csock|
      ssock.sync = false
      ssock.write("h")
      assert_equal :wait_readable, csock.read_nonblock(1, exception: false)
      assert_equal 4, ssock.write_nonblock("ello")
      ssock.close
      assert_equal "hello", csock.read(5)
    end
  end
end if defined?(BasicSocket)
