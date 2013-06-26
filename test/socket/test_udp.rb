begin
  require "socket"
  require "test/unit"
rescue LoadError
end


class TestSocket_UDPSocket < Test::Unit::TestCase
  def test_open
    assert_nothing_raised { UDPSocket.open {} }
    assert_nothing_raised { UDPSocket.open(Socket::AF_INET) {} }
    assert_nothing_raised { UDPSocket.open("AF_INET") {} }
    assert_nothing_raised { UDPSocket.open(:AF_INET) {} }
  end

  def test_connect
    s = UDPSocket.new
    host = Object.new
    class << host; self end.send(:define_method, :to_str) {
      s.close
      "127.0.0.1"
    }
    assert_raise(IOError, "[ruby-dev:25045]") {
      s.connect(host, 1)
    }
  end

  def test_bind
    s = UDPSocket.new
    host = Object.new
    class << host; self end.send(:define_method, :to_str) {
      s.close
      "127.0.0.1"
    }
    assert_raise(IOError, "[ruby-dev:25057]") {
      s.bind(host, 2000)
    }
  ensure
    s.close if s && !s.closed?
  end

  def test_bind_addrinuse
    host = "127.0.0.1"

    in_use = UDPSocket.new
    in_use.bind(host, 0)
    port = in_use.addr[1]

    s = UDPSocket.new

    e = assert_raises(Errno::EADDRINUSE) do
      s.bind(host, port)
    end

    assert_match "bind(2) for \"#{host}\" port #{port}", e.message
  ensure
    in_use.close if in_use
    s.close if s
  end

  def test_send_too_long
    u = UDPSocket.new

    e = assert_raises Errno::EMSGSIZE do
      u.send "\0" * 100_000, 0, "127.0.0.1", 7 # echo
    end

    assert_match 'for "127.0.0.1" port 7', e.message
  ensure
    u.close if u
  end
end if defined?(UDPSocket)
