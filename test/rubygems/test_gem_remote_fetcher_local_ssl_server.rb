# frozen_string_literal: true

require_relative "helper"

require "webrick/https" if Gem::HAVE_OPENSSL

unless Gem::HAVE_OPENSSL
  warn "Skipping Gem::RemoteFetcher tests.  openssl not found."
end

require "rubygems/remote_fetcher"
require "rubygems/package"

class TestGemRemoteFetcherLocalSSLServer < Gem::TestCase
  include Gem::DefaultUserInteraction

  # Generated via:
  #   x = OpenSSL::PKey::DH.new(2048) # wait a while...
  #   x.to_s => pem
  TEST_KEY_DH2048 = OpenSSL::PKey::DH.new <<-_END_OF_PEM_
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA3Ze2EHSfYkZLUn557torAmjBgPsqzbodaRaGZtgK1gEU+9nNJaFV
G1JKhmGUiEDyIW7idsBpe4sX/Wqjnp48Lr8IeI/SlEzLdoGpf05iRYXC8Cm9o8aM
cfmVgoSEAo9YLBpzoji2jHkO7Q5IPt4zxbTdlmmGFLc/GO9q7LGHhC+rcMcNTGsM
49AnILNn49pq4Y72jSwdmvq4psHZwwFBbPwLdw6bLUDDCN90jfqvYt18muwUxDiN
NP0fuvVAIB158VnQ0liHSwcl6+9vE1mL0Jo/qEXQxl0+UdKDjaGfTsn6HIrwTnmJ
PeIQQkFng2VVot/WAQbv3ePqWq07g1BBcwIBAg==
-----END DH PARAMETERS-----
    _END_OF_PEM_

  def setup
    super

    @ssl_server = nil
    @ssl_server_thread = nil
  end

  def teardown
    if @ssl_server
      @ssl_server.stop
      @ssl_server = nil
    end
    if @ssl_server_thread
      @ssl_server_thread.kill.join
      @ssl_server_thread = nil
    end
    WEBrick::Utils::TimeoutHandler.terminate

    super
  end

  def test_ssl_connection
    ssl_server = start_ssl_server
    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_ssl_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { SSLVerifyClient: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" \
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_do_not_allow_invalid_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { SSLVerifyClient: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "invalid_client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" \
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
      end
    end
  end

  def test_do_not_allow_insecure_ssl_connection_by_default
    ssl_server = start_ssl_server
    with_configured_fetcher do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
      end
    end
  end

  def test_ssl_connection_allow_verify_none
    ssl_server = start_ssl_server
    with_configured_fetcher(":ssl_verify_mode: 0") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_do_not_follow_insecure_redirect
    @server_uri = "http://example.com"
    ssl_server = start_ssl_server
    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    expected_error_message =
      "redirecting to non-https resource: #{@server_uri} (https://localhost:#{ssl_server.config[:Port]}/insecure_redirect?to=#{@server_uri})"

    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      err = assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/insecure_redirect?to=#{@server_uri}")
      end

      assert_equal(err.message, expected_error_message)
    end
  end

  def test_nil_ca_cert
    ssl_server = start_ssl_server
    temp_ca_cert = nil

    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}")
      end
    end
  end

  private

  def with_configured_fetcher(config_str = nil, &block)
    if config_str
      temp_conf = File.join @tempdir, ".gemrc"
      File.open temp_conf, "w" do |fp|
        fp.puts config_str
      end
      Gem.configuration = Gem::ConfigFile.new %W[--config-file #{temp_conf}]
    end
    fetcher = Gem::RemoteFetcher.new
    yield fetcher
  ensure
    fetcher.close_all
    Gem.configuration = nil
  end

  class NilLog < WEBrick::Log
    def log(level, data) # Do nothing
    end
  end

  def start_ssl_server(config = {})
    pend "starting this test server fails randomly on jruby" if Gem.java_platform?

    null_logger = NilLog.new
    server = WEBrick::HTTPServer.new({
      Port: 0,
      Logger: null_logger,
      AccessLog: [],
      SSLEnable: true,
      SSLCACertificateFile: File.join(__dir__, "ca_cert.pem"),
      SSLCertificate: cert("ssl_cert.pem"),
      SSLPrivateKey: key("ssl_key.pem"),
      SSLVerifyClient: nil,
      SSLCertName: nil,
    }.merge(config))
    server.mount_proc("/yaml") do |_req, res|
      res.body = "--- true\n"
    end
    server.mount_proc("/insecure_redirect") do |req, res|
      res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, req.query["to"])
    end
    server.ssl_context.tmp_dh_callback = proc { TEST_KEY_DH2048 }
    t = Thread.new do
      server.start
    rescue StandardError => ex
      puts "ERROR during server thread: #{ex.message}"
      raise
    ensure
      server.shutdown
    end
    while server.status != :Running
      sleep 0.1
      unless t.alive?
        t.join
        raise
      end
    end
    @ssl_server = server
    @ssl_server_thread = t
    server
  end

  def cert(filename)
    OpenSSL::X509::Certificate.new(File.read(File.join(__dir__, filename)))
  end

  def key(filename)
    OpenSSL::PKey::RSA.new(File.read(File.join(__dir__, filename)))
  end
end if Gem::HAVE_OPENSSL
