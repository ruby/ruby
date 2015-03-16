require "test/unit"
begin
  require 'net/https'
  require 'stringio'
  require 'timeout'
  require File.expand_path("../../openssl/utils", File.dirname(__FILE__))
  require File.expand_path("utils", File.dirname(__FILE__))
rescue LoadError
  # should skip this test
end

class TestNetHTTPS < Test::Unit::TestCase
  include TestNetHTTPUtils

  subject = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
  exts = [
    ["keyUsage", "keyEncipherment,digitalSignature", true],
  ]
  key = OpenSSL::TestUtils::TEST_KEY_RSA1024
  cert = OpenSSL::TestUtils.issue_cert(
    subject, key, 1, Time.now, Time.now + 3600, exts,
    nil, nil, OpenSSL::Digest::SHA1.new
  )

  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'ssl_enable' => true,
    'ssl_certificate' => cert,
    'ssl_private_key' => key,
  }

  def test_get
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      store_ctx.current_cert.to_der == config('ssl_certificate').to_der
    end
    http.request_get("/") {|res|
      assert_equal($test_net_http_data, res.body)
    }
  rescue SystemCallError
    skip $!
  end

  def test_post
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      store_ctx.current_cert.to_der == config('ssl_certificate').to_der
    end
    data = config('ssl_private_key').to_der
    http.request_post("/", data, {'content-type' => 'application/x-www-form-urlencoded'}) {|res|
      assert_equal(data, res.body)
    }
  rescue SystemCallError
    skip $!
  end

  def test_session_reuse
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      store_ctx.current_cert.to_der == config('ssl_certificate').to_der
    end

    http.start
    http.get("/")
    http.finish

    http.start
    http.get("/")
    http.finish # three times due to possible bug in OpenSSL 0.9.8

    sid = http.instance_variable_get(:@ssl_session).id

    http.start
    http.get("/")

    socket = http.instance_variable_get(:@socket).io

    assert socket.session_reused?

    assert_equal sid, http.instance_variable_get(:@ssl_session).id

    http.finish
  rescue SystemCallError
    skip $!
  end

  def test_session_reuse_but_expire
    http = Net::HTTP.new("localhost", config("port"))
    http.use_ssl = true
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      store_ctx.current_cert.to_der == config('ssl_certificate').to_der
    end

    http.ssl_timeout = -1
    http.start
    http.get("/")
    http.finish

    sid = http.instance_variable_get(:@ssl_session).id

    http.start
    http.get("/")

    socket = http.instance_variable_get(:@socket).io
    assert_equal false, socket.session_reused?

    assert_not_equal sid, http.instance_variable_get(:@ssl_session).id

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
    http = Net::HTTP.new("127.0.0.1", config("port"))
    http.use_ssl = true
    http.verify_callback = Proc.new do |preverify_ok, store_ctx|
      store_ctx.current_cert.to_der == config('ssl_certificate').to_der
    end
    ex = assert_raise(OpenSSL::SSL::SSLError){
      http.request_get("/") {|res| }
    }
    assert_match(/hostname \"127.0.0.1\" does not match/, ex.message)
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
end if defined?(OpenSSL::TestUtils)
