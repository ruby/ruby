require 'test/unit'
begin
  require 'http-access2'
rescue LoadError
end
require 'soap/rpc/driver'

if defined?(HTTPAccess2) and defined?(OpenSSL)

module SOAP; module SSL


class TestSSL < Test::Unit::TestCase
  PORT = 17171

  DIR = File.dirname(File.expand_path(__FILE__))
  require 'rbconfig'
  RUBY = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
  )

  def setup
    @url = "https://localhost:#{PORT}/hello"
    @serverpid = @client = nil
    @verify_callback_called = false
    setup_server
    setup_client
  end

  def teardown
    teardown_client
    teardown_server
  end

  def test_options
    cfg = @client.streamhandler.client.ssl_config
    assert_nil(cfg.client_cert)
    assert_nil(cfg.client_key)
    assert_nil(cfg.client_ca)
    assert_equal(OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT, cfg.verify_mode)
    assert_nil(cfg.verify_callback)
    assert_nil(cfg.timeout)
    assert_equal(OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_SSLv2, cfg.options)
    assert_equal("ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH", cfg.ciphers)
    assert_instance_of(OpenSSL::X509::Store, cfg.cert_store)
    # dummy call to ensure sslsvr initialization finished.
    assert_raise(OpenSSL::SSL::SSLError) do
      @client.hello_world("ssl client")
    end
  end

  def test_verification
    cfg = @client.options
    cfg["protocol.http.ssl_config.verify_callback"] = method(:verify_callback).to_proc
    @verify_callback_called = false
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    assert_equal("certificate verify failed", ssle.message)
    assert(@verify_callback_called)
    #
    cfg["protocol.http.ssl_config.client_cert"] = File.join(DIR, "client.cert")
    cfg["protocol.http.ssl_config.client_key"] = File.join(DIR, "client.key")
    @verify_callback_called = false
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    assert_equal("certificate verify failed", ssle.message)
    assert(@verify_callback_called)
    #
    cfg["protocol.http.ssl_config.ca_file"] = File.join(DIR, "ca.cert")
    @verify_callback_called = false
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    assert_equal("certificate verify failed", ssle.message)
    assert(@verify_callback_called)
    #
    cfg["protocol.http.ssl_config.ca_file"] = File.join(DIR, "subca.cert")
    @verify_callback_called = false
    assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
    assert(@verify_callback_called)
    #
    cfg["protocol.http.ssl_config.verify_depth"] = "1"
    @verify_callback_called = false
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    assert_equal("certificate verify failed", ssle.message)
    assert(@verify_callback_called)
    #
    cfg["protocol.http.ssl_config.verify_depth"] = ""
    cfg["protocol.http.ssl_config.cert_store"] = OpenSSL::X509::Store.new
    cfg["protocol.http.ssl_config.verify_mode"] = OpenSSL::SSL::VERIFY_PEER.to_s
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    assert_equal("certificate verify failed", ssle.message)
    #
    cfg["protocol.http.ssl_config.verify_mode"] = ""
    assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
  end

  def test_property
    testpropertyname = File.join(DIR, 'soapclient.properties')
    File.open(testpropertyname, "w") do |f|
      f <<<<__EOP__
protocol.http.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_PEER
# depth: 1 causes an error (intentional)
protocol.http.ssl_config.verify_depth = 1
protocol.http.ssl_config.client_cert = #{File.join(DIR, 'client.cert')}
protocol.http.ssl_config.client_key = #{File.join(DIR, 'client.key')}
protocol.http.ssl_config.ca_file = #{File.join(DIR, 'ca.cert')}
protocol.http.ssl_config.ca_file = #{File.join(DIR, 'subca.cert')}
protocol.http.ssl_config.ciphers = ALL
__EOP__
    end
    begin
      @client.loadproperty(testpropertyname)
      @client.options["protocol.http.ssl_config.verify_callback"] = method(:verify_callback).to_proc
      @verify_callback_called = false
      # NG with String
      ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
      assert_equal("certificate verify failed", ssle.message)
      assert(@verify_callback_called)
      # NG with Integer
      @client.options["protocol.http.ssl_config.verify_depth"] = 0
      ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
      assert_equal("certificate verify failed", ssle.message)
      assert(@verify_callback_called)
      # OK with empty
      @client.options["protocol.http.ssl_config.verify_depth"] = ""
      @verify_callback_called = false
      assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
      assert(@verify_callback_called)
      # OK with nil
      @client.options["protocol.http.ssl_config.verify_depth"] = nil
      @verify_callback_called = false
      assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
      assert(@verify_callback_called)
      # OK with String
      @client.options["protocol.http.ssl_config.verify_depth"] = "3"
      @verify_callback_called = false
      assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
      assert(@verify_callback_called)
      # OK with Integer
      @client.options["protocol.http.ssl_config.verify_depth"] = 3
      @verify_callback_called = false
      assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
      assert(@verify_callback_called)
    ensure
      File.unlink(testpropertyname)
    end
  end

  def test_ciphers
    cfg = @client.options
    cfg["protocol.http.ssl_config.client_cert"] = File.join(DIR, 'client.cert')
    cfg["protocol.http.ssl_config.client_key"] = File.join(DIR, 'client.key')
    cfg["protocol.http.ssl_config.ca_file"] = File.join(DIR, "ca.cert")
    cfg["protocol.http.ssl_config.ca_file"] = File.join(DIR, "subca.cert")
    #cfg.timeout = 123
    cfg["protocol.http.ssl_config.ciphers"] = "!ALL"
    #
    ssle = assert_raise(OpenSSL::SSL::SSLError) {@client.hello_world("ssl client")}
    # depends on OpenSSL version. (?:0.9.8|0.9.7)
    assert_match(/\A(?:SSL_CTX_set_cipher_list:: no cipher match|no ciphers available)\z/, ssle.message)
    #
    cfg["protocol.http.ssl_config.ciphers"] = "ALL"
    assert_equal("Hello World, from ssl client", @client.hello_world("ssl client"))
  end

private

  def q(str)
    %Q["#{str}"]
  end

  def setup_server
    svrcmd = "#{q(RUBY)} "
    #svrcmd << "-d " if $DEBUG
    svrcmd << File.join(DIR, "sslsvr.rb")
    svrout = IO.popen(svrcmd)
    @serverpid = Integer(svrout.gets.chomp)
  end

  def setup_client
    @client = SOAP::RPC::Driver.new(@url, 'urn:ssltst')
    @client.add_method("hello_world", "from")
  end

  def teardown_server
    if @serverpid
      Process.kill('KILL', @serverpid)
      Process.waitpid(@serverpid)
    end
  end

  def teardown_client
    @client.reset_stream if @client
  end

  def verify_callback(ok, cert)
    @verify_callback_called = true
    p ["client", ok, cert] if $DEBUG
    ok
  end
end


end; end

end
