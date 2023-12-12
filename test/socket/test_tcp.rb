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
    assert_raise(IO::TimeoutError, Errno::ENETUNREACH) do
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

  def test_ai_addrconfig
    # This test verifies that we pass AI_ADDRCONFIG to the DNS resolver when making
    # an outgoing connection.
    # The verification of this is unfortunately incredibly convoluted. We perform the
    # test by setting up a fake DNS server to receive queries. Then, we construct
    # an environment which has only IPv4 addresses and uses that fake DNS server. We
    # then attempt to make an outgoing TCP connection. Finally, we verify that we
    # only received A and not AAAA queries on our fake resolver.
    # This test can only possibly work on Linux, and only when run as root. If either
    # of these conditions aren't met, the test will be skipped.

    # The construction of our IPv6-free environment must happen in a child process,
    # which we can put in its own network & mount namespaces.

    omit "This test is disabled.  It is retained to show the original intent of [ruby-core:110870]"

    IO.popen("-") do |test_io|
      if test_io.nil?
        begin
          # Child program
          require 'fiddle'
          require 'resolv'
          require 'open3'

          libc = Fiddle.dlopen(nil)
          begin
            unshare = Fiddle::Function.new(libc['unshare'], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          rescue Fiddle::DLError
            # Test can't run because we don't have unshare(2) in libc
            # This will be the case on not-linux, and also on very old glibc versions (or
            # possibly other libc's that don't expose this syscall wrapper)
            $stdout.write(Marshal.dump({result: :skip, reason: "unshare(2) or mount(2) not in libc"}))
            exit
          end

          # Move our test process into a new network & mount namespace.
          # This environment will be configured to be IPv6 free and point DNS resolution
          # at a fake DNS server.
          # (n.b. these flags are CLONE_NEWNS | CLONE_NEWNET)
          ret = unshare.call(0x00020000 | 0x40000000)
          errno = Fiddle.last_error
          if ret == -1 && errno == Errno::EPERM::Errno
            # Test can't run because we're not root.
            $stdout.write(Marshal.dump({result: :skip, reason: "insufficient permissions to unshare namespaces"}))
            exit
          elsif ret == -1 && (errno == Errno::ENOSYS::Errno || errno == Errno::EINVAL::Errno)
            # No unshare(2) in the kernel (or kernel too old to know about this namespace type)
            $stdout.write(Marshal.dump({result: :skip, reason: "errno #{errno} calling unshare(2)"}))
            exit
          elsif ret == -1
            # Unexpected failure
            raise "errno #{errno} calling unshare(2)"
          end

          # Set up our fake DNS environment. Clean out /etc/hosts...
          fake_hosts_file = Tempfile.new('ruby_test_hosts')
          fake_hosts_file.write <<~HOSTS
            127.0.0.1 localhost
            ::1 localhost
          HOSTS
          fake_hosts_file.flush

          # Have /etc/resolv.conf point to 127.0.0.1...
          fake_resolv_conf = Tempfile.new('ruby_test_resolv')
          fake_resolv_conf.write <<~RESOLV
            nameserver 127.0.0.1
          RESOLV
          fake_resolv_conf.flush

          # Also stub out /etc/nsswitch.conf; glibc can have other resolver modules
          # (like systemd-resolved) configured in there other than just using dns,
          # so rewrite it to remove any `hosts:` lines and add one which just uses
          # dns.
          real_nsswitch_conf = File.read('/etc/nsswitch.conf') rescue ""
          fake_nsswitch_conf = Tempfile.new('ruby_test_nsswitch')
          real_nsswitch_conf.lines.reject { _1 =~ /^\s*hosts:/ }.each do |ln|
            fake_nsswitch_conf.puts ln
          end
          fake_nsswitch_conf.puts "hosts: files myhostname dns"
          fake_nsswitch_conf.flush

          # This is needed to make sure our bind-mounds aren't visible outside this process.
          system 'mount', '--make-rprivate', '/', exception: true
          # Bind-mount the fake files over the top of the real files.
          system 'mount', '--bind', '--make-private', fake_hosts_file.path, '/etc/hosts', exception: true
          system 'mount', '--bind', '--make-private', fake_resolv_conf.path, '/etc/resolv.conf', exception: true
          system 'mount', '--bind', '--make-private', fake_nsswitch_conf.path, '/etc/nsswitch.conf', exception: true

          # Create a dummy interface with only an IPv4 address
          system 'ip', 'link', 'add', 'dummy0', 'type', 'dummy', exception: true
          system 'ip', 'addr', 'add', '192.168.1.2/24', 'dev', 'dummy0', exception: true
          system 'ip', 'link', 'set', 'dummy0', 'up', exception: true
          system 'ip', 'link', 'set', 'lo', 'up', exception: true

          # Disable IPv6 on this interface (this is needed to disable the link-local
          # IPv6 address)
          File.open('/proc/sys/net/ipv6/conf/dummy0/disable_ipv6', 'w') do |f|
            f.puts "1"
          end

          # Create a fake DNS server which will receive the DNS queries triggered by TCPSocket.new
          fake_dns_server_socket = UDPSocket.new
          fake_dns_server_socket.bind('127.0.0.1', 53)
          received_dns_queries = []
          fake_dns_server_thread = Thread.new do
            Socket.udp_server_loop_on([fake_dns_server_socket]) do |msg, msg_src|
              request = Resolv::DNS::Message.decode(msg)
              received_dns_queries << request
              response = request.dup.tap do |r|
                r.qr = 0
                r.rcode = 3 # NXDOMAIN
              end
              msg_src.reply response.encode
            end
          end

          # Make a request which will hit our fake DNS swerver - this needs to be in _another_
          # process because glibc will cache resolver info across the fork otherwise.
          load_path_args = $LOAD_PATH.flat_map { ['-I', _1] }
          Open3.capture3('/proc/self/exe', *load_path_args, '-rsocket', '-e', <<~RUBY)
            TCPSocket.open('www.example.com', 4444)
          RUBY

          fake_dns_server_thread.kill
          fake_dns_server_thread.join

          have_aaaa_qs = received_dns_queries.any? do |query|
            query.question.any? do |question|
              question[1] == Resolv::DNS::Resource::IN::AAAA
            end
          end

          have_a_q = received_dns_queries.any? do |query|
            query.question.any? do |question|
              question[0].to_s == "www.example.com"
            end
          end

          if have_aaaa_qs
            $stdout.write(Marshal.dump({result: :fail, reason: "got AAAA queries, expected none"}))
          elsif !have_a_q
            $stdout.write(Marshal.dump({result: :fail, reason: "got no A query for example.com"}))
          else
            $stdout.write(Marshal.dump({result: :success}))
          end
        rescue => ex
          $stdout.write(Marshal.dump({result: :fail, reason: ex.full_message}))
        ensure
          # Make sure the child process does not transfer control back into the test runner.
          exit!
        end
      else
        test_result = Marshal.load(test_io.read)

        case test_result[:result]
        when :skip
          omit test_result[:reason]
        when :fail
          fail test_result[:reason]
        end
      end
    end
  end
end if defined?(TCPSocket)
