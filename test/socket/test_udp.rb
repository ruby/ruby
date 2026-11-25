# frozen_string_literal: true

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

  def test_inspect
    UDPSocket.open() {|sock|
      assert_match(/AF_INET\b/, sock.inspect)
    }
    if Socket.const_defined?(:AF_INET6)
      begin
        UDPSocket.open(Socket::AF_INET6) {|sock|
          assert_match(/AF_INET6\b/, sock.inspect)
        }
      rescue Errno::EAFNOSUPPORT
        omit 'AF_INET6 not supported by kernel'
      end
    end
  end

  def test_recv_negative_length
    UDPSocket.open do |receiver|
      receiver.bind("127.0.0.1", 0)
      UDPSocket.open do |sender|
        sender.send("A" * 16, 0, "127.0.0.1", receiver.addr[1])
        IO.select([receiver], nil, nil, 10) or flunk "socket did not become readable"
        msg = "negative length -1 given"
        assert_raise_with_message(ArgumentError, msg) { receiver.recvfrom(-1, 0, +"x") }
        assert_raise_with_message(ArgumentError, msg) { receiver.recv(-1, 0, +"x") }
        assert_raise_with_message(ArgumentError, msg) { receiver.recvfrom_nonblock(-1, 0, +"x") }
        assert_raise_with_message(ArgumentError, msg) { receiver.recv_nonblock(-1, 0, +"x") }
        assert_raise_with_message(ArgumentError, msg) { receiver.recvfrom(-1) }
        assert_equal("A" * 16, receiver.recv(16))
      end
    end
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

    e = assert_raise(Errno::EADDRINUSE) do
      s.bind(host, port)
    end

    assert_match "bind(2) for \"#{host}\" port #{port}", e.message
  ensure
    in_use.close if in_use
    s.close if s
  end

  def test_send_too_long
    u = UDPSocket.new

    e = assert_raise(Errno::EMSGSIZE) do
      u.send "\0" * 100_000, 0, "127.0.0.1", 7 # echo
    end

    assert_match 'for "127.0.0.1" port 7', e.message
  ensure
    u.close if u
  end

  def test_bind_no_memory_leak
    assert_no_memory_leak(["-rsocket"], <<-"end;", <<-"end;", rss: true)
      s = UDPSocket.new
      s.close
    end;
      100_000.times {begin s.bind("127.0.0.1", 1) rescue IOError; end}
    end;
  end

  def test_connect_no_memory_leak
    assert_no_memory_leak(["-rsocket"], <<-"end;", <<-"end;", rss: true)
      s = UDPSocket.new
      s.close
    end;
      100_000.times {begin s.connect("127.0.0.1", 1) rescue IOError; end}
    end;
  end

  def test_send_no_memory_leak
    assert_no_memory_leak(["-rsocket"], <<-"end;", <<-"end;", rss: true)
      s = UDPSocket.new
      s.close
    end;
      100_000.times {begin s.send("\0"*100, 0, "127.0.0.1", 1) rescue IOError; end}
    end;
  end
end if defined?(UDPSocket)
