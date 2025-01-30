# frozen_string_literal: true

begin
  require "socket"
  require "test/unit"
rescue LoadError
end


class TestSocket_TCPSocket < Test::Unit::TestCase
  def test_inspect
    TCPServer.open("localhost", 0) {|server|
      assert_match(/AF_INET/, server.inspect)
      TCPSocket.open("localhost", server.addr[1]) {|client|
        assert_match(/AF_INET/, client.inspect)
      }
    }
  end

  def test_initialize_failure
    # These addresses are chosen from TEST-NET-1, TEST-NET-2, and TEST-NET-3.
    # [RFC 5737]
    # They are chosen because probably they are not used as a host address.
    # Anyway the addresses are used for bind() and should be failed.
    # So no packets should be generated.
    test_ip_addresses = [
      '192.0.2.1', '192.0.2.42', # TEST-NET-1
      '198.51.100.1', '198.51.100.42', # TEST-NET-2
      '203.0.113.1', '203.0.113.42', # TEST-NET-3
    ]
    begin
      list = Socket.ip_address_list
    rescue NotImplementedError
      return
    end
    test_ip_addresses -= list.reject {|ai| !ai.ipv4? }.map {|ai| ai.ip_address }
    if test_ip_addresses.empty?
      return
    end
    client_addr = test_ip_addresses.first
    client_port = 8000

    server_addr = '127.0.0.1'
    server_port = 80

    begin
      # Since client_addr is not an IP address of this host,
      # bind() in TCPSocket.new should fail as EADDRNOTAVAIL.
      t = TCPSocket.new(server_addr, server_port, client_addr, client_port)
      flunk "expected SystemCallError"
    rescue SystemCallError => e
      assert_match "for \"#{client_addr}\" port #{client_port}", e.message
    end
  ensure
    t.close if t && !t.closed?
  end

  def test_initialize_resolv_timeout
    TCPServer.open("localhost", 0) do |svr|
      th = Thread.new {
        c = svr.accept
        c.close
      }
      addr = svr.addr
      s = TCPSocket.new(addr[3], addr[1], resolv_timeout: 10)
      th.join
    ensure
      s.close()
    end
  end

  def test_initialize_connect_timeout
    assert_raise(IO::TimeoutError, Errno::ENETUNREACH, Errno::EACCES) do
      TCPSocket.new("192.0.2.1", 80, connect_timeout: 0)
    end
  end

  def test_recvfrom
    TCPServer.open("localhost", 0) {|svr|
      th = Thread.new {
        c = svr.accept
        c.write "foo"
        c.close
      }
      addr = svr.addr
      TCPSocket.open(addr[3], addr[1]) {|sock|
        assert_equal(["foo", nil], sock.recvfrom(0x10000))
      }
      th.join
    }
  end

  def test_encoding
    TCPServer.open("localhost", 0) {|svr|
      th = Thread.new {
        c = svr.accept
        c.write "foo\r\n"
        c.close
      }
      addr = svr.addr
      TCPSocket.open(addr[3], addr[1]) {|sock|
        assert_equal(true, sock.binmode?)
        s = sock.gets
        assert_equal("foo\r\n", s)
        assert_equal(Encoding.find("ASCII-8BIT"), s.encoding)
      }
      th.join
    }
  end

  def test_accept_nonblock
    TCPServer.open("localhost", 0) {|svr|
      assert_raise(IO::WaitReadable) { svr.accept_nonblock }
      assert_equal :wait_readable, svr.accept_nonblock(exception: false)
      assert_raise(IO::WaitReadable) { svr.accept_nonblock(exception: true) }
    }
  end

  def test_accept_multithread
    attempts_count       = 5
    server_threads_count = 3
    client_threads_count = 3

    attempts_count.times do
      server_threads = Array.new(server_threads_count) do
        Thread.new do
          TCPServer.open("localhost", 0) do |server|
            accept_threads = Array.new(client_threads_count) do
              Thread.new { server.accept.close }
            end
            client_threads = Array.new(client_threads_count) do
              Thread.new { TCPSocket.open(server.addr[3], server.addr[1]) {} }
            end
            client_threads.each(&:join)
            accept_threads.each(&:join)
          end
        end
      end

      server_threads.each(&:join)
    end
  end

  def test_initialize_v6_hostname_resolved_earlier
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    begin
      # Verify that "localhost" can be resolved to an IPv6 address
      Socket.getaddrinfo("localhost", 0, Socket::AF_INET6)
      server = TCPServer.new("::1", 0)
    rescue Socket::ResolutionError, Errno::EADDRNOTAVAIL # IPv6 is not supported
      return
    end

    server_thread = Thread.new { server.accept }
    port = server.addr[1]

    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv4: 1000 } }
    )
    assert_true(socket.remote_address.ipv6?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_v4_hostname_resolved_earlier
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]

    server_thread = Thread.new { server.accept }
    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv6: 1000 } }
    )
    assert_true(socket.remote_address.ipv4?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_v6_hostname_resolved_in_resolution_delay
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    begin
      # Verify that "localhost" can be resolved to an IPv6 address
      Socket.getaddrinfo("localhost", 0, Socket::AF_INET6)
      server = TCPServer.new("::1", 0)
    rescue Socket::ResolutionError, Errno::EADDRNOTAVAIL # IPv6 is not supported
      return
    end

    port = server.addr[1]
    delay_time = 25 # Socket::RESOLUTION_DELAY (private) is 50ms

    server_thread = Thread.new { server.accept }
    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv6: delay_time } }
    )
    assert_true(socket.remote_address.ipv6?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_v6_hostname_resolved_earlier_and_v6_server_is_not_listening
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    ipv4_address = "127.0.0.1"
    server = Socket.new(Socket::AF_INET, :STREAM)
    server.bind(Socket.pack_sockaddr_in(0, ipv4_address))
    port = server.connect_address.ip_port

    server_thread = Thread.new { server.listen(1); server.accept }
    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv4: 10 } }
    )
    assert_equal(ipv4_address, socket.remote_address.ip_address)
  ensure
    accepted, _ = server_thread&.value
    accepted&.close
    server&.close
    socket&.close
  end

  def test_initialize_v6_hostname_resolved_later_and_v6_server_is_not_listening
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = Socket.new(Socket::AF_INET, :STREAM)
    server.bind(Socket.pack_sockaddr_in(0, "127.0.0.1"))
    port = server.connect_address.ip_port

    server_thread = Thread.new { server.listen(1); server.accept }
    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv6: 25 } }
    )
    assert_true(socket.remote_address.ipv4?)
  ensure
    accepted, _ = server_thread&.value
    accepted&.close
    server&.close
    socket&.close
  end

  def test_initialize_v6_hostname_resolution_failed_and_v4_hostname_resolution_is_success
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]

    server_thread = Thread.new { server.accept }
    socket = TCPSocket.new(
      "localhost",
      port,
      fast_fallback: true,
      test_mode_settings: { delay: { ipv4: 10 }, error: { ipv6: Socket::EAI_FAIL } }
    )
    assert_true(socket.remote_address.ipv4?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_resolv_timeout_with_connection_failure
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    begin
      server = TCPServer.new("::1", 0)
    rescue Errno::EADDRNOTAVAIL # IPv6 is not supported
      return
    end

    port = server.connect_address.ip_port
    server.close

    assert_raise(Errno::ETIMEDOUT) do
      TCPSocket.new(
        "localhost",
        port,
        resolv_timeout: 0.01,
        fast_fallback: true,
        test_mode_settings: { delay: { ipv4: 1000 } }
      )
    end
  end

  def test_initialize_with_hostname_resolution_failure_after_connection_failure
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    begin
      server = TCPServer.new("::1", 0)
    rescue Errno::EADDRNOTAVAIL # IPv6 is not supported
      return
    end

    port = server.connect_address.ip_port
    server.close

    assert_raise(Errno::ECONNREFUSED) do
      TCPSocket.new(
        "localhost",
        port,
        fast_fallback: true,
        test_mode_settings: { delay: { ipv4: 100 }, error: { ipv4: Socket::EAI_FAIL } }
      )
    end
  end

  def test_initialize_with_connection_failure_after_hostname_resolution_failure
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = TCPServer.new("127.0.0.1", 0)
    port = server.connect_address.ip_port
    server.close

    assert_raise(Errno::ECONNREFUSED) do
      TCPSocket.new(
        "localhost",
        port,
        fast_fallback: true,
        test_mode_settings: { delay: { ipv4: 100 }, error: { ipv6: Socket::EAI_FAIL } }
      )
    end
  end

  def test_initialize_v6_connected_socket_with_v6_address
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    begin
      server = TCPServer.new("::1", 0)
    rescue Errno::EADDRNOTAVAIL # IPv6 is not supported
      return
    end

    server_thread = Thread.new { server.accept }
    port = server.addr[1]

    socket = TCPSocket.new("::1", port)
    assert_true(socket.remote_address.ipv6?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_v4_connected_socket_with_v4_address
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = TCPServer.new("127.0.0.1", 0)
    server_thread = Thread.new { server.accept }
    port = server.addr[1]

    socket = TCPSocket.new("127.0.0.1", port)
    assert_true(socket.remote_address.ipv4?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end

  def test_initialize_fast_fallback_is_false
    return if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    server = TCPServer.new("127.0.0.1", 0)
    _, port, = server.addr
    server_thread = Thread.new { server.accept }

    socket = TCPSocket.new("127.0.0.1", port, fast_fallback: false)
    assert_true(socket.remote_address.ipv4?)
  ensure
    server_thread&.value&.close
    server&.close
    socket&.close
  end
end if defined?(TCPSocket)
