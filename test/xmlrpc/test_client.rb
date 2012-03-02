require 'minitest/autorun'
require 'xmlrpc/client'

module XMLRPC
  class ClientTest < MiniTest::Unit::TestCase
    class FakeClient < XMLRPC::Client
      attr_reader :args

      def initialize(*args)
        @args = args
        super
      end
    end

    def test_new2_host_path_port
      client = FakeClient.new2 'http://example.org/foo'
      host, path, port, *rest = client.args

      assert_equal 'example.org', host
      assert_equal '/foo', path
      assert_equal 80, port

      rest.each { |x| refute x }
    end

    def test_new2_custom_port
      client = FakeClient.new2 'http://example.org:1234/foo'
      host, path, port, *rest = client.args

      assert_equal 'example.org', host
      assert_equal '/foo', path
      assert_equal 1234, port

      rest.each { |x| refute x }
    end

    def test_new2_ssl
      client = FakeClient.new2 'https://example.org/foo'
      host, path, port, proxy_host, proxy_port, user, password, use_ssl, timeout = client.args

      assert_equal 'example.org', host
      assert_equal '/foo', path
      assert_equal 443, port
      assert use_ssl

      refute proxy_host
      refute proxy_port
      refute user
      refute password
      refute timeout
    end

    def test_new2_ssl_custom_port
      client = FakeClient.new2 'https://example.org:1234/foo'
      host, path, port, proxy_host, proxy_port, user, password, use_ssl, timeout = client.args

      assert_equal 'example.org', host
      assert_equal '/foo', path
      assert_equal 1234, port

      refute proxy_host
      refute proxy_port
      refute user
      refute password
      refute timeout
    end

    def test_new2_user_password
      client = FakeClient.new2 'http://aaron:tenderlove@example.org/foo'
      host, path, port, proxy_host, proxy_port, user, password, use_ssl, timeout = client.args

      [ host, path, port ].each { |x| assert x }
      assert_equal 'aaron', user
      assert_equal 'tenderlove', password

      [ proxy_host, proxy_port, use_ssl, timeout ].each { |x| refute x }
    end

    def test_new2_proxy_host
      client = FakeClient.new2 'http://example.org/foo', 'example.com'
      host, path, port, proxy_host, proxy_port, user, password, use_ssl, timeout = client.args

      [ host, path, port ].each { |x| assert x }

      assert_equal 'example.com', proxy_host

      [ user, password, proxy_port, use_ssl, timeout ].each { |x| refute x }
    end

    def test_new2_proxy_port
      client = FakeClient.new2 'http://example.org/foo', 'example.com:1234'
      host, path, port, proxy_host, proxy_port, user, password, use_ssl, timeout = client.args

      [ host, path, port ].each { |x| assert x }

      assert_equal 'example.com', proxy_host
      assert_equal 1234, proxy_port

      [ user, password, use_ssl, timeout ].each { |x| refute x }
    end

    def test_new2_no_path
      client = FakeClient.new2 'http://example.org'
      host, path, port, *rest = client.args

      assert_equal 'example.org', host
      assert_nil path
      assert port

      rest.each { |x| refute x }
    end

    def test_new2_slash_path
      client = FakeClient.new2 'http://example.org/'
      host, path, port, *rest = client.args

      assert_equal 'example.org', host
      assert_equal '/', path
      assert port

      rest.each { |x| refute x }
    end

    def test_new2_bad_protocol
      assert_raises(ArgumentError) do
        XMLRPC::Client.new2 'ftp://example.org'
      end
    end

    def test_new2_bad_uri
      assert_raises(ArgumentError) do
        XMLRPC::Client.new2 ':::::'
      end
    end
  end
end
