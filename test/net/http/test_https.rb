# frozen_string_literal: false
require "test/unit"
require_relative "utils"
begin
  require 'net/https'
rescue LoadError
  # should skip this test
end

return unless defined?(OpenSSL::SSL)

class TestNetHTTPS < Test::Unit::TestCase
  include TestNetHTTPUtils

  def self.read_fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  HOST = 'localhost'
  HOST_IP = '127.0.0.1'
  CA_CERT = OpenSSL::X509::Certificate.new(read_fixture("cacert.pem"))
  SERVER_KEY = OpenSSL::PKey.read(read_fixture("server.key"))
  SERVER_CERT = OpenSSL::X509::Certificate.new(read_fixture("server.crt"))
  TEST_STORE = OpenSSL::X509::Store.new.tap {|s| s.add_cert(CA_CERT) }

  CONFIG = {
    'host' => HOST,
    'proxy_host' => nil,
    'proxy_port' => nil,
    'ssl_enable' => true,
    'ssl_certificate' => SERVER_CERT,
    'ssl_private_key' => SERVER_KEY,
  }

  def test_get
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
      assert_equal(SERVER_CERT.to_der, http.peer_cert.to_der)
    }
  end

  def test_get_SNI
    http = Net::HTTP.new(HOST, config("port"))
    http.ipaddr = config('host')
    http.use_ssl = true
    http.cert_store = TEST_STORE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
      assert_equal(SERVER_CERT.to_der, http.peer_cert.to_der)
    }
  end

  def test_get_SNI_proxy
    TCPServer.open(HOST_IP, 0) {|serv|
      _, port, _, _ = serv.addr
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy(HOST_IP, port, 'user', 'password')
        http = proxy.new("foo.example.org", 8000)
        http.ipaddr = "192.0.2.1"
        http.use_ssl = true
        http.cert_store = TEST_STORE
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
      @log_tester = lambda {|_| }
      assert_raise(OpenSSL::SSL::SSLError){ http.start }
    end
  end

  def test_post
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    data = config('ssl_private_key').to_der
    http.request_post("/", data, {'content-type' => 'application/x-www-form-urlencoded'}) {|res|
      assert_equal(data, res.body)
    }
  end

  def test_session_reuse
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE

    if OpenSSL::OPENSSL_LIBRARY_VERSION =~ /LibreSSL (\d+\.\d+)/ && $1.to_f > 3.19
      # LibreSSL 3.2 defaults to TLSv1.3 in server and client, which doesn't currently
      # support session resuse.  Limiting the version to the TLSv1.2 stack allows
      # this test to continue to work on LibreSSL 3.2+.  LibreSSL may eventually
      # support session reuse, but there are no current plans to do so.
      http.ssl_version = :TLSv1_2
    end

    http.start
    session_reused = http.instance_variable_get(:@socket).io.session_reused?
    assert_false session_reused unless session_reused.nil? # can not detect re-use under JRuby
    http.get("/")
    http.finish

    http.start
    session_reused = http.instance_variable_get(:@socket).io.session_reused?
    assert_true session_reused unless session_reused.nil? # can not detect re-use under JRuby
    assert_equal $test_net_http_data, http.get("/").body
    http.finish
  end

  def test_session_reuse_but_expire
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE

    http.ssl_timeout = 1
    http.start
    http.get("/")
    http.finish
    sleep 1.25
    http.start
    http.get("/")

    socket = http.instance_variable_get(:@socket).io
    assert_equal false, socket.session_reused?, "NOTE: OpenSSL library version is #{OpenSSL::OPENSSL_LIBRARY_VERSION}"

    http.finish
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
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
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
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
    }
    assert_match(/certificate verify failed/, ex.message)
  end

  def test_verify_callback
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    certs = []
    http.verify_callback = Proc.new {|preverify_ok, store_ctx|
      certs << store_ctx.current_cert
      preverify_ok
    }
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
    assert_equal(SERVER_CERT.to_der, certs.last.to_der)
  end

  def test_timeout_during_SSL_handshake
    bug4246 = "expected the SSL connection to have timed out but have not. [ruby-core:34203]"

    # listen for connections... but deliberately do not complete SSL handshake
    TCPServer.open(HOST, 0) {|server|
      port = server.addr[1]

      conn = Net::HTTP.new(HOST, port)
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
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.min_version = :TLS1
    http.cert_store = TEST_STORE
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
  end

  def test_max_version
    http = Net::HTTP.new(HOST, config("port"))
    http.use_ssl = true
    http.max_version = :SSL2
    http.cert_store = TEST_STORE
    @log_tester = lambda {|_| }
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
    }
    re_msg = /\ASSL_connect returned=1 errno=0 |SSL_CTX_set_max_proto_version|No appropriate protocol/
    assert_match(re_msg, ex.message)
  end

  def test_ractor
    assert_ractor(<<~RUBY, require: 'net/https')
      expected = #{$test_net_http_data.dump}.b
      ret = Ractor.new {
        host = #{HOST.dump}
        port = #{config('port')}
        ca_cert_pem = #{CA_CERT.to_pem.dump}
        cert_store = OpenSSL::X509::Store.new.tap { |s|
          s.add_cert(OpenSSL::X509::Certificate.new(ca_cert_pem))
        }
        Net::HTTP.start(host, port, use_ssl: true, cert_store: cert_store) { |http|
          res = http.get('/')
          res.body
        }
      }.value
      assert_equal expected, ret
    RUBY
  end if defined?(Ractor) && Ractor.method_defined?(:value)
end

class TestNetHTTPSIdentityVerifyFailure < Test::Unit::TestCase
  include TestNetHTTPUtils

  def self.read_fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  HOST = 'localhost'
  HOST_IP = '127.0.0.1'
  CA_CERT = OpenSSL::X509::Certificate.new(read_fixture("cacert.pem"))
  SERVER_KEY = OpenSSL::PKey.read(read_fixture("server.key"))
  SERVER_CERT = OpenSSL::X509::Certificate.new(read_fixture("server.crt"))
  TEST_STORE = OpenSSL::X509::Store.new.tap {|s| s.add_cert(CA_CERT) }

  CONFIG = {
    'host' => HOST_IP,
    'proxy_host' => nil,
    'proxy_port' => nil,
    'ssl_enable' => true,
    'ssl_certificate' => SERVER_CERT,
    'ssl_private_key' => SERVER_KEY,
  }

  def test_identity_verify_failure
    # the certificate's subject has CN=localhost
    http = Net::HTTP.new(HOST_IP, config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE
    @log_tester = lambda {|_| }
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
      sleep 0.5
    }
    re_msg = /certificate verify failed|hostname \"#{HOST_IP}\" does not match/
    assert_match(re_msg, ex.message)
  end
end
