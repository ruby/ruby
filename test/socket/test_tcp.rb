begin
  require "socket"
  require "test/unit"
rescue LoadError
end


class TestTCPSocket < Test::Unit::TestCase
  def test_recvfrom # [ruby-dev:24705]
    svr = TCPServer.new("localhost", 0)
    Thread.new {
      svr.accept.print("x"*0x1000)
    }
    addr = svr.addr
    sock = TCPSocket.open(addr[2], addr[1])
    Thread.new {
      Thread.pass
      ObjectSpace.each_object(String) {|s|
        s.replace "a" if s.length == 0x10000
      }
    }
    assert_raise(RuntimeError, SocketError) {
      sock.recvfrom(0x10000)
    }
  end
end if defined?(TCPSocket)
