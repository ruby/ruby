# frozen_string_literal: true

require_relative "helper"
require "socket"
require "openssl"

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
      # TODO lookup ssl_server status and close it properly
      # @ssl_server.shutdown
      @ssl_server = nil
    end
    if @ssl_server_thread
      @ssl_server_thread.kill.join
      @ssl_server_thread = nil
    end
    super
  end

  def test_ssl_connection
    ssl_server = start_ssl_server
    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
    end
  end

  def test_ssl_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "client.pem")

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

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "invalid_client.pem")

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
    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
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
  ensure
    fetcher.close_all
    Gem.configuration = nil
  end

  def start_ssl_server(config = {})
    server = TCPServer.new(0)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert("ssl_cert.pem")
    ctx.key = key("ssl_key.pem")
    ctx.ca_file = File.join(__dir__, "ca_cert.pem")
    ctx.tmp_dh_callback = proc { TEST_KEY_DH2048 }
    ctx.verify_mode = config[:verify_mode] if config[:verify_mode]
    ssl_server = OpenSSL::SSL::SSLServer.new(server, ctx)
    @ssl_server_thread = Thread.new do
      loop do
        ssl_client = ssl_server.accept
        Thread.new(ssl_client) do |client|
          begin
            handle_request(client)
          rescue OpenSSL::SSL::SSLError => e
            warn "SSL error: #{e.message}"
          ensure
            client.close
          end
        end
      end
    end
    @ssl_server = ssl_server
    server
  end

  def handle_request(client)
    request = client.gets
    if request.start_with?("GET /yaml")
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/yaml\r\n\r\n--- true\n"
    elsif request.start_with?("GET /insecure_redirect")
      location = request.match(/to=([^ ]+)/)[1]
      client.print "HTTP/1.1 301 Moved Permanently\r\nLocation: #{location}\r\n\r\n"
    else
      client.print "HTTP/1.1 404 Not Found\r\n\r\n"
    end
  end

  def cert(filename)
    OpenSSL::X509::Certificate.new(File.read(File.join(__dir__, filename)))
  end

  def key(filename)
    OpenSSL::PKey::RSA.new(File.read(File.join(__dir__, filename)))
  end
end if Gem::HAVE_OPENSSL
