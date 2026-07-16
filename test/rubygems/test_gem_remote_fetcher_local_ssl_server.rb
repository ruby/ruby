# frozen_string_literal: true

require_relative "helper"
require_relative "local_ssl_server_utilities"

unless Gem::HAVE_OPENSSL
  warn "Skipping Gem::RemoteFetcher tests.  openssl not found."
end

require "rubygems/remote_fetcher"
require "rubygems/package"

class TestGemRemoteFetcherLocalSSLServer < Gem::TestCase
  include Gem::DefaultUserInteraction
  include Gem::LocalSSLServerUtilities

  def setup
    super
    initialize_ssl_server
  end

  def teardown
    stop_ssl_server
    super
  end

  def test_ssl_connection
    ssl_server = start_ssl_server
    temp_ca_cert = File.join(certs_dir, "ca_cert.pem")
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_pqc_ssl_connection
    omit_unless_support_pqc

    ssl_server = start_ssl_server(mode: :pqc)
    temp_ca_cert = File.join(certs_dir, "mldsa65_ca_cert.pem")
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_ssl_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(certs_dir, "ca_cert.pem")
    temp_client_cert = File.join(certs_dir, "client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" \
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_pqc_ssl_client_cert_auth_connection
    omit_unless_support_pqc

    ssl_server = start_ssl_server(
      mode: :pqc,
      verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    )

    temp_ca_cert = File.join(certs_dir, "mldsa65_ca_cert.pem")
    temp_client_cert = File.join(certs_dir, "mldsa65_client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" \
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_do_not_allow_invalid_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(certs_dir, "ca_cert.pem")
    temp_client_cert = File.join(certs_dir, "invalid_client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" \
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
      end
    end
  end

  def test_do_not_allow_insecure_ssl_connection_by_default
    ssl_server = start_ssl_server
    with_configured_fetcher do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
      end
    end
  end

  def test_ssl_connection_allow_verify_none
    ssl_server = start_ssl_server
    with_configured_fetcher(":ssl_verify_mode: 0") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_do_not_follow_insecure_redirect
    @server_uri = "http://example.com"
    ssl_server = start_ssl_server
    temp_ca_cert = File.join(certs_dir, "ca_cert.pem")
    expected_error_message =
      "redirecting to non-https resource: #{@server_uri} (https://localhost:#{ssl_server.addr[1]}/insecure_redirect?to=#{@server_uri})"

    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      err = assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/insecure_redirect?to=#{@server_uri}")
      end

      assert_equal(err.message, expected_error_message)
    end
  end

  def test_nil_ca_cert
    ssl_server = start_ssl_server
    temp_ca_cert = nil

    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      assert_raise Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}")
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
    sleep 0.5 unless RUBY_PLATFORM.match?(/mswin|mingw/)
  ensure
    fetcher.close_all
    Gem.configuration = nil
  end

  def omit_unless_support_pqc
    without_pqc_support do |message|
      omit message
    end
  end
end if Gem::HAVE_OPENSSL
