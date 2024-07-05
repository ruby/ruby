# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require_relative 'utils'

class TestOpenURIProxy < Test::Unit::TestCase
  include TestOpenURIUtils

  def with_env(h)
    begin
      old = {}
      h.each_key {|k| old[k] = ENV[k] }
      h.each {|k, v| ENV[k] = v }
      yield
    ensure
      h.each_key {|k| ENV[k] = old[k] }
    end
  end

  def setup
    @proxies = %w[http_proxy HTTP_PROXY ftp_proxy FTP_PROXY no_proxy]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }
  end

  def teardown
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def test_proxy
    with_http {|srv, url|
      proxy_log = StringIO.new(''.dup)
      proxy_access_log = StringIO.new(''.dup)
      proxy_auth_log = ''.dup
      proxy_host = '127.0.0.1'
      proxy = SimpleHTTPProxyServer.new(proxy_host, 0, lambda {|req, res|
          proxy_auth_log << req.request_line
      }, proxy_log, proxy_access_log)
      proxy_port = proxy.instance_variable_get(:@server).addr[1]
      proxy_url = "http://#{proxy_host}:#{proxy_port}/"
      begin
        proxy_thread = proxy.start
        srv.mount_proc("/proxy", lambda { |req, res| res.body = "proxy" } )
        URI.open("#{url}/proxy", :proxy=>proxy_url) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_match(/#{Regexp.quote url}/, proxy_auth_log); proxy_auth_log.clear
        URI.open("#{url}/proxy", :proxy=>URI(proxy_url)) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_match(/#{Regexp.quote url}/, proxy_auth_log); proxy_auth_log.clear
        URI.open("#{url}/proxy", :proxy=>nil) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_equal("", proxy_auth_log); proxy_auth_log.clear
        assert_raise(ArgumentError) {
          URI.open("#{url}/proxy", :proxy=>:invalid) {}
        }
        assert_equal("", proxy_auth_log); proxy_auth_log.clear
        with_env("http_proxy"=>proxy_url) {
          # should not use proxy for 127.0.0.0/8.
          URI.open("#{url}/proxy") {|f|
            assert_equal("200", f.status[0])
            assert_equal("proxy", f.read)
          }
        }
        assert_equal("", proxy_auth_log); proxy_auth_log.clear
      ensure
        proxy.shutdown
        proxy_thread.join
      end
      assert_equal("", proxy_log.string)
    }
  end

  def test_proxy_http_basic_authentication_failure
    with_http {|srv, url|
      proxy_log = StringIO.new(''.dup)
      proxy_access_log = StringIO.new(''.dup)
      proxy_auth_log = ''.dup
      proxy_host = '127.0.0.1'
      proxy = SimpleHTTPProxyServer.new(proxy_host, 0, lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise ProxyAuthenticationRequired
          end
      }, proxy_log, proxy_access_log)
      proxy_port = proxy.instance_variable_get(:@server).addr[1]
      proxy_url = "http://#{proxy_host}:#{proxy_port}/"
      begin
        th = proxy.start
        srv.mount_proc("/proxy", lambda { |req, res| res.body = "proxy" } )
        exc = assert_raise(OpenURI::HTTPError) { URI.open("#{url}/proxy", :proxy=>proxy_url) {} }
        assert_equal("407", exc.io.status[0])
        assert_match(/#{Regexp.quote url}/, proxy_auth_log); proxy_auth_log.clear
      ensure
        proxy.shutdown
        th.join
      end
      assert_match(/ERROR ProxyAuthenticationRequired/, proxy_log.string)
    }
  end

  def test_proxy_http_basic_authentication_success
    with_http {|srv, url|
      proxy_log = StringIO.new(''.dup)
      proxy_access_log = StringIO.new(''.dup)
      proxy_auth_log = ''.dup
      proxy_host = '127.0.0.1'
      proxy = SimpleHTTPProxyServer.new(proxy_host, 0, lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise ProxyAuthenticationRequired
          end
      }, proxy_log, proxy_access_log)
      proxy_port = proxy.instance_variable_get(:@server).addr[1]
      proxy_url = "http://#{proxy_host}:#{proxy_port}/"
      begin
        th = proxy.start
        srv.mount_proc("/proxy", lambda { |req, res| res.body = "proxy" } )
        URI.open("#{url}/proxy",
            :proxy_http_basic_authentication=>[proxy_url, "user", "pass"]) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_match(/#{Regexp.quote url}/, proxy_auth_log); proxy_auth_log.clear
        assert_raise(ArgumentError) {
          URI.open("#{url}/proxy",
              :proxy_http_basic_authentication=>[true, "user", "pass"]) {}
        }
        assert_equal("", proxy_auth_log); proxy_auth_log.clear
      ensure
        proxy.shutdown
        th.join
      end
      assert_equal("", proxy_log.string)
    }
  end

  def test_authenticated_proxy_http_basic_authentication_success
    with_http {|srv, url|
      proxy_log = StringIO.new(''.dup)
      proxy_access_log = StringIO.new(''.dup)
      proxy_auth_log = ''.dup
      proxy_host = '127.0.0.1'
      proxy = SimpleHTTPProxyServer.new(proxy_host, 0, lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise ProxyAuthenticationRequired
          end
      }, proxy_log, proxy_access_log)
      proxy_port = proxy.instance_variable_get(:@server).addr[1]
      proxy_url = "http://user:pass@#{proxy_host}:#{proxy_port}/"
      begin
        th = proxy.start
        srv.mount_proc("/proxy", lambda { |req, res| res.body = "proxy" } )
        URI.open("#{url}/proxy", :proxy => proxy_url) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_match(/#{Regexp.quote url}/, proxy_auth_log); proxy_auth_log.clear
        assert_equal("", proxy_auth_log); proxy_auth_log.clear
      ensure
        proxy.shutdown
        th.join
      end
      assert_equal("", proxy_log.string)
    }
  end
end
