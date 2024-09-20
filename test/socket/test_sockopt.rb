# frozen_string_literal: true

require 'test/unit'
require 'socket'

class TestSocketOption < Test::Unit::TestCase
  def test_new
    data = [1].pack("i")
    sockopt = Socket::Option.new(:INET, :SOCKET, :KEEPALIVE, data)
    assert_equal(Socket::AF_INET, sockopt.family)
    assert_equal(Socket::SOL_SOCKET, sockopt.level)
    assert_equal(Socket::SO_KEEPALIVE, sockopt.optname)
    assert_equal(Socket::SO_KEEPALIVE, sockopt.optname)
    assert_equal(data, sockopt.data)
  end

  def test_bool
    opt = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
    assert_equal(1, opt.int)
    opt = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, false)
    assert_equal(0, opt.int)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 0)
    assert_equal(false, opt.bool)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
    assert_equal(true, opt.bool)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 2)
    assert_equal(true, opt.bool)
    begin
      Socket.open(:INET, :STREAM) {|s|
        s.setsockopt(Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true))
        assert_equal(true, s.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).bool)
        s.setsockopt(Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, false))
        assert_equal(false, s.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).bool)
      }
    rescue TypeError
      if /aix/ =~ RUBY_PLATFORM
        omit "Known bug in getsockopt(2) on AIX"
      end
      raise $!
    end
  end

  def test_ipv4_multicast_loop
    sockopt = Socket::Option.ipv4_multicast_loop(128)
    assert_equal('#<Socket::Option: INET IP MULTICAST_LOOP 128>', sockopt.inspect)
    assert_equal(Socket::AF_INET, sockopt.family)
    assert_equal(Socket::IPPROTO_IP, sockopt.level)
    assert_equal(Socket::IP_MULTICAST_LOOP, sockopt.optname)
    assert_equal(128, sockopt.ipv4_multicast_loop)
  end

  def test_ipv4_multicast_loop_size
    expected_size = Socket.open(:INET, :DGRAM) {|s|
      s.getsockopt(:IP, :MULTICAST_LOOP).to_s.bytesize
    }
    assert_equal(expected_size, Socket::Option.ipv4_multicast_loop(0).to_s.bytesize)
  end

  def test_ipv4_multicast_ttl
    sockopt = Socket::Option.ipv4_multicast_ttl(128)
    assert_equal('#<Socket::Option: INET IP MULTICAST_TTL 128>', sockopt.inspect)
    assert_equal(Socket::AF_INET, sockopt.family)
    assert_equal(Socket::IPPROTO_IP, sockopt.level)
    assert_equal(Socket::IP_MULTICAST_TTL, sockopt.optname)
    assert_equal(128, sockopt.ipv4_multicast_ttl)
  end

  def test_ipv4_multicast_ttl_size
    expected_size = Socket.open(:INET, :DGRAM) {|s|
      s.getsockopt(:IP, :MULTICAST_TTL).to_s.bytesize
    }
    assert_equal(expected_size, Socket::Option.ipv4_multicast_ttl(0).to_s.bytesize)
  end

  def test_unpack
    sockopt = Socket::Option.new(:INET, :SOCKET, :KEEPALIVE, [1].pack("i"))
    assert_equal([1], sockopt.unpack("i"))
    assert_equal([1], sockopt.data.unpack("i"))
  end
end
