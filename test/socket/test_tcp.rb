begin
  require "socket"
  require "test/unit"
rescue LoadError
end


class TestTCPSocket < Test::Unit::TestCase
  def test_recvfrom
assert false, "TODO: doesn't work on mswin32/64" if /mswin/ =~ RUBY_PLATFORM
    svr = TCPServer.new("localhost", 0)
    th = Thread.new {
      c = svr.accept
      c.write "foo"
      c.close
    }
    addr = svr.addr
    sock = TCPSocket.open(addr[2], addr[1])
    assert_equal(["foo", nil], sock.recvfrom(0x10000))
  ensure
    th.kill
    th.join
  end
end if defined?(TCPSocket)
