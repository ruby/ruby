begin
  require "socket"
rescue LoadError
end

require "test/unit"
require "tempfile"

class TestSocketAddrInfo < Test::Unit::TestCase
  def test_addrinfo_ip
    ai = AddrInfo.ip("127.0.0.1")
    assert_equal([0, "127.0.0.1"], Socket.unpack_sockaddr_in(ai))
    assert_equal(Socket::AF_INET, ai.afamily)
    assert_equal(Socket::PF_INET, ai.pfamily)
    assert_equal(0, ai.socktype)
    assert_equal(0, ai.protocol)
  end

  def test_addrinfo_tcp
    ai = AddrInfo.tcp("127.0.0.1", 80)
    assert_equal([80, "127.0.0.1"], Socket.unpack_sockaddr_in(ai))
    assert_equal(Socket::AF_INET, ai.afamily)
    assert_equal(Socket::PF_INET, ai.pfamily)
    assert_equal(Socket::SOCK_STREAM, ai.socktype)
    assert_includes([0, Socket::IPPROTO_TCP], ai.protocol)
  end

  def test_addrinfo_udp
    ai = AddrInfo.udp("127.0.0.1", 80)
    assert_equal([80, "127.0.0.1"], Socket.unpack_sockaddr_in(ai))
    assert_equal(Socket::AF_INET, ai.afamily)
    assert_equal(Socket::PF_INET, ai.pfamily)
    assert_equal(Socket::SOCK_DGRAM, ai.socktype)
    assert_includes([0, Socket::IPPROTO_UDP], ai.protocol)
  end

  def test_addrinfo_ip_unpack
    ai = AddrInfo.tcp("127.0.0.1", 80)
    assert_equal(["127.0.0.1", 80], ai.ip_unpack)
  end

  def test_addrinfo_new_inet
    ai = AddrInfo.new(["AF_INET", 46102, "localhost.localdomain", "127.0.0.2"])
    assert_equal([46102, "127.0.0.2"], Socket.unpack_sockaddr_in(ai))
    assert_equal(Socket::AF_INET, ai.afamily)
    assert_equal(Socket::PF_INET, ai.pfamily)
    assert_equal(0, ai.socktype)
    assert_equal(0, ai.protocol)
  end

  def test_addrinfo_predicates
    ipv4_ai = AddrInfo.new(Socket.sockaddr_in(80, "192.168.0.1"))
    assert(ipv4_ai.ip?)
    assert(ipv4_ai.ipv4?)
    assert(!ipv4_ai.ipv6?)
    assert(!ipv4_ai.unix?)
  end

  def test_basicsocket_send
    s1 = Socket.new(:INET, :DGRAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    sa = s1.getsockname
    ai = AddrInfo.new(sa)
    s2 = Socket.new(:INET, :DGRAM, 0)
    s2.send("test-basicsocket-send", 0, ai)
    assert_equal("test-basicsocket-send", s1.recv(100))
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
  end

  def test_udpsocket_send
    s1 = UDPSocket.new
    s1.bind("127.0.0.1", 0)
    ai = AddrInfo.new(s1.getsockname)
    s2 = UDPSocket.new
    s2.send("test-udp-send", 0, ai)
    assert_equal("test-udp-send", s1.recv(100))
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
  end

  def test_socket_bind
    s1 = Socket.new(:INET, :DGRAM, 0)
    sa = Socket.sockaddr_in(0, "127.0.0.1")
    ai = AddrInfo.new(sa)
    s1.bind(ai)
    s2 = UDPSocket.new
    s2.send("test-socket-bind", 0, s1.getsockname)
    assert_equal("test-socket-bind", s1.recv(100))
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
  end

  def test_socket_connect
    s1 = Socket.new(:INET, :STREAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s1.listen(5)
    ai = AddrInfo.new(s1.getsockname)
    s2 = Socket.new(:INET, :STREAM, 0)
    s2.connect(ai)
    s3, sender_addr = s1.accept
    s2.send("test-socket-connect", 0)
    assert_equal("test-socket-connect", s3.recv(100))
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
    s3.close if s3 && !s3.closed?
  end

  def test_socket_connect_nonblock
    s1 = Socket.new(:INET, :STREAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s1.listen(5)
    ai = AddrInfo.new(s1.getsockname)
    s2 = Socket.new(:INET, :STREAM, 0)
    begin
      s2.connect_nonblock(ai)
    rescue Errno::EINPROGRESS
      IO.select(nil, [s2])
      begin
        s2.connect_nonblock(ai)
      rescue Errno::EISCONN
      end
    end
    s3, sender_addr = s1.accept
    s2.send("test-socket-connect-nonblock", 0)
    assert_equal("test-socket-connect-nonblock", s3.recv(100))
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
    s3.close if s3 && !s3.closed?
  end

  def test_socket_getnameinfo
     ai = AddrInfo.udp("127.0.0.1", 8888)
     assert_equal(["127.0.0.1", "8888"], Socket.getnameinfo(ai, Socket::NI_NUMERICHOST|Socket::NI_NUMERICSERV))
  end

  def test_basicsocket_local_address
    s1 = Socket.new(:INET, :DGRAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    e = Socket.unpack_sockaddr_in(s1.getsockname)
    a = Socket.unpack_sockaddr_in(s1.local_address.to_sockaddr)
    assert_equal(e, a)
    assert_equal(Socket::AF_INET, s1.local_address.afamily)
    assert_equal(Socket::PF_INET, s1.local_address.pfamily)
    assert_equal(Socket::SOCK_DGRAM, s1.local_address.socktype)
  ensure
    s1.close if s1 && !s1.closed?
  end

  def test_basicsocket_remote_address
    s1 = TCPServer.new("127.0.0.1", 0)
    s2 = Socket.new(:INET, :STREAM, 0)
    s2.connect(s1.getsockname)
    s3, _ = s1.accept
    e = Socket.unpack_sockaddr_in(s2.getsockname)
    a = Socket.unpack_sockaddr_in(s3.remote_address.to_sockaddr)
    assert_equal(e, a)
    assert_equal(Socket::AF_INET, s3.remote_address.afamily)
    assert_equal(Socket::PF_INET, s3.remote_address.pfamily)
    assert_equal(Socket::SOCK_STREAM, s3.remote_address.socktype)
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
    s3.close if s3 && !s3.closed?
  end

  def test_socket_accept
    serv = Socket.new(:INET, :STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen(5)
    c = Socket.new(:INET, :STREAM, 0)
    c.connect(serv.local_address)
    ret = serv.accept
    s, ai = ret
    assert_kind_of(Array, ret)
    assert_equal(2, ret.length)
    assert_kind_of(AddrInfo, ai)
    e = Socket.unpack_sockaddr_in(c.getsockname)
    a = Socket.unpack_sockaddr_in(ai.to_sockaddr)
    assert_equal(e, a)
  ensure
    serv.close if serv && !serv.closed?
    s.close if s && !s.closed?
    c.close if c && !c.closed?
  end

  def test_socket_accept_nonblock
    serv = Socket.new(:INET, :STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen(5)
    c = Socket.new(:INET, :STREAM, 0)
    c.connect(serv.local_address)
    begin
      ret = serv.accept_nonblock
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
      IO.select([serv])
      retry
    end
    s, ai = ret
    assert_kind_of(Array, ret)
    assert_equal(2, ret.length)
    assert_kind_of(AddrInfo, ai)
    e = Socket.unpack_sockaddr_in(c.getsockname)
    a = Socket.unpack_sockaddr_in(ai.to_sockaddr)
    assert_equal(e, a)
  ensure
    serv.close if serv && !serv.closed?
    s.close if s && !s.closed?
    c.close if c && !c.closed?
  end

  def test_socket_sysaccept
    serv = Socket.new(:INET, :STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen(5)
    c = Socket.new(:INET, :STREAM, 0)
    c.connect(serv.local_address)
    ret = serv.sysaccept
    fd, ai = ret
    s = IO.new(fd)
    assert_kind_of(Array, ret)
    assert_equal(2, ret.length)
    assert_kind_of(AddrInfo, ai)
    e = Socket.unpack_sockaddr_in(c.getsockname)
    a = Socket.unpack_sockaddr_in(ai.to_sockaddr)
    assert_equal(e, a)
  ensure
    serv.close if serv && !serv.closed?
    s.close if s && !s.closed?
    c.close if c && !c.closed?
  end

  def test_socket_recvfrom
    s1 = Socket.new(:INET, :DGRAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s2 = Socket.new(:INET, :DGRAM, 0)
    s2.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s2.send("test-socket-recvfrom", 0, s1.getsockname)
    data, ai = s1.recvfrom(100)
    assert_equal("test-socket-recvfrom", data)
    assert_kind_of(AddrInfo, ai)
    e = Socket.unpack_sockaddr_in(s2.getsockname)
    a = Socket.unpack_sockaddr_in(ai.to_sockaddr)
    assert_equal(e, a)
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
  end

  def test_socket_recvfrom_nonblock
    s1 = Socket.new(:INET, :DGRAM, 0)
    s1.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s2 = Socket.new(:INET, :DGRAM, 0)
    s2.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    s2.send("test-socket-recvfrom", 0, s1.getsockname)
    begin
      data, ai = s1.recvfrom_nonblock(100)
    rescue Errno::EWOULDBLOCK
      IO.select([s1])
      retry
    end
    assert_equal("test-socket-recvfrom", data)
    assert_kind_of(AddrInfo, ai)
    e = Socket.unpack_sockaddr_in(s2.getsockname)
    a = Socket.unpack_sockaddr_in(ai.to_sockaddr)
    assert_equal(e, a)
  ensure
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
  end

  if Socket.const_defined?("AF_INET6")

    def test_addrinfo_new_inet6
      ai = AddrInfo.new(["AF_INET6", 42304, "ip6-localhost", "::1"])
      assert_equal([42304, "::1"], Socket.unpack_sockaddr_in(ai))
      assert_equal(Socket::AF_INET6, ai.afamily)
      assert_equal(Socket::PF_INET6, ai.pfamily)
      assert_equal(0, ai.socktype)
      assert_equal(0, ai.protocol)
    end

    def test_addrinfo_ip_unpack_inet6
      ai = AddrInfo.tcp("::1", 80)
      assert_equal(["::1", 80], ai.ip_unpack)
    end

  end

  if defined?(UNIXSocket) && /cygwin/ !~ RUBY_PLATFORM

    def test_addrinfo_unix
      ai = AddrInfo.unix("/tmp/sock")
      assert_equal("/tmp/sock", Socket.unpack_sockaddr_un(ai))
      assert_equal(Socket::AF_UNIX, ai.afamily)
      assert_equal(Socket::PF_UNIX, ai.pfamily)
      assert_equal(Socket::SOCK_STREAM, ai.socktype)
      assert_equal(0, ai.protocol)
    end

    def test_addrinfo_unix_path
      ai = AddrInfo.unix("/tmp/sock1")
      assert_equal("/tmp/sock1", ai.unix_path)
    end

    def test_addrinfo_new_unix
      ai = AddrInfo.new(["AF_UNIX", "/tmp/sock"])
      assert_equal("/tmp/sock", Socket.unpack_sockaddr_un(ai))
      assert_equal(Socket::AF_UNIX, ai.afamily)
      assert_equal(Socket::PF_UNIX, ai.pfamily)
      assert_equal(Socket::SOCK_STREAM, ai.socktype) # UNIXSocket/UNIXServer is SOCK_STREAM only.
      assert_equal(0, ai.protocol)
    end

    def test_addrinfo_predicates_unix
      unix_ai = AddrInfo.new(Socket.sockaddr_un("/tmp/sososo"))
      assert(!unix_ai.ip?)
      assert(!unix_ai.ipv4?)
      assert(!unix_ai.ipv6?)
      assert(unix_ai.unix?)
    end

  end
end
