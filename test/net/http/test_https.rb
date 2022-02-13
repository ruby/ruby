# frozen_string_literal: false
require "test/unit"
begin
  require 'net/https'
  require 'stringio'
  require 'timeout'
  require File.expand_path("utils", File.dirname(__FILE__))
rescue LoadError
  # should skip this test
end

class TestNetHTTPS < Test::Unit::TestCase
  include TestNetHTTPUtils

  def self.read_fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  CA_CERT = OpenSSL::X509::Certificate.new(read_fixture("cacert.pem"))
  SERVER_KEY = OpenSSL::PKey.read(read_fixture("server.key"))
  SERVER_CERT = OpenSSL::X509::Certificate.new(read_fixture("server.crt"))
  DHPARAMS = OpenSSL::PKey::DH.new(read_fixture("dhparams.pem"))
  TEST_STORE = OpenSSL::X509::Store.new.tap {|s| s.add_cert(CA_CERT) }

  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'ssl_enable' => true,
    'ssl_certificate' => SERVER_CERT,
    'ssl_private_key' => SERVER_KEY,
    'ssl_tmp_dh_callback' => proc { DHPARAMS },
  }

  def test_get
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    certs = []
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      certs << store_ctx.current_cert
      preverify_ok
    end
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
    # TODO: OpenSSL 1.1.1h seems to yield only SERVER_CERT; need to check the incompatibility
    certs.zip([CA_CERT, SERVER_CERT][-certs.size..]) do |actual, expected|
      assert_equal(expected.to_der, actual.to_der)
    end
  rescue SystemCallError
    skip $!
  end

  def test_get_SNI
    http = Net::HTTP.new("localhost", config("port"))
    http.ipaddr = config('host')
    http.use_ssl = true
    http.cert_store = TEST_STORE
    certs = []
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      certs << store_ctx.current_cert
      preverify_ok
    end
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
    # TODO: OpenSSL 1.1.1h seems to yield only SERVER_CERT; need to check the incompatibility
    certs.zip([CA_CERT, SERVER_CERT][-certs.size..]) do |actual, expected|
      assert_equal(expected.to_der, actual.to_der)
    end
  end

  def test_get_SNI_proxy
    TCPServer.open("127.0.0.1", 0) {|serv|
      _, port, _, _ = serv.addr
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password')
        http = proxy.new("foo.example.org", 8000)
        http.ipaddr = "192.0.2.1"
        http.use_ssl = true
        http.cert_store = TEST_STORE
        certs = []
        http.verify_callback = Proc.new do |preverify_ok, store_ctx|
          certs << store_ctx.current_cert
          preverify_ok
        end
        begin
          http.start
        rescue EOFError
        end
      }
      server_thread = Thread.new {
        sock = serv.accept
        begin
          proxy_request = sock.gets("\r\n\r\n")
          assert_equal(
            "CONNECT 192.0.2.1:8000 HTTP/1.1\r\n" +
            "Host: foo.example.org:8000\r\n" +
            "Proxy-Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n" +
            "\r\n",
            proxy_request,
            "[ruby-dev:25673]")
        ensure
          sock.close
        end
      }
      assert_join_threads([client_thread, server_thread])
    }

  end

  def test_get_SNI_failure
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new("invalidservername", config("port"))
      http.ipaddr = config('host')
      http.use_ssl = true
      http.cert_store = TEST_STORE
      certs = []
      http.verify_callback = Proc.new do |preverify_ok, store_ctx|
        certs << store_ctx.current_cert
        preverify_ok
      end
      @log_tester = lambda {|_| }
      assert_raise(OpenSSL::SSL::SSLError){ http.start }
    end
  end

  def test_post
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    data = config('ssl_private_key').to_der
    http.request_post("/", data, {'content-type' => 'application/x-www-form-urlencoded'}) {|res|
      assert_equal(data, res.body)
    }
  rescue SystemCallError
    skip $!
  end

  def test_session_reuse
    # FIXME: The new_session_cb is known broken for clients in OpenSSL 1.1.0h.
    # See https://github.com/openssl/openssl/pull/5967 for details.
    skip if OpenSSL::OPENSSL_LIBRARY_VERSION =~ /OpenSSL 1.1.0h/

    # FIXME: GitHub Actions for MinGW failed. Maybe it's because of OpenSSL on MiNGW
    if /mingw/ =~ RUBY_PLATFORM
      skip "Skip net/https test using openssl on MinGW"
    end

    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE

    if OpenSSL::OPENSSL_LIBRARY_VERSION =~ /LibreSSL (\d+\.\d+)/ && $1.to_f > 3.19
      # LibreSSL 3.2 defaults to TLSv1.3 in server and client, which doesn't currently
      # support session resuse.  Limiting the version to the TLSv1.2 stack allows
      # this test to continue to work on LibreSSL 3.2+.  LibreSSL may eventually
      # support session reuse, but there are no current plans to do so.
      http.ssl_version = :TLSv1
    end

    http.start
    http.get("/")
    http.finish

    http.start
    http.get("/")

    socket = http.instance_variable_get(:@socket).io
    assert_equal true, socket.session_reused?

    http.finish
  rescue SystemCallError
    skip $!
  end

  def test_session_reuse_but_expire
    # FIXME: The new_session_cb is known broken for clients in OpenSSL 1.1.0h.
    skip if OpenSSL::OPENSSL_LIBRARY_VERSION =~ /OpenSSL 1.1.0h/

    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE

    http.ssl_timeout = -1
    http.start
    http.get("/")
    http.finish

    http.start
    http.get("/")

    socket = http.instance_variable_get(:@socket).io
    assert_equal false, socket.session_reused?

    http.finish
  rescue SystemCallError
    skip $!
  end

  if ENV["RUBY_OPENSSL_TEST_ALL"]
    def test_verify
      http = Net::HTTP.new("ssl.netlab.jp", 443)
      http.use_ssl = true
      assert(
        (http.request_head("/"){|res| } rescue false),
        "The system may not have default CA certificate store."
      )
    end
  end

  def test_verify_none
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
  rescue SystemCallError
    skip $!
  end

  def test_skip_hostname_verification
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new('invalidservername', config('port'))
      http.ipaddr = config('host')
      http.use_ssl = true
      http.cert_store = TEST_STORE
      http.verify_hostname = false
      assert_nothing_raised { http.start }
    ensure
      http.finish if http&.started?
    end
  end

  def test_fail_if_verify_hostname_is_true
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new('invalidservername', config('port'))
      http.ipaddr = config('host')
      http.use_ssl = true
      http.cert_store = TEST_STORE
      http.verify_hostname = true
      @log_tester = lambda { |_| }
      assert_raise(OpenSSL::SSL::SSLError) { http.start }
    end
  end

  def test_certificate_verify_failure
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    ex = assert_raise(OpenSSL::SSL::SSLError){
      begin
        http.request_get("/") {|res| }
      rescue SystemCallError
        skip $!
      end
    }
    assert_match(/certificate verify failed/, ex.message)
    unless /mswin|mingw/ =~ RUBY_PLATFORM
      # on Windows, Errno::ECONNRESET will be raised, and it'll be eaten by
      # WEBrick
      @log_tester = lambda {|log|
        assert_equal(1, log.length)
        assert_match(/ERROR OpenSSL::SSL::SSLError:/, log[0])
      }
    end
  end

  def test_identity_verify_failure
    # the certificate's subject has CN=localhost
    http = Net::HTTP.new("127.0.0.1", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    @log_tester = lambda {|_| }
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
    }
    re_msg = /certificate verify failed|hostname \"127.0.0.1\" does not match/
    assert_match(re_msg, ex.message)
  end

  def test_timeout_during_SSL_handshake
    bug4246 = "expected the SSL connection to have timed out but have not. [ruby-core:34203]"

    # listen for connections... but deliberately do not complete SSL handshake
    TCPServer.open('localhost', 0) {|server|
      port = server.addr[1]

      conn = Net::HTTP.new('localhost', port)
      conn.use_ssl = true
      conn.read_timeout = 0.01
      conn.open_timeout = 0.01

      th = Thread.new do
        assert_raise(Net::OpenTimeout) {
          conn.get('/')
        }
      end
      assert th.join(10), bug4246
    }
  end

  def test_min_version
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.min_version = :TLS1
    http.cert_store = TEST_STORE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
  end

  def test_max_version
    http = Net::HTTP.new("127.0.0.1", config("port"))
    http.use_ssl = true
    http.max_version = :SSL2
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      true
    end
    @log_tester = lambda {|_| }
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
    }
    re_msg = /\ASSL_connect returned=1 errno=0 |SSL_CTX_set_max_proto_version/
    assert_match(re_msg, ex.message)
  end

end if defined?(OpenSSL::SSL)
