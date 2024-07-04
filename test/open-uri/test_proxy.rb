# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require 'webrick'
require 'webrick/httpproxy'
begin
  require 'zlib'
rescue LoadError
end

class TestOpenURIProxy < Test::Unit::TestCase

  NullLog = Object.new
  def NullLog.<<(arg)
    #puts arg if / INFO / !~ arg
  end

  def with_http(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    logger = WEBrick::Log.new(log, WEBrick::BasicLog::WARN)
    Dir.mktmpdir {|dr|
      srv = WEBrick::HTTPServer.new({
        :DocumentRoot => dr,
        :ServerType => Thread,
        :Logger => logger,
        :AccessLog => [[NullLog, ""]],
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, port, _, host = srv.listeners[0].addr
      server_thread = srv.start
      server_thread2 = Thread.new {
        server_thread.join
        if log_tester
          log_tester.call(log)
        end
      }
      client_thread = Thread.new {
        begin
          yield srv, dr, "http://#{host}:#{port}", server_thread, log
        ensure
          srv.shutdown
        end
      }
      assert_join_threads([client_thread, server_thread2])
    }
  ensure
    WEBrick::Utils::TimeoutHandler.terminate
  end

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
    with_http {|srv, dr, url|
      proxy_log = StringIO.new(''.dup)
      proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
      proxy_auth_log = ''.dup
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[NullLog, ""]],
        :ProxyAuthProc => lambda {|req, res|
          proxy_auth_log << req.request_line
        },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
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
    with_http {|srv, dr, url|
      proxy_log = StringIO.new(''.dup)
      proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
      proxy_auth_log = ''.dup
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[NullLog, ""]],
        :ProxyAuthProc => lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise WEBrick::HTTPStatus::ProxyAuthenticationRequired
          end
        },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
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
      assert_match(/ERROR WEBrick::HTTPStatus::ProxyAuthenticationRequired/, proxy_log.string)
    }
  end

  def test_proxy_http_basic_authentication_success
    with_http {|srv, dr, url|
      proxy_log = StringIO.new(''.dup)
      proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
      proxy_auth_log = ''.dup
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[NullLog, ""]],
        :ProxyAuthProc => lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise WEBrick::HTTPStatus::ProxyAuthenticationRequired
          end
        },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
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
    with_http {|srv, dr, url|
      proxy_log = StringIO.new(''.dup)
      proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
      proxy_auth_log = ''.dup
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[NullLog, ""]],
        :ProxyAuthProc => lambda {|req, res|
          proxy_auth_log << req.request_line
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise WEBrick::HTTPStatus::ProxyAuthenticationRequired
          end
        },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
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
