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

  def self.fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  CA_CERT = OpenSSL::X509::Certificate.new(fixture("cacert.pem"))
  SERVER_KEY = OpenSSL::PKey.read(fixture("server.key"))
  SERVER_CERT = OpenSSL::X509::Certificate.new(fixture("server.crt"))
  DHPARAMS = OpenSSL::PKey::DH.new(fixture("dhparams.pem"))
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
    assert_equal(CA_CERT.to_der, certs[0].to_der)
    assert_equal(SERVER_CERT.to_der, certs[1].to_der)
  rescue SystemCallError
    skip $!
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

    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.cert_store = TEST_STORE

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
