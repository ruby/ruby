# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require 'stringio'
require_relative 'utils'
require 'webrick'
begin
  require 'openssl'
  require 'webrick/https'
rescue LoadError
end
require 'webrick/httpproxy'

class TestOpenURISSL < Test::Unit::TestCase
end

class TestOpenURISSL
  include TestOpenURIUtils

  NullLog = Object.new
  def NullLog.<<(arg)
  end

  def with_https_webrick(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    logger = WEBrick::Log.new(log, WEBrick::BasicLog::WARN)
    Dir.mktmpdir {|dr|
      srv = WEBrick::HTTPServer.new({
        :DocumentRoot => dr,
        :ServerType => Thread,
        :Logger => logger,
        :AccessLog => [[NullLog, ""]],
        :SSLEnable => true,
        :SSLCertificate => OpenSSL::X509::Certificate.new(SERVER_CERT),
        :SSLPrivateKey => OpenSSL::PKey::RSA.new(SERVER_KEY),
        :SSLTmpDhCallback => proc { OpenSSL::PKey::DH.new(DHPARAMS) },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, port, _, host = srv.listeners[0].addr
      threads = []
      server_thread = srv.start
      threads << Thread.new {
        server_thread.join
        if log_tester
          log_tester.call(log)
        end
      }
      threads << Thread.new {
        begin
          yield srv, dr, "https://#{host}:#{port}", server_thread, log, threads
        ensure
          srv.shutdown
        end
      }
      assert_join_threads(threads)
    }
  ensure
    WEBrick::Utils::TimeoutHandler.terminate
  end

  def setup
    @proxies = %w[http_proxy HTTP_PROXY https_proxy HTTPS_PROXY ftp_proxy FTP_PROXY no_proxy]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }
  end

  def teardown
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def setup_validation(srv, dr)
    cacert_filename = "#{dr}/cacert.pem"
    URI.open(cacert_filename, "w") {|f| f << CA_CERT }
    if srv.respond_to?(:mount_proc)
      srv.mount_proc("/data", lambda { |req, res| res.body = "ddd" } )
    end
    cacert_filename
  end

  def test_validation_success
    with_https {|srv, dr, url|
      cacert_filename = setup_validation(srv, dr)
      URI.open("#{url}/data", :ssl_ca_cert => cacert_filename) {|f|
        assert_equal("200", f.status[0])
        assert_equal("ddd", f.read)
      }
    }
  end

  def test_validation_noverify
    with_https {|srv, dr, url|
      setup_validation(srv, dr)
      URI.open("#{url}/data", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE) {|f|
        assert_equal("200", f.status[0])
        assert_equal("ddd", f.read)
      }
    }
  end

  def test_validation_failure
    unless /mswin|mingw/ =~ RUBY_PLATFORM
      # on Windows, Errno::ECONNRESET will be raised, and it'll be eaten by
      # WEBrick
      log_tester = lambda {|server_log|
        assert_equal(1, server_log.length)
        assert_match(/ERROR OpenSSL::SSL::SSLError:/, server_log[0])
      }
    end
    with_https_webrick(log_tester) {|srv, dr, url, server_thread, server_log|
      setup_validation(srv, dr)
      assert_raise(OpenSSL::SSL::SSLError) { URI.open("#{url}/data") {} }
    }
  end

  def test_ssl_min_version
    with_https {|srv, dr, url|
      setup_validation(srv, dr)
      URI.open("#{url}/data", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE, :ssl_min_version => :TLS1_2) {|f|
        assert_equal("200", f.status[0])
        assert_equal("ddd", f.read)
      }
    }
  end

  def test_bad_ssl_version
    with_https(nil) {|srv, dr, url|
      setup_validation(srv, dr)
      assert_raise(ArgumentError) {
        URI.open("#{url}/data", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE, :ssl_min_version => :TLS_no_such_version) {}
      }
    }
  end

  def with_https_proxy(proxy_log_tester=lambda {|proxy_log, proxy_access_log| assert_equal([], proxy_log) })
    proxy_log = []
    proxy_logger = WEBrick::Log.new(proxy_log, WEBrick::BasicLog::WARN)
    with_https {|srv, dr, url, server_thread, server_log, threads|
      cacert_filename = "#{dr}/cacert.pem"
      open(cacert_filename, "w") {|f| f << CA_CERT }
      cacert_directory = "#{dr}/certs"
      Dir.mkdir cacert_directory
      hashed_name = "%08x.0" % OpenSSL::X509::Certificate.new(CA_CERT).subject.hash
      open("#{cacert_directory}/#{hashed_name}", "w") {|f| f << CA_CERT }
      proxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => proxy_logger,
        :AccessLog => [[proxy_access_log=[], WEBrick::AccessLog::COMMON_LOG_FORMAT]],
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, proxy_port, _, proxy_host = proxy.listeners[0].addr
      proxy_thread = proxy.start
      threads << Thread.new {
        proxy_thread.join
        if proxy_log_tester
          proxy_log_tester.call(proxy_log, proxy_access_log)
        end
      }
      begin
        yield srv, dr, url, cacert_filename, cacert_directory, proxy_host, proxy_port
      ensure
        proxy.shutdown
      end
    }
  end

  def test_proxy_cacert_file
    url = nil
    proxy_log_tester = lambda {|proxy_log, proxy_access_log|
      assert_equal(1, proxy_access_log.length)
      assert_match(%r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ], proxy_access_log[0])
      assert_equal([], proxy_log)
    }
    with_https_proxy(proxy_log_tester) {|srv, dr, url_, cacert_filename, cacert_directory, proxy_host, proxy_port|
      url = url_
      URI.open("#{url}/proxy", :proxy=>"http://#{proxy_host}:#{proxy_port}/", :ssl_ca_cert => cacert_filename) {|f|
        assert_equal("200", f.status[0])
        assert_equal("proxy", f.read)
      }
    }
  end

  def test_proxy_cacert_dir
    url = nil
    proxy_log_tester = lambda {|proxy_log, proxy_access_log|
      assert_equal(1, proxy_access_log.length)
      assert_match(%r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ], proxy_access_log[0])
      assert_equal([], proxy_log)
    }
    with_https_proxy(proxy_log_tester) {|srv, dr, url_, cacert_filename, cacert_directory, proxy_host, proxy_port|
      url = url_
      URI.open("#{url}/proxy", :proxy=>"http://#{proxy_host}:#{proxy_port}/", :ssl_ca_cert => cacert_directory) {|f|
        assert_equal("200", f.status[0])
        assert_equal("proxy", f.read)
      }
    }
  end

end if defined?(OpenSSL::SSL)
