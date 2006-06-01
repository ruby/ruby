begin
  require "socket"
rescue LoadError
end

require "test/unit"
require "tempfile"

class TestNonblockSocket < Test::Unit::TestCase
  def test_accept_nonblock
    serv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen(5)
    assert_raise(Errno::EAGAIN) { serv.accept_nonblock }
    c = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    c.connect(serv.getsockname)
    s, sockaddr = serv.accept_nonblock
    assert_equal(c.getsockname, sockaddr)
  ensure
    serv.close if serv
    c.close if c
    s.close if s
  end

  def test_connect_nonblock
    serv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen(5)
    c = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    servaddr = serv.getsockname
    begin
      c.connect_nonblock(servaddr)
    rescue Errno::EINPROGRESS
      IO.select nil, [c]
      assert_nothing_raised {
        begin
          c.connect_nonblock(servaddr)
        rescue Errno::EISCONN
        end
      }
    end
    s, sockaddr = serv.accept
    assert_equal(c.getsockname, sockaddr)
  ensure
    serv.close if serv
    c.close if c
    s.close if s
  end

  def test_udp_recvfrom_nonblock
    u1 = UDPSocket.new
    u2 = UDPSocket.new
    u1.bind("127.0.0.1", 0)
    assert_raise(Errno::EAGAIN) { u1.recvfrom_nonblock(100) }
    assert_raise(Errno::EAGAIN) { u2.recvfrom_nonblock(100) }
    u2.send("aaa", 0, u1.getsockname)
    IO.select [u1]
    mesg, inet_addr = u1.recvfrom_nonblock(100)
    assert_equal(4, inet_addr.length)
    assert_equal("aaa", mesg)
    af, port, host, addr = inet_addr
    u2_port, u2_addr = Socket.unpack_sockaddr_in(u2.getsockname)
    assert_equal(u2_port, port)
    assert_raise(Errno::EAGAIN) { u1.recvfrom_nonblock(100) }
    u2.send("", 0, u1.getsockname)
    IO.select [u1]
    mesg, inet_addr = u1.recvfrom_nonblock(100)
    assert_equal("", mesg)
  ensure
    u1.close if u1
    u2.close if u2
  end

  def bound_unix_socket(klass)
    tmpfile = Tempfile.new("testrubysock")
    path = tmpfile.path
    tmpfile.close(true)
    return klass.new(path), path
  end

  def test_unix_recvfrom_nonblock
    serv, serv_path = bound_unix_socket(UNIXServer)
    c = UNIXSocket.new(serv_path)
    s = serv.accept
    assert_raise(Errno::EAGAIN) { s.recvfrom_nonblock(100) }
    assert_raise(Errno::EAGAIN) { c.recvfrom_nonblock(100) }
    s.write "aaa"
    IO.select [c]
    mesg, unix_addr = c.recvfrom_nonblock(100)
    assert_equal("aaa", mesg)
    if unix_addr != nil # connection-oriented socket may not return the peer address.
      assert_equal(2, unix_addr.length)
      af, path = unix_addr
      assert_equal(serv_path, path)
    end
    s.close
    IO.select [c]
    mesg, unix_addr = c.recvfrom_nonblock(100)
    assert_equal("", mesg)
  ensure
    File.unlink serv_path if serv_path && File.socket?(serv_path)
    serv.close if serv
    c.close if c
    s.close if s && !s.closed?
  end

  def test_socket_recvfrom_nonblock
    s1 = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s2 = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
    assert_raise(Errno::EAGAIN) { s1.recvfrom_nonblock(100) }
    assert_raise(Errno::EAGAIN) { s2.recvfrom_nonblock(100) }
    s2.send("aaa", 0, s1.getsockname)
    IO.select [s1]
    mesg, sockaddr = s1.recvfrom_nonblock(100) 
    assert_equal("aaa", mesg)
    port, addr = Socket.unpack_sockaddr_in(sockaddr)
    s2_port, s2_addr = Socket.unpack_sockaddr_in(s2.getsockname)
    assert_equal(s2_port, port)
  ensure
    s1.close if s1
    s2.close if s2
  end

  def tcp_pair
    serv = TCPServer.new("127.0.0.1", 0)
    af, port, host, addr = serv.addr
    c = TCPSocket.new(addr, port)
    s = serv.accept
    return c, s
  ensure
    serv.close if serv
  end

  def test_read_nonblock
    c, s = tcp_pair
    assert_raise(Errno::EAGAIN) { c.read_nonblock(100) }
    assert_raise(Errno::EAGAIN) { s.read_nonblock(100) }
    c.write("abc")
    IO.select [s]
    assert_equal("a", s.read_nonblock(1))
    assert_equal("bc", s.read_nonblock(100))
    assert_raise(Errno::EAGAIN) { s.read_nonblock(100) }
  ensure
    c.close if c
    s.close if s
  end

  def test_write_nonblock
    c, s = tcp_pair
    str = "a" * 10000
    _, ws, _ = IO.select(nil, [c], nil)
    assert_equal([c], ws)
    ret = c.write_nonblock(str)
    assert_operator(ret, :>, 0)
    loop {
      assert_raise(Errno::EAGAIN) {
        loop {
          ret = c.write_nonblock(str)
          assert_operator(ret, :>, 0)
        }
      }
      _, ws, _ = IO.select(nil, [c], nil, 0)
      break if !ws
    }
  ensure
    c.close if c
    s.close if s
  end

end if defined?(Socket)
