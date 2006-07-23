begin
  require "socket"
rescue LoadError
end

require "test/unit"
require "tempfile"

class TestUNIXSocket < Test::Unit::TestCase
  def test_fd_passing
    r1, w = IO.pipe
    s1, s2 = UNIXSocket.pair
    begin
      s1.send_io(nil)
    rescue NotImplementedError
      assert_raise(NotImplementedError) { s2.recv_io }
    rescue TypeError
      s1.send_io(r1)
      r2 = s2.recv_io
      assert_equal(r1.stat.ino, r2.stat.ino)
      assert_not_equal(r1.fileno, r2.fileno)
      w.syswrite "a"
      assert_equal("a", r2.sysread(10))
    ensure
      s1.close
      s2.close
      w.close
      r1.close
      r2.close if r2 && !r2.closed?
    end
  end

  def bound_unix_socket(klass)
    tmpfile = Tempfile.new("testrubysock")
    path = tmpfile.path
    tmpfile.close(true)
    yield klass.new(path), path
  ensure
    File.unlink path if path && File.socket?(path)
  end

  def test_addr
    bound_unix_socket(UNIXServer) {|serv, path|
      c = UNIXSocket.new(path)
      s = serv.accept
      assert_equal(["AF_UNIX", path], c.peeraddr)
      assert_equal(["AF_UNIX", ""], c.addr)
      assert_equal(["AF_UNIX", ""], s.peeraddr)
      assert_equal(["AF_UNIX", path], s.addr)
      assert_equal(path, s.path)
      assert_equal("", c.path)
    }
  end

  def test_noname_path
    s1, s2 = UNIXSocket.pair
    assert_equal("", s1.path)
    assert_equal("", s2.path)
  ensure
    s1.close
    s2.close
  end

  def test_noname_addr
    s1, s2 = UNIXSocket.pair
    assert_equal(["AF_UNIX", ""], s1.addr)
    assert_equal(["AF_UNIX", ""], s2.addr)
  ensure
    s1.close
    s2.close
  end

  def test_noname_peeraddr
    s1, s2 = UNIXSocket.pair
    assert_equal(["AF_UNIX", ""], s1.peeraddr)
    assert_equal(["AF_UNIX", ""], s2.peeraddr)
  ensure
    s1.close
    s2.close
  end

  def test_noname_unpack_sockaddr_un
    s1, s2 = UNIXSocket.pair
    n = nil
    assert_equal("", Socket.unpack_sockaddr_un(n)) if (n = s1.getsockname) != ""
    assert_equal("", Socket.unpack_sockaddr_un(n)) if (n = s1.getsockname) != ""
    assert_equal("", Socket.unpack_sockaddr_un(n)) if (n = s2.getsockname) != ""
    assert_equal("", Socket.unpack_sockaddr_un(n)) if (n = s1.getpeername) != ""
    assert_equal("", Socket.unpack_sockaddr_un(n)) if (n = s2.getpeername) != ""
  ensure
    s1.close
    s2.close
  end

  def test_noname_recvfrom
    s1, s2 = UNIXSocket.pair
    s2.write("a")
    assert_equal(["a", ["AF_UNIX", ""]], s1.recvfrom(10))
  ensure
    s1.close
    s2.close
  end

  def test_noname_recv_nonblock
    s1, s2 = UNIXSocket.pair
    s2.write("a")
    IO.select [s1]
    assert_equal("a", s1.recv_nonblock(10))
  ensure
    s1.close
    s2.close
  end

  def test_too_long_path
    assert_raise(ArgumentError) { Socket.sockaddr_un("a" * 300) }
    assert_raise(ArgumentError) { UNIXServer.new("a" * 300) }
  end

  def test_nul
    assert_raise(ArgumentError) { Socket.sockaddr_un("a\0b") }
    assert_raise(ArgumentError) { UNIXServer.new("a\0b") }
  end

  def test_dgram_pair
    s1, s2 = UNIXSocket.pair(Socket::SOCK_DGRAM)
    assert_raise(Errno::EAGAIN) { s1.recv_nonblock(10) }
    s2.send("", 0)
    s2.send("haha", 0)
    s2.send("", 0)
    s2.send("", 0)
    assert_equal("", s1.recv(10))
    assert_equal("haha", s1.recv(10))
    assert_equal("", s1.recv(10))
    assert_equal("", s1.recv(10))
    assert_raise(Errno::EAGAIN) { s1.recv_nonblock(10) }
  ensure
    s1.close if s1
    s2.close if s2
  end

end if defined?(UNIXSocket) && /cygwin/ !~ RUBY_PLATFORM
