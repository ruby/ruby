begin
  require "socket"
  require "test/unit"
rescue LoadError
end

class TestBasicSocket < Test::Unit::TestCase
  def test_setsockopt # [ruby-dev:25039]
    s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    val = Object.new
    class << val; self end.send(:define_method, :to_str) {
      s.close
      "eth0"
    }
    assert_raise(IOError) {
      s.setsockopt(Socket::SOL_SOCKET, Socket::SO_BINDTODEVICE, val)
    }
  end
end if defined?(Socket)
