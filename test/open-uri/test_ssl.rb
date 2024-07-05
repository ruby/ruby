# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require 'stringio'
require_relative 'utils'
begin
  require 'openssl'
rescue LoadError
end

class TestOpenURISSL < Test::Unit::TestCase
  include TestOpenURIUtils

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
    with_https(nil) {|srv, dr, url, server_thread, server_log|
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
