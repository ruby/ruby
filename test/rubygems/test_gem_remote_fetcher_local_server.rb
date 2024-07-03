# frozen_string_literal: true

require_relative "helper"

require "webrick"
require "webrick/https" if Gem::HAVE_OPENSSL

unless Gem::HAVE_OPENSSL
  warn "Skipping Gem::RemoteFetcher tests.  openssl not found."
end

require "rubygems/remote_fetcher"
require "rubygems/package"

# = Testing Proxy Settings
#
# These tests check the proper proxy server settings by running two
# web servers.  The web server at http://localhost:#{SERVER_PORT}
# represents the normal gem server and returns a gemspec with a rake
# version of 0.4.11.  The web server at http://localhost:#{PROXY_PORT}
# represents the proxy server and returns a different dataset where
# rake has version 0.4.2.  This allows us to detect which server is
# returning the data.
#
# Note that the proxy server is not a *real* proxy server.  But our
# software doesn't really care, as long as we hit the proxy URL when a
# proxy is configured.

class TestGemRemoteFetcherLocalServer < Gem::TestCase
  include Gem::DefaultUserInteraction

  SERVER_DATA = <<-EOY
--- !ruby/object:Gem::Cache
gems:
  rake-0.4.11: !ruby/object:Gem::Specification
    rubygems_version: "0.7"
    specification_version: 1
    name: rake
    version: !ruby/object:Gem::Version
      version: 0.4.11
    date: 2004-11-12
    summary: Ruby based make-like utility.
    require_paths:
      - lib
    author: Jim Weirich
    email: jim@weirichhouse.org
    homepage: http://rake.rubyforge.org
    description: Rake is a Make-like program implemented in Ruby. Tasks and dependencies are specified in standard Ruby syntax.
    autorequire:
    bindir: bin
    has_rdoc: true
    required_ruby_version: !ruby/object:Gem::Version::Requirement
      requirements:
        -
          - ">"
          - !ruby/object:Gem::Version
            version: 0.0.0
      version:
    platform: ruby
    files:
      - README
    test_files: []
    library_stubs:
    rdoc_options:
    extra_rdoc_files:
    executables:
      - rake
    extensions: []
    requirements: []
    dependencies: []
  EOY

  PROXY_DATA = SERVER_DATA.gsub(/0.4.11/, "0.4.2")

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
    @proxies = %w[https_proxy http_proxy HTTP_PROXY http_proxy_user HTTP_PROXY_USER http_proxy_pass HTTP_PROXY_PASS no_proxy NO_PROXY]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }

    super
    start_servers
    self.enable_yaml = true
    self.enable_zip = false

    base_server_uri = "http://localhost:#{normal_server_port}"
    @proxy_uri = "http://localhost:#{proxy_server_port}"

    @server_uri = base_server_uri + "/yaml"
    @server_z_uri = base_server_uri + "/yaml.Z"

    @cache_dir = File.join @gemhome, "cache"

    # TODO: why does the remote fetcher need it written to disk?
    @a1, @a1_gem = util_gem "a", "1" do |s|
      s.executables << "a_bin"
    end

    @a1.loaded_from = File.join(@gemhome, "specifications", @a1.full_name)

    Gem::RemoteFetcher.fetcher = nil
    @stub_ui = Gem::MockGemUi.new
    @fetcher = Gem::RemoteFetcher.fetcher
  end

  def teardown
    @fetcher.close_all
    stop_servers
    super
    Gem.configuration[:http_proxy] = nil
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def test_no_proxy
    use_ui @stub_ui do
      assert_data_from_server @fetcher.fetch_path(@server_uri)
      response = @fetcher.fetch_path(@server_uri, nil, true)
      assert_equal SERVER_DATA.size, response["content-length"].to_i
    end
  end

  def test_implicit_no_proxy
    use_ui @stub_ui do
      ENV["http_proxy"] = "http://fakeurl:12345"
      fetcher = Gem::RemoteFetcher.new :no_proxy
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_proxy
    use_ui @stub_ui do
      ENV["http_proxy"] = @proxy_uri
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_proxy fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_upper_case_proxy
    use_ui @stub_ui do
      ENV["HTTP_PROXY"] = @proxy_uri
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_proxy fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_proxy_no_env
    use_ui @stub_ui do
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_fetch_http_with_additional_headers
    ENV["http_proxy"] = @proxy_uri
    ENV["no_proxy"] = Gem::URI.parse(@server_uri).host
    fetcher = Gem::RemoteFetcher.new nil, nil, { "X-Captain" => "murphy" }
    @fetcher = fetcher
    assert_equal "murphy", fetcher.fetch_path(@server_uri)
  end

  def test_observe_no_proxy_env_single_host
    use_ui @stub_ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = Gem::URI.parse(@server_uri).host
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_observe_no_proxy_env_list
    use_ui @stub_ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = "fakeurl.com, #{Gem::URI.parse(@server_uri).host}"
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
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

  def assert_data_from_server(data)
    assert_match(/0\.4\.11/, data, "Data is not from server")
  end

  def assert_data_from_proxy(data)
    assert_match(/0\.4\.2/, data, "Data is not from proxy")
  end

  class NilLog < WEBrick::Log
    def log(level, data) # Do nothing
    end
  end

  private

  attr_reader :normal_server, :proxy_server
  attr_accessor :enable_zip, :enable_yaml

  def start_servers
    @normal_server ||= start_server(SERVER_DATA)
    @proxy_server  ||= start_server(PROXY_DATA)
    @enable_yaml = true
    @enable_zip = false
    @ssl_server = nil
    @ssl_server_thread = nil
  end

  def stop_servers
    if @normal_server
      @normal_server.kill.join
      @normal_server = nil
    end
    if @proxy_server
      @proxy_server.kill.join
      @proxy_server = nil
    end
    if @ssl_server
      @ssl_server.stop
      @ssl_server = nil
    end
    if @ssl_server_thread
      @ssl_server_thread.kill.join
      @ssl_server_thread = nil
    end
    WEBrick::Utils::TimeoutHandler.terminate
  end

  def normal_server_port
    @normal_server[:server].config[:Port]
  end

  def proxy_server_port
    @proxy_server[:server].config[:Port]
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

  def start_server(data)
    null_logger = NilLog.new
    s = WEBrick::HTTPServer.new(
      Port: 0,
      DocumentRoot: nil,
      Logger: null_logger,
      AccessLog: null_logger
    )
    s.mount_proc("/kill") {|_req, _res| s.shutdown }
    s.mount_proc("/yaml") do |req, res|
      if req["X-Captain"]
        res.body = req["X-Captain"]
      elsif @enable_yaml
        res.body = data
        res["Content-Type"] = "text/plain"
        res["content-length"] = data.size
      else
        res.status = "404"
        res.body = "<h1>NOT FOUND</h1>"
        res["Content-Type"] = "text/html"
      end
    end
    s.mount_proc("/yaml.Z") do |_req, res|
      if @enable_zip
        res.body = Zlib::Deflate.deflate(data)
        res["Content-Type"] = "text/plain"
      else
        res.status = "404"
        res.body = "<h1>NOT FOUND</h1>"
        res["Content-Type"] = "text/html"
      end
    end
    th = Thread.new do
      s.start
    rescue StandardError => ex
      abort "ERROR during server thread: #{ex.message}"
    ensure
      s.shutdown
    end
    th[:server] = s
    th
  end

  def cert(filename)
    OpenSSL::X509::Certificate.new(File.read(File.join(__dir__, filename)))
  end

  def key(filename)
    OpenSSL::PKey::RSA.new(File.read(File.join(__dir__, filename)))
  end
end if Gem::HAVE_OPENSSL
