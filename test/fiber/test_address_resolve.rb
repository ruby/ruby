# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestAddressResolve < Test::Unit::TestCase
  class NullScheduler < Scheduler
    def address_resolve(*)
    end
  end

  class StubScheduler < Scheduler
    def address_resolve(hostname)
      ["1.2.3.4", "1234::1"]
    end
  end

  def test_addrinfo_getaddrinfo_ipv4_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Addrinfo.getaddrinfo("example.com", 80, :AF_INET, :STREAM)
        assert_equal(1, result.count)

        ai = result.first
        assert_equal("1.2.3.4", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_ipv6_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Addrinfo.getaddrinfo("example.com", 80, :AF_INET6, :STREAM)
        assert_equal(1, result.count)

        ai = result.first
        assert_equal("1234::1", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET6, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_pf_unspec_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        results = Addrinfo.getaddrinfo("example.com", 80, :PF_UNSPEC, :STREAM)
        assert_equal(2, results.count)

        ai_ipv4 = results.first
        assert_equal("1.2.3.4", ai_ipv4.ip_address)
        assert_equal(80, ai_ipv4.ip_port)
        assert_equal(Socket::AF_INET, ai_ipv4.afamily)
        assert_equal(Socket::SOCK_STREAM, ai_ipv4.socktype)

        ai_ipv6 = results.last
        assert_equal("1234::1", ai_ipv6.ip_address)
        assert_equal(80, ai_ipv6.ip_port)
        assert_equal(Socket::AF_INET6, ai_ipv6.afamily)
        assert_equal(Socket::SOCK_STREAM, ai_ipv6.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_full_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        results = Addrinfo.getaddrinfo("example.com", 80)
        assert_equal(6, results.count)

        ai_ipv4_tcp = results[0]
        assert_equal("1.2.3.4", ai_ipv4_tcp.ip_address)
        assert_equal(80, ai_ipv4_tcp.ip_port)
        assert_equal(Socket::AF_INET, ai_ipv4_tcp.afamily)
        assert_equal(Socket::SOCK_STREAM, ai_ipv4_tcp.socktype)

        ai_ipv4_udp = results[1]
        assert_equal("1.2.3.4", ai_ipv4_udp.ip_address)
        assert_equal(80, ai_ipv4_udp.ip_port)
        assert_equal(Socket::AF_INET, ai_ipv4_udp.afamily)
        assert_equal(Socket::SOCK_DGRAM, ai_ipv4_udp.socktype)

        ai_ipv4_sock_raw = results[2]
        assert_equal("1.2.3.4", ai_ipv4_sock_raw.ip_address)
        assert_equal(80, ai_ipv4_sock_raw.ip_port)
        assert_equal(Socket::AF_INET, ai_ipv4_sock_raw.afamily)
        assert_equal(Socket::SOCK_RAW, ai_ipv4_sock_raw.socktype)

        ai_ipv6_tcp = results[3]
        assert_equal("1234::1", ai_ipv6_tcp.ip_address)
        assert_equal(80, ai_ipv6_tcp.ip_port)
        assert_equal(Socket::AF_INET6, ai_ipv6_tcp.afamily)
        assert_equal(Socket::SOCK_STREAM, ai_ipv6_tcp.socktype)

        ai_ipv6_udp = results[4]
        assert_equal("1234::1", ai_ipv6_udp.ip_address)
        assert_equal(80, ai_ipv6_udp.ip_port)
        assert_equal(Socket::AF_INET6, ai_ipv6_udp.afamily)
        assert_equal(Socket::SOCK_DGRAM, ai_ipv6_udp.socktype)

        ai_ipv6_sock_raw = results[5]
        assert_equal("1234::1", ai_ipv6_sock_raw.ip_address)
        assert_equal(80, ai_ipv6_sock_raw.ip_port)
        assert_equal(Socket::AF_INET6, ai_ipv6_sock_raw.afamily)
        assert_equal(Socket::SOCK_RAW, ai_ipv6_sock_raw.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_numeric_non_blocking
    Thread.new do
      scheduler = NullScheduler.new # scheduler hook not invoked
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Addrinfo.getaddrinfo("1.2.3.4", 80, :AF_INET, :STREAM)
        assert_equal(1, result.count)

        ai = result.first
        assert_equal("1.2.3.4", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_any_non_blocking
    Thread.new do
      scheduler = NullScheduler.new # scheduler hook not invoked
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Addrinfo.getaddrinfo("<any>", 80, :AF_INET, :STREAM)
        assert_equal(1, result.count)

        ai = result.first
        assert_equal("0.0.0.0", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_localhost
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        results = Addrinfo.getaddrinfo("localhost", 80, :AF_INET, :STREAM)
        assert_equal(1, results.count)

        ai = results.first
        assert_equal("1.2.3.4", ai.ip_address)
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_non_existing_domain_blocking
    Thread.new do
      scheduler = NullScheduler.new # invoked, returns nil
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        assert_raise(SocketError) {
          Addrinfo.getaddrinfo("non-existing-domain.abc", nil)
        }
      end
    end.join
  end

  def test_addrinfo_getaddrinfo_no_host_non_blocking
    Thread.new do
      scheduler = NullScheduler.new # scheduler hook not invoked
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Addrinfo.getaddrinfo(nil, 80, :AF_INET, :STREAM)
        assert_equal(1, result.count)

        ai = result.first
        assert_equal("127.0.0.1", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_ip_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        ai = Addrinfo.ip("example.com")

        assert_equal("1.2.3.4", ai.ip_address)
      end
    end.join
  end

  def test_addrinfo_tcp_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        ai = Addrinfo.tcp("example.com", 80)

        assert_equal("1.2.3.4", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_STREAM, ai.socktype)
      end
    end.join
  end

  def test_addrinfo_udp_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        ai = Addrinfo.udp("example.com", 80)

        assert_equal("1.2.3.4", ai.ip_address)
        assert_equal(80, ai.ip_port)
        assert_equal(Socket::AF_INET, ai.afamily)
        assert_equal(Socket::SOCK_DGRAM, ai.socktype)
      end
    end.join
  end

  def test_ip_socket_getaddress_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        ip = IPSocket.getaddress("example.com")

        assert_equal("1.2.3.4", ip)
      end
    end.join
  end

  # This test "hits deep" into C function call chain.
  def test_socket_getnameinfo_domain_blocking
    Thread.new do
      scheduler = StubScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = Socket.getnameinfo(["AF_INET", 80, "example.com"], Socket::NI_NUMERICSERV)

        assert_equal(["1.2.3.4", "80"], result)
      end
    end.join
  end
end
