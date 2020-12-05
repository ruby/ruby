# frozen_string_literal: true

begin
  require "socket"
  require "tmpdir"
  require "fcntl"
  require "etc"
  require "test/unit"
rescue LoadError
end

class TestSocket < Test::Unit::TestCase
  def test_socket_new
    begin
      s = Socket.new(:INET, :STREAM)
      assert_kind_of(Socket, s)
    ensure
      s.close
    end
  end

  def test_socket_new_cloexec
    return unless defined? Fcntl::FD_CLOEXEC
    begin
      s = Socket.new(:INET, :STREAM)
      assert(s.close_on_exec?)
    ensure
      s.close
    end
  end

  def test_unpack_sockaddr
    sockaddr_in = Socket.sockaddr_in(80, "")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un(sockaddr_in) }
    sockaddr_un = Socket.sockaddr_un("/testdir/s")
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in(sockaddr_un) }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_in("") }
    assert_raise(ArgumentError) { Socket.unpack_sockaddr_un("") }
  end if Socket.respond_to?(:sockaddr_un)

  def test_sysaccept
    serv = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    serv.bind(Socket.sockaddr_in(0, "127.0.0.1"))
    serv.listen 5
    c = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    c.connect(serv.getsockname)
    fd, peeraddr = serv.sysaccept
    assert_equal(c.getsockname, peeraddr.to_sockaddr)
  ensure
    serv.close if serv
    c.close if c
    IO.for_fd(fd).close if fd
  end

  def test_initialize
    Socket.open(Socket::AF_INET, Socket::SOCK_STREAM, 0) {|s|
      s.bind(Socket.sockaddr_in(0, "127.0.0.1"))
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError, NoMethodError) { Socket.unpack_sockaddr_un(addr) }
    }
    Socket.open("AF_INET", "SOCK_STREAM", 0) {|s|
      s.bind(Socket.sockaddr_in(0, "127.0.0.1"))
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError, NoMethodError) { Socket.unpack_sockaddr_un(addr) }
    }
    Socket.open(:AF_INET, :SOCK_STREAM, 0) {|s|
      s.bind(Socket.sockaddr_in(0, "127.0.0.1"))
      addr = s.getsockname
      assert_nothing_raised { Socket.unpack_sockaddr_in(addr) }
      assert_raise(ArgumentError, NoMethodError) { Socket.unpack_sockaddr_un(addr) }
    }
  end

  def test_bind
    Socket.open(Socket::AF_INET, Socket::SOCK_STREAM, 0) {|bound|
      bound.bind(Socket.sockaddr_in(0, "127.0.0.1"))
      addr = bound.getsockname
      port, = Socket.unpack_sockaddr_in(addr)

      Socket.open(Socket::AF_INET, Socket::SOCK_STREAM, 0) {|s|
        e = assert_raise(Errno::EADDRINUSE) do
          s.bind(Socket.sockaddr_in(port, "127.0.0.1"))
        end

        assert_match "bind(2) for 127.0.0.1:#{port}", e.message
      }
    }
  end

  def test_getaddrinfo
    # This should not send a DNS query because AF_UNIX.
    assert_raise(SocketError) { Socket.getaddrinfo("www.kame.net", 80, "AF_UNIX") }
  end

  def test_getaddrinfo_raises_no_errors_on_port_argument_of_0 # [ruby-core:29427]
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', 0, Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', '0', Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ Socket.getaddrinfo('localhost', '00', Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_raise(SocketError, '[ruby-core:29427]'){ Socket.getaddrinfo(nil, nil, Socket::AF_INET, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME) }
    assert_nothing_raised('[ruby-core:29427]'){ TCPServer.open('localhost', 0) {} }
  end

  def test_getaddrinfo_after_fork
    skip "fork not supported" unless Process.respond_to?(:fork)
    assert_normal_exit(<<-"end;", '[ruby-core:100329] [Bug #17220]')
      require "socket"
      Socket.getaddrinfo("localhost", nil)
      pid = fork { Socket.getaddrinfo("localhost", nil) }
      assert_equal pid, Timeout.timeout(3) { Process.wait(pid) }
    end;
  end


  def test_getnameinfo
    assert_raise(SocketError) { Socket.getnameinfo(["AF_UNIX", 80, "0.0.0.0"]) }
    assert_raise(ArgumentError) {Socket.getnameinfo(["AF_INET", "http\0", "example.net"])}
    assert_raise(ArgumentError) {Socket.getnameinfo(["AF_INET", "http", "example.net\0"])}
  end

  def test_ip_address_list
    begin
      list = Socket.ip_address_list
    rescue NotImplementedError
      return
    end
    list.each {|ai|
      assert_instance_of(Addrinfo, ai)
      assert(ai.ip?)
    }
  end

  def test_ip_address_list_include_localhost
    begin
      list = Socket.ip_address_list
    rescue NotImplementedError
      return
    end
    assert_includes list.map(&:ip_address), Addrinfo.tcp("localhost", 0).ip_address
  end

  def test_tcp
    TCPServer.open(0) {|serv|
      addr = serv.connect_address
      addr.connect {|s1|
        s2 = serv.accept
        begin
          assert_equal(s2.remote_address.ip_unpack, s1.local_address.ip_unpack)
        ensure
          s2.close
        end
      }
    }
  end

  def test_tcp_cloexec
    return unless defined? Fcntl::FD_CLOEXEC
    TCPServer.open(0) {|serv|
      addr = serv.connect_address
      addr.connect {|s1|
        s2 = serv.accept
        begin
          assert(s2.close_on_exec?)
        ensure
          s2.close
        end
      }

    }
  end

  def random_port
    # IANA suggests dynamic port for 49152 to 65535
    # http://www.iana.org/assignments/port-numbers
    49152 + rand(65535-49152+1)
  end

  def errors_addrinuse
    [Errno::EADDRINUSE]
  end

  def test_tcp_server_sockets
    port = random_port
    begin
      sockets = Socket.tcp_server_sockets(port)
    rescue *errors_addrinuse
      return # not test failure
    end
    begin
      sockets.each {|s|
        assert_equal(port, s.local_address.ip_port)
      }
    ensure
      sockets.each {|s|
        s.close
      }
    end
  end

  def test_tcp_server_sockets_port0
    sockets = Socket.tcp_server_sockets(0)
    ports = sockets.map {|s| s.local_address.ip_port }
    the_port = ports.first
    ports.each {|port|
      assert_equal(the_port, port)
    }
  ensure
    if sockets
      sockets.each {|s|
        s.close
      }
    end
  end

  if defined? UNIXSocket
    def test_unix
      Dir.mktmpdir {|tmpdir|
        path = "#{tmpdir}/sock"
        UNIXServer.open(path) {|serv|
          Socket.unix(path) {|s1|
            s2 = serv.accept
            begin
              s2raddr = s2.remote_address
              s1laddr = s1.local_address
              assert(s2raddr.to_sockaddr.empty? ||
                     s1laddr.to_sockaddr.empty? ||
                     s2raddr.unix_path == s1laddr.unix_path)
              assert(s2.close_on_exec?)
            ensure
              s2.close
            end
          }
        }
      }
    end

    def test_unix_server_socket
      Dir.mktmpdir {|tmpdir|
        path = "#{tmpdir}/sock"
        2.times {
          serv = Socket.unix_server_socket(path)
          begin
            assert_kind_of(Socket, serv)
            assert(File.socket?(path))
            assert_equal(path, serv.local_address.unix_path)
          ensure
            serv.close
          end
        }
      }
    end

    def test_accept_loop_with_unix
      Dir.mktmpdir {|tmpdir|
        tcp_servers = []
        clients = []
        accepted = []
        begin
          tcp_servers = Socket.tcp_server_sockets(0)
          unix_server = Socket.unix_server_socket("#{tmpdir}/sock")
          tcp_servers.each {|s|
            addr = s.connect_address
            begin
              clients << addr.connect
            rescue
              # allow failure if the address is IPv6
              raise unless addr.ipv6?
            end
          }
          addr = unix_server.connect_address
          assert_nothing_raised("connect to #{addr.inspect}") {
            clients << addr.connect
          }
          Socket.accept_loop(tcp_servers, unix_server) {|s|
            accepted << s
            break if clients.length == accepted.length
          }
          assert_equal(clients.length, accepted.length)
        ensure
          tcp_servers.each {|s| s.close if !s.closed?  }
          unix_server.close if unix_server && !unix_server.closed?
          clients.each {|s| s.close if !s.closed?  }
          accepted.each {|s| s.close if !s.closed?  }
        end
      }
    end
  end

  def test_accept_loop
    servers = []
    begin
      servers = Socket.tcp_server_sockets(0)
      port = servers[0].local_address.ip_port
      Socket.tcp("localhost", port) {|s1|
        Socket.accept_loop(servers) {|s2, client_ai|
          begin
            assert_equal(s1.local_address.ip_unpack, client_ai.ip_unpack)
          ensure
            s2.close
          end
          break
        }
      }
    ensure
      servers.each {|s| s.close if !s.closed?  }
    end
  end

  def test_accept_loop_multi_port
    servers = []
    begin
      servers = Socket.tcp_server_sockets(0)
      port = servers[0].local_address.ip_port
      servers2 = Socket.tcp_server_sockets(0)
      servers.concat servers2
      port2 = servers2[0].local_address.ip_port

      Socket.tcp("localhost", port) {|s1|
        Socket.accept_loop(servers) {|s2, client_ai|
          begin
            assert_equal(s1.local_address.ip_unpack, client_ai.ip_unpack)
          ensure
            s2.close
          end
          break
        }
      }
      Socket.tcp("localhost", port2) {|s1|
        Socket.accept_loop(servers) {|s2, client_ai|
          begin
            assert_equal(s1.local_address.ip_unpack, client_ai.ip_unpack)
          ensure
            s2.close
          end
          break
        }
      }
    ensure
      servers.each {|s| s.close if !s.closed?  }
    end
  end

  def test_udp_server
    begin
      ifaddrs = Socket.getifaddrs
    rescue NotImplementedError
      skip "Socket.getifaddrs not implemented"
    end

    ifconfig = nil
    Socket.udp_server_sockets(0) {|sockets|
      famlies = {}
      sockets.each {|s| famlies[s.local_address.afamily] = s }
      nd6 = {}
      ifaddrs.reject! {|ifa|
        ai = ifa.addr
        next true unless ai
        s = famlies[ai.afamily]
        next true unless s
        next true if ai.ipv6_linklocal? # IPv6 link-local address is too troublesome in this test.
        case RUBY_PLATFORM
        when /linux/
          if ai.ip_address.include?('%') and
            (Etc.uname[:release][/[0-9.]+/].split('.').map(&:to_i) <=> [2,6,18]) <= 0
            # Cent OS 5.6 (2.6.18-238.19.1.el5xen) doesn't correctly work
            # sendmsg with pktinfo for link-local ipv6 addresses
            next true
          end
        when /freebsd/
          if ifa.addr.ipv6_linklocal?
            # FreeBSD 9.0 with default setting (ipv6_activate_all_interfaces
            # is not YES) sets IFDISABLED to interfaces which don't have
            # global IPv6 address.
            # Link-local IPv6 addresses on those interfaces don't work.
            ulSIOCGIFINFO_IN6 = 3225971052
            ulND6_IFF_IFDISABLED = 8
            in6_ondireq = ifa.name
            s.ioctl(ulSIOCGIFINFO_IN6, in6_ondireq)
            flag = in6_ondireq.unpack('A16L6').last
            next true if flag & ulND6_IFF_IFDISABLED != 0
            nd6[ai] = flag
          end
        when /darwin/
          if !ai.ipv6?
          elsif ai.ipv6_unique_local? && /darwin1[01]\./ =~ RUBY_PLATFORM
            next true # iCloud addresses do not work, see Bug #6692
          elsif ifr_name = ai.ip_address[/%(.*)/, 1]
            # Mac OS X may sets IFDISABLED as FreeBSD does
            ulSIOCGIFFLAGS = 3223349521
            ulSIOCGIFINFO_IN6 = 3224398156
            ulIFF_POINTOPOINT = 0x10
            ulND6_IFF_IFDISABLED = 8
            in6_ondireq = ifr_name
            s.ioctl(ulSIOCGIFINFO_IN6, in6_ondireq)
            flag = in6_ondireq.unpack('A16L6').last
            next true if (flag & ulND6_IFF_IFDISABLED) != 0
            nd6[ai] = flag
            in6_ifreq = [ifr_name,ai.to_sockaddr].pack('a16A*')
            s.ioctl(ulSIOCGIFFLAGS, in6_ifreq)
            next true if in6_ifreq.unpack('A16L1').last & ulIFF_POINTOPOINT != 0
          end
          ifconfig ||= `/sbin/ifconfig`
          next true if ifconfig.scan(/^(\w+):(.*(?:\n\t.*)*)/).find do |_ifname, value|
            value.include?(ai.ip_address) && value.include?('POINTOPOINT')
          end
        end
        false
      }
      skipped = false
      begin
        port = sockets.first.local_address.ip_port

        ping_p = false
        th = Thread.new {
          Socket.udp_server_loop_on(sockets) {|msg, msg_src|
            break if msg == "exit"
            rmsg = Marshal.dump([msg, msg_src.remote_address, msg_src.local_address])
            ping_p = true
            msg_src.reply rmsg
          }
        }

        ifaddrs.each {|ifa|
          ai = ifa.addr
          Addrinfo.udp(ai.ip_address, port).connect {|s|
            ping_p = false
            msg1 = "<<<#{ai.inspect}>>>"
            s.sendmsg msg1
            unless IO.select([s], nil, nil, 10)
              nd6options = nd6.key?(ai) ? "nd6=%x " % nd6[ai] : ''
              raise "no response from #{ifa.inspect} #{nd6options}ping=#{ping_p}"
            end
            msg2, addr = s.recvmsg
            msg2, _, _ = Marshal.load(msg2)
            assert_equal(msg1, msg2)
            assert_equal(ai.ip_address, addr.ip_address)
          }
        }
      rescue NotImplementedError, Errno::ENOSYS
        skipped = true
        skip "need sendmsg and recvmsg: #{$!}"
      ensure
        if th
          if skipped
            Thread.kill th unless th.join(10)
          else
            Addrinfo.udp("127.0.0.1", port).connect {|s| s.sendmsg "exit" }
            unless th.join(10)
              Thread.kill th
              th.join(10)
              raise "thread killed"
            end
          end
        end
      end
    }
  end

  def test_linger
    opt = Socket::Option.linger(true, 0)
    assert_equal([true, 0], opt.linger)
    Addrinfo.tcp("127.0.0.1", 0).listen {|serv|
      serv.local_address.connect {|s1|
        s2, _ = serv.accept
        begin
          s1.setsockopt(opt)
          s1.close
          assert_raise(Errno::ECONNRESET) { s2.read }
        ensure
          s2.close
        end
      }
    }
  end

  def timestamp_retry_rw(s1, s2, t1, type)
    IO.pipe do |r,w|
      # UDP may not be reliable, keep sending until recvmsg returns:
      th = Thread.new do
        n = 0
        begin
          s2.send("a", 0, s1.local_address)
          n += 1
        end while IO.select([r], nil, nil, 0.1).nil?
        n
      end
      timeout = (defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? ? 120 : 30) # for --jit-wait
      assert_equal([[s1],[],[]], IO.select([s1], nil, nil, timeout))
      msg, _, _, stamp = s1.recvmsg
      assert_equal("a", msg)
      assert(stamp.cmsg_is?(:SOCKET, type))
      w.close # stop th
      n = th.value
      n > 1 and
        warn "UDP packet loss for #{type} over loopback, #{n} tries needed"
      t2 = Time.now.strftime("%Y-%m-%d")
      pat = Regexp.union([t1, t2].uniq)
      assert_match(pat, stamp.inspect)
      t = stamp.timestamp
      assert_match(pat, t.strftime("%Y-%m-%d"))
      stamp
    end
  end

  def test_timestamp
    return if /linux|freebsd|netbsd|openbsd|solaris|darwin/ !~ RUBY_PLATFORM
    return if !defined?(Socket::AncillaryData) || !defined?(Socket::SO_TIMESTAMP)
    t1 = Time.now.strftime("%Y-%m-%d")
    stamp = nil
    Addrinfo.udp("127.0.0.1", 0).bind {|s1|
      Addrinfo.udp("127.0.0.1", 0).bind {|s2|
        s1.setsockopt(:SOCKET, :TIMESTAMP, true)
        stamp = timestamp_retry_rw(s1, s2, t1, :TIMESTAMP)
      }
    }
    t = stamp.timestamp
    pat = /\.#{"%06d" % t.usec}/
    assert_match(pat, stamp.inspect)
  end

  def test_timestampns
    return if /linux/ !~ RUBY_PLATFORM || !defined?(Socket::SO_TIMESTAMPNS)
    t1 = Time.now.strftime("%Y-%m-%d")
    stamp = nil
    Addrinfo.udp("127.0.0.1", 0).bind {|s1|
      Addrinfo.udp("127.0.0.1", 0).bind {|s2|
        begin
          s1.setsockopt(:SOCKET, :TIMESTAMPNS, true)
        rescue Errno::ENOPROTOOPT
          # SO_TIMESTAMPNS is available since Linux 2.6.22
          return
        end
        stamp = timestamp_retry_rw(s1, s2, t1, :TIMESTAMPNS)
      }
    }
    t = stamp.timestamp
    pat = /\.#{"%09d" % t.nsec}/
    assert_match(pat, stamp.inspect)
  end

  def test_bintime
    return if /freebsd/ !~ RUBY_PLATFORM
    t1 = Time.now.strftime("%Y-%m-%d")
    stamp = nil
    Addrinfo.udp("127.0.0.1", 0).bind {|s1|
      Addrinfo.udp("127.0.0.1", 0).bind {|s2|
        s1.setsockopt(:SOCKET, :BINTIME, true)
        s2.send "a", 0, s1.local_address
        msg, _, _, stamp = s1.recvmsg
        assert_equal("a", msg)
        assert(stamp.cmsg_is?(:SOCKET, :BINTIME))
      }
    }
    t2 = Time.now.strftime("%Y-%m-%d")
    pat = Regexp.union([t1, t2].uniq)
    assert_match(pat, stamp.inspect)
    t = stamp.timestamp
    assert_match(pat, t.strftime("%Y-%m-%d"))
    assert_equal(stamp.data[-8,8].unpack("Q")[0], t.subsec * 2**64)
  end

  def test_closed_read
    require 'timeout'
    require 'socket'
    bug4390 = '[ruby-core:35203]'
    server = TCPServer.new("localhost", 0)
    serv_thread = Thread.new {server.accept}
    begin sleep(0.1) end until serv_thread.stop?
    sock = TCPSocket.new("localhost", server.addr[1])
    client_thread = Thread.new do
      assert_raise(IOError, bug4390) {
        sock.readline
      }
    end
    begin sleep(0.1) end until client_thread.stop?
    Timeout.timeout(1) do
      sock.close
      sock = nil
      client_thread.join
    end
  ensure
    serv_thread.value.close
    server.close
  end

  def test_connect_timeout
    host = "127.0.0.1"
    server = TCPServer.new(host, 0)
    port = server.addr[1]
    serv_thread = Thread.new {server.accept}
    sock = Socket.tcp(host, port, :connect_timeout => 30)
    accepted = serv_thread.value
    assert_kind_of TCPSocket, accepted
    assert_equal sock, IO.select(nil, [ sock ])[1][0], "not writable"
    sock.close

    # some platforms may not timeout when the listener queue overflows,
    # but we know Linux does with the default listen backlog of SOMAXCONN for
    # TCPServer.
    assert_raise(Errno::ETIMEDOUT) do
      (Socket::SOMAXCONN*2).times do |i|
        sock = Socket.tcp(host, port, :connect_timeout => 0)
        assert_equal sock, IO.select(nil, [ sock ])[1][0],
                     "not writable (#{i})"
        sock.close
      end
    end if RUBY_PLATFORM =~ /linux/
  ensure
    server.close
    accepted.close if accepted
    sock.close if sock && ! sock.closed?
  end

  def test_getifaddrs
    begin
      list = Socket.getifaddrs
    rescue NotImplementedError
      return
    end
    list.each {|ifaddr|
      assert_instance_of(Socket::Ifaddr, ifaddr)
    }
  end

  def test_connect_in_rescue
    serv = Addrinfo.tcp(nil, 0).listen
    addr = serv.connect_address
    begin
      raise "dummy error"
    rescue
      s = addr.connect
      assert(!s.closed?)
    end
  ensure
    serv.close if serv && !serv.closed?
    s.close if s && !s.closed?
  end

  def test_bind_in_rescue
    begin
      raise "dummy error"
    rescue
      s = Addrinfo.tcp(nil, 0).bind
      assert(!s.closed?)
    end
  ensure
    s.close if s && !s.closed?
  end

  def test_listen_in_rescue
    begin
      raise "dummy error"
    rescue
      s = Addrinfo.tcp(nil, 0).listen
      assert(!s.closed?)
    end
  ensure
    s.close if s && !s.closed?
  end

  def test_udp_server_sockets_in_rescue
    begin
      raise "dummy error"
    rescue
      ss = Socket.udp_server_sockets(0)
      ss.each {|s|
        assert(!s.closed?)
      }
    end
  ensure
    if ss
      ss.each {|s|
        s.close if !s.closed?
      }
    end
  end

  def test_tcp_server_sockets_in_rescue
    begin
      raise "dummy error"
    rescue
      ss = Socket.tcp_server_sockets(0)
      ss.each {|s|
        assert(!s.closed?)
      }
    end
  ensure
    if ss
      ss.each {|s|
        s.close if !s.closed?
      }
    end
  end

  def test_recvmsg_udp_no_arg
    n = 4097
    s1 = Addrinfo.udp("127.0.0.1", 0).bind
    s2 = s1.connect_address.connect
    s2.send("a" * n, 0)
    ret = s1.recvmsg
    assert_equal n, ret[0].bytesize, '[ruby-core:71517] [Bug #11701]'

    s2.send("a" * n, 0)
    IO.select([s1])
    ret = s1.recvmsg_nonblock
    assert_equal n, ret[0].bytesize, 'non-blocking should also grow'
  ensure
    s1.close
    s2.close
  end

  def test_udp_read_truncation
    s1 = Addrinfo.udp("127.0.0.1", 0).bind
    s2 = s1.connect_address.connect
    s2.send("a" * 100, 0)
    ret = s1.read(10)
    assert_equal "a" * 10, ret
    s2.send("b" * 100, 0)
    ret = s1.read(10)
    assert_equal "b" * 10, ret
  ensure
    s1.close
    s2.close
  end

  def test_udp_recv_truncation
    s1 = Addrinfo.udp("127.0.0.1", 0).bind
    s2 = s1.connect_address.connect
    s2.send("a" * 100, 0)
    ret = s1.recv(10, Socket::MSG_PEEK)
    assert_equal "a" * 10, ret
    ret = s1.recv(10, 0)
    assert_equal "a" * 10, ret
    s2.send("b" * 100, 0)
    ret = s1.recv(10, 0)
    assert_equal "b" * 10, ret
  ensure
    s1.close
    s2.close
  end

  def test_udp_recvmsg_truncation
    s1 = Addrinfo.udp("127.0.0.1", 0).bind
    s2 = s1.connect_address.connect
    s2.send("a" * 100, 0)
    ret, addr, rflags = s1.recvmsg(10, Socket::MSG_PEEK)
    assert_equal "a" * 10, ret
    # AIX does not set MSG_TRUNC for a message partially read with MSG_PEEK.
    assert_equal Socket::MSG_TRUNC, rflags & Socket::MSG_TRUNC if !rflags.nil? && /aix/ !~ RUBY_PLATFORM
    ret, addr, rflags = s1.recvmsg(10, 0)
    assert_equal "a" * 10, ret
    assert_equal Socket::MSG_TRUNC, rflags & Socket::MSG_TRUNC if !rflags.nil?
    s2.send("b" * 100, 0)
    ret, addr, rflags = s1.recvmsg(10, 0)
    assert_equal "b" * 10, ret
    assert_equal Socket::MSG_TRUNC, rflags & Socket::MSG_TRUNC if !rflags.nil?
    addr
  ensure
    s1.close
    s2.close
  end

end if defined?(Socket)
