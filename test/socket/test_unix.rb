begin
  require "socket"
  require "test/unit"
rescue LoadError
end

class TestUNIXSocket < Test::Unit::TestCase
  def test_fd_passing
    r1, w = IO.pipe
    s1, s2 = UNIXSocket.pair
    begin
      s1.send_io r1
    rescue NotImplementedError
      s1.close
      assert_raise(NotImplementedError) { s2.recv_io }
      return
    end
    r2 = s2.recv_io
    assert_equal(r1.stat.ino, r2.stat.ino)
    assert_not_equal(r1.fileno, r2.fileno)
  ensure
    s1.close if s1
    s2.close if s2
    r1.close if r1
    r2.close if r2
    w.close if w
  end
end if defined?(UNIXSocket)
