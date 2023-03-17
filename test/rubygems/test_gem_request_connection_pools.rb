# frozen_string_literal: true

require_relative "helper"
require "rubygems/request"
require "timeout"

class TestGemRequestConnectionPool < Gem::TestCase
  class FakeHttp
    def initialize(*args)
    end

    def start
    end
  end

  def setup
    super
    @old_client = Gem::Request::ConnectionPools.client
    Gem::Request::ConnectionPools.client = FakeHttp

    @proxy = URI "http://proxy.example"
  end

  def teardown
    Gem::Request::ConnectionPools.client = @old_client
    super
  end

  def test_to_proxy_substring
    pools = Gem::Request::ConnectionPools.new nil, []

    env_no_proxy = %w[
      ems.example
    ]

    no_proxy = pools.send :no_proxy?, "rubygems.example", env_no_proxy

    refute no_proxy, "mismatch"
  end

  def test_to_proxy_empty_string
    pools = Gem::Request::ConnectionPools.new nil, []

    env_no_proxy = [""]

    no_proxy = pools.send :no_proxy?, "ems.example", env_no_proxy

    refute no_proxy, "mismatch"
  end

  def test_checkout_same_connection
    uri = URI.parse("http://example/some_endpoint")

    pools = Gem::Request::ConnectionPools.new nil, []
    pool = pools.pool_for uri
    conn = pool.checkout
    pool.checkin conn

    assert_equal conn, pool.checkout
  end

  def test_to_proxy_eh
    pools = Gem::Request::ConnectionPools.new nil, []

    env_no_proxy = %w[
      1.no-proxy.example
      2.no-proxy.example
    ]

    no_proxy = pools.send :no_proxy?, "2.no-proxy.example", env_no_proxy

    assert no_proxy, "match"

    no_proxy = pools.send :no_proxy?, "proxy.example", env_no_proxy

    refute no_proxy, "mismatch"
  end

  def test_to_proxy_eh_wildcard
    pools = Gem::Request::ConnectionPools.new nil, []

    env_no_proxy = %w[
      .no-proxy.example
    ]

    no_proxy = pools.send :no_proxy?, "2.no-proxy.example", env_no_proxy

    assert no_proxy, "wildcard matching subdomain"

    no_proxy = pools.send :no_proxy?, "no-proxy.example", env_no_proxy

    assert no_proxy, "wildcard matching dotless domain"

    no_proxy = pools.send :no_proxy?, "proxy.example", env_no_proxy

    refute no_proxy, "wildcard mismatch"
  end

  def test_net_http_args
    pools = Gem::Request::ConnectionPools.new nil, []

    net_http_args = pools.send :net_http_args, URI("http://example"), nil

    assert_equal ["example", 80], net_http_args
  end

  def test_net_http_args_ipv6
    pools = Gem::Request::ConnectionPools.new nil, []

    net_http_args = pools.send :net_http_args, URI("http://[::1]"), nil

    assert_equal ["::1", 80], net_http_args
  end

  def test_net_http_args_proxy
    pools = Gem::Request::ConnectionPools.new nil, []

    net_http_args = pools.send :net_http_args, URI("http://example"), @proxy

    assert_equal ["example", 80, "proxy.example", 80, nil, nil], net_http_args
  end

  def test_net_http_args_no_proxy
    orig_no_proxy = ENV["no_proxy"]
    ENV["no_proxy"] = "example"

    pools = Gem::Request::ConnectionPools.new nil, []

    net_http_args = pools.send :net_http_args, URI("http://example"), @proxy

    assert_equal ["example", 80, nil, nil], net_http_args
  ensure
    ENV["no_proxy"] = orig_no_proxy
  end

  def test_thread_waits_for_connection
    uri = URI.parse("http://example/some_endpoint")
    pools = Gem::Request::ConnectionPools.new nil, []
    pool  = pools.pool_for uri

    pool.checkout

    Thread.new do
      assert_raise(Timeout::Error) do
        Timeout.timeout(1) do
          pool.checkout
        end
      end
    end.join
  end
end
