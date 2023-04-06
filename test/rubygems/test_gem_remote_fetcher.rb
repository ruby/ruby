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

class TestGemRemoteFetcher < Gem::TestCase
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

  def test_self_fetcher
    fetcher = Gem::RemoteFetcher.fetcher
    refute_nil fetcher
    assert_kind_of Gem::RemoteFetcher, fetcher
  end

  def test_self_fetcher_with_proxy
    proxy_uri = "http://proxy.example.com"
    Gem.configuration[:http_proxy] = proxy_uri
    Gem::RemoteFetcher.fetcher = nil

    fetcher = Gem::RemoteFetcher.fetcher

    refute_nil fetcher
    assert_kind_of Gem::RemoteFetcher, fetcher
    assert_equal proxy_uri, fetcher.instance_variable_get(:@proxy).to_s
  end

  def test_fetch_path_bad_uri
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raise ArgumentError do
      @fetcher.fetch_path("gems.example.com/yaml", nil, true)
    end

    assert_equal "uri scheme is invalid: nil", e.message
  end

  def test_no_proxy
    use_ui @stub_ui do
      assert_data_from_server @fetcher.fetch_path(@server_uri)
      response = @fetcher.fetch_path(@server_uri, nil, true)
      assert_equal SERVER_DATA.size, response["content-length"].to_i
    end
  end

  def test_cache_update_path
    uri = URI "http://example/file"
    path = File.join @tempdir, "file"

    fetcher = util_fuck_with_fetcher "hello"

    data = fetcher.cache_update_path uri, path

    assert_equal "hello", data

    assert_equal "hello", File.read(path)
  end

  def test_cache_update_path_with_utf8_internal_encoding
    with_internal_encoding("UTF-8") do
      uri = URI "http://example/file"
      path = File.join @tempdir, "file"
      data = String.new("\xC8").force_encoding(Encoding::BINARY)

      fetcher = util_fuck_with_fetcher data

      written_data = fetcher.cache_update_path uri, path

      assert_equal data, written_data
      assert_equal data, File.binread(path)
    end
  end

  def test_cache_update_path_no_update
    uri = URI "http://example/file"
    path = File.join @tempdir, "file"

    fetcher = util_fuck_with_fetcher "hello"

    data = fetcher.cache_update_path uri, path, false

    assert_equal "hello", data

    assert_path_not_exist path
  end

  def util_fuck_with_fetcher(data, blow = false)
    fetcher = Gem::RemoteFetcher.fetcher
    fetcher.instance_variable_set :@test_data, data

    if blow
      def fetcher.fetch_path(arg, *rest)
        # OMG I'm such an ass
        class << self; remove_method :fetch_path; end
        def self.fetch_path(arg, *rest)
          @test_arg = arg
          @test_data
        end

        raise Gem::RemoteFetcher::FetchError.new("haha!", "")
      end
    else
      def fetcher.fetch_path(arg, *rest)
        @test_arg = arg
        @test_data
      end
    end

    fetcher
  end

  def test_download
    a1_data = nil
    File.open @a1_gem, "rb" do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, "http://gems.example.com")
    assert_equal("http://gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_auth
    a1_data = nil
    File.open @a1_gem, "rb" do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, "http://user:password@gems.example.com")
    assert_equal("http://user:password@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_token
    a1_data = nil
    File.open @a1_gem, "rb" do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, "http://token@gems.example.com")
    assert_equal("http://token@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_x_oauth_basic
    a1_data = nil
    File.open @a1_gem, "rb" do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, "http://token:x-oauth-basic@gems.example.com")
    assert_equal("http://token:x-oauth-basic@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_encoded_auth
    a1_data = nil
    File.open @a1_gem, "rb" do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, "http://user:%25pas%25sword@gems.example.com")
    assert_equal("http://user:%25pas%25sword@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_cached
    FileUtils.mv @a1_gem, @cache_dir

    inst = Gem::RemoteFetcher.fetcher

    assert_equal @a1.cache_file, inst.download(@a1, "http://gems.example.com")
  end

  def test_download_local
    FileUtils.mv @a1_gem, @tempdir
    local_path = File.join @tempdir, @a1.file_name
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::RemoteFetcher.fetcher
    end

    assert_equal @a1.cache_file, inst.download(@a1, local_path)
  end

  def test_download_local_space
    space_path = File.join @tempdir, "space path"
    FileUtils.mkdir space_path
    FileUtils.mv @a1_gem, space_path
    local_path = File.join space_path, @a1.file_name
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::RemoteFetcher.fetcher
    end

    assert_equal @a1.cache_file, inst.download(@a1, local_path)
  end

  def test_download_install_dir
    a1_data = File.open @a1_gem, "rb", &:read

    fetcher = util_fuck_with_fetcher a1_data

    install_dir = File.join @tempdir, "more_gems"

    a1_cache_gem = File.join install_dir, "cache", @a1.file_name
    FileUtils.mkdir_p(File.dirname(a1_cache_gem))
    actual = fetcher.download(@a1, "http://gems.example.com", install_dir)

    assert_equal a1_cache_gem, actual
    assert_equal("http://gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)

    assert File.exist?(a1_cache_gem)
  end

  unless Gem.win_platform? || Process.uid.zero? # File.chmod doesn't work
    def test_download_local_read_only
      FileUtils.mv @a1_gem, @tempdir
      local_path = File.join @tempdir, @a1.file_name
      inst = nil
      FileUtils.chmod 0555, @a1.cache_dir
      begin
        FileUtils.mkdir_p File.join(Gem.user_dir, "cache")
      rescue StandardError
        nil
      end
      FileUtils.chmod 0555, File.join(Gem.user_dir, "cache")

      Dir.chdir @tempdir do
        inst = Gem::RemoteFetcher.fetcher
      end

      assert_equal(File.join(@tempdir, @a1.file_name),
                   inst.download(@a1, local_path))
    ensure
      FileUtils.chmod 0755, File.join(Gem.user_dir, "cache")
      FileUtils.chmod 0755, @a1.cache_dir
    end

    def test_download_read_only
      FileUtils.chmod 0555, @a1.cache_dir
      FileUtils.chmod 0555, @gemhome

      fetcher = util_fuck_with_fetcher File.read(@a1_gem)
      fetcher.download(@a1, "http://gems.example.com")
      a1_cache_gem = File.join Gem.user_dir, "cache", @a1.file_name
      assert File.exist? a1_cache_gem
    ensure
      FileUtils.chmod 0755, @gemhome
      FileUtils.chmod 0755, @a1.cache_dir
    end
  end

  def test_download_platform_legacy
    original_platform = "old-platform"

    e1, e1_gem = util_gem "e", "1" do |s|
      s.platform = Gem::Platform::CURRENT
      s.instance_variable_set :@original_platform, original_platform
    end
    e1.loaded_from = File.join(@gemhome, "specifications", e1.full_name)

    e1_data = nil
    File.open e1_gem, "rb" do |fp|
      e1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher e1_data, :blow_chunks

    e1_cache_gem = e1.cache_file

    assert_equal e1_cache_gem, fetcher.download(e1, "http://gems.example.com")

    assert_equal("http://gems.example.com/gems/#{e1.original_name}.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(e1_cache_gem)
  end

  def test_download_same_file
    FileUtils.mv @a1_gem, @tempdir
    local_path = File.join @tempdir, @a1.file_name
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::RemoteFetcher.fetcher
    end

    cache_path = @a1.cache_file
    FileUtils.mv local_path, cache_path

    gem = Gem::Package.new cache_path

    assert_equal cache_path, inst.download(gem.spec, cache_path)
  end

  def test_download_unsupported
    inst = Gem::RemoteFetcher.fetcher

    e = assert_raise ArgumentError do
      inst.download @a1, "ftp://gems.rubyforge.org"
    end

    assert_equal "unsupported URI scheme ftp", e.message
  end

  def test_download_to_cache
    @a2, @a2_gem = util_gem "a", "2"

    util_setup_spec_fetcher @a1, @a2
    @fetcher.instance_variable_set :@a1, @a1
    @fetcher.instance_variable_set :@a2, @a2
    def @fetcher.fetch_path(uri, mtime = nil, head = false)
      case uri.request_uri
      when /#{@a1.spec_name}/ then
        Gem.deflate Marshal.dump @a1
      when /#{@a2.spec_name}/ then
        Gem.deflate Marshal.dump @a2
      else
        uri.to_s
      end
    end

    gem = Gem::RemoteFetcher.fetcher.download_to_cache dep "a"

    assert_equal @a2.file_name, File.basename(gem)
  end

  def test_fetch_path_gzip
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      Gem::Util.gzip "foo"
    end

    assert_equal "foo", fetcher.fetch_path(@uri + "foo.gz")
  end

  def test_fetch_path_gzip_unmodified
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      nil
    end

    assert_nil fetcher.fetch_path(@uri + "foo.gz", Time.at(0))
  end

  def test_fetch_path_io_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(*)
      raise EOFError
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_equal "EOFError: EOFError (#{url})", e.message
    assert_equal url, e.uri
  end

  def test_fetch_path_socket_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      raise SocketError
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_equal "SocketError: SocketError (#{url})", e.message
    assert_equal url, e.uri
  end

  def test_fetch_path_system_call_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime = nil, head = nil)
      raise Errno::ECONNREFUSED, "connect(2)"
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_match(/ECONNREFUSED:.*connect\(2\) \(#{Regexp.escape url}\)\z/,
                 e.message)
    assert_equal url, e.uri
  end

  def test_fetch_path_timeout_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime = nil, head = nil)
      raise Timeout::Error, "timed out"
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_match(/Timeout::Error: timed out \(#{Regexp.escape url}\)\z/,
                 e.message)
    assert_equal url, e.uri
  end

  def test_fetch_path_getaddrinfo_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime = nil, head = nil)
      raise SocketError, "getaddrinfo: nodename nor servname provided"
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_match(/SocketError: getaddrinfo: nodename nor servname provided \(#{Regexp.escape url}\)\z/,
                 e.message)
    assert_equal url, e.uri
  end

  def test_fetch_path_openssl_ssl_sslerror
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime = nil, head = nil)
      raise OpenSSL::SSL::SSLError
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_equal "OpenSSL::SSL::SSLError: OpenSSL::SSL::SSLError (#{url})", e.message
    assert_equal url, e.uri
  end

  def test_fetch_path_unmodified
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      nil
    end

    assert_nil fetcher.fetch_path(URI.parse(@gem_repo), Time.at(0))
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

  def test_fetch_http
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      url = "http://gems.example.com/redirect"
      if defined? @requested
        res = Net::HTTPOK.new nil, 200, nil
        def res.body
          "real_path"
        end
      else
        @requested = true
        res = Net::HTTPMovedPermanently.new nil, 301, nil
        res.add_field "Location", url
      end
      res
    end

    data = fetcher.fetch_http URI.parse(url)

    assert_equal "real_path", data
  end

  def test_fetch_http_redirects
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      url = "http://gems.example.com/redirect"
      res = Net::HTTPMovedPermanently.new nil, 301, nil
      res.add_field "Location", url
      res
    end

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_http URI.parse(url)
    end

    assert_equal "too many redirects (#{url})", e.message
  end

  def test_fetch_http_redirects_without_location
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      res = Net::HTTPMovedPermanently.new nil, 301, nil
      res
    end

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_http URI.parse(url)
    end

    assert_equal "redirecting but no redirect location was given (#{url})", e.message
  end

  def test_fetch_http_with_additional_headers
    ENV["http_proxy"] = @proxy_uri
    ENV["no_proxy"] = URI.parse(@server_uri).host
    fetcher = Gem::RemoteFetcher.new nil, nil, { "X-Captain" => "murphy" }
    @fetcher = fetcher
    assert_equal "murphy", fetcher.fetch_path(@server_uri)
  end

  def assert_fetch_s3(url, signature, token=nil, region="us-east-1", instance_profile_json=nil)
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    $fetched_uri = nil
    $instance_profile = instance_profile_json

    def fetcher.request(uri, request_class, last_modified = nil)
      $fetched_uri = uri
      res = Net::HTTPOK.new nil, 200, nil
      def res.body
        "success"
      end
      res
    end

    def fetcher.s3_uri_signer(uri)
      require "json"
      s3_uri_signer = Gem::S3URISigner.new(uri)
      def s3_uri_signer.ec2_metadata_credentials_json
        JSON.parse($instance_profile)
      end
      # Running sign operation to make sure uri.query is not mutated
      s3_uri_signer.sign
      raise "URI query is not empty: #{uri.query}" unless uri.query.nil?
      s3_uri_signer
    end

    data = fetcher.fetch_s3 URI.parse(url)

    assert_equal "https://my-bucket.s3.#{region}.amazonaws.com/gems/specs.4.8.gz?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=testuser%2F20190624%2F#{region}%2Fs3%2Faws4_request&X-Amz-Date=20190624T050641Z&X-Amz-Expires=86400#{token ? "&X-Amz-Security-Token=" + token : ""}&X-Amz-SignedHeaders=host&X-Amz-Signature=#{signature}", $fetched_uri.to_s
    assert_equal "success", data
  ensure
    $fetched_uri = nil
  end

  def test_fetch_s3_config_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :id => "testuser", :secret => "testpass" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_config_creds_with_region
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :id => "testuser", :secret => "testpass", :region => "us-west-2" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_config_creds_with_token
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :id => "testuser", :secret => "testpass", :security_token => "testtoken" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = nil
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "env" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds_with_region
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = nil
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "env", :region => "us-west-2" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds_with_token
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = "testtoken"
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "env" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_url_creds
    url = "s3://testuser:testpass@my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
    end
  end

  def test_fetch_s3_instance_profile_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b", nil, "us-east-1",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_instance_profile_creds_with_region
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "instance_profile", :region => "us-west-2" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_instance_profile_creds_with_token
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :provider => "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken", "us-east-1",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass", "Token": "testtoken"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def refute_fetch_s3(url, expected_message)
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_s3 URI.parse(url)
    end

    assert_match expected_message, e.message
  end

  def test_fetch_s3_no_source_key
    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "no s3_source key exists in .gemrc"
  end

  def test_fetch_s3_no_host
    Gem.configuration[:s3_source] = {
      "my-bucket" => { :id => "testuser", :secret => "testpass" },
    }

    url = "s3://other-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "no key for host other-bucket in s3_source in .gemrc"
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_id
    Gem.configuration[:s3_source] = { "my-bucket" => { :secret => "testpass" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "s3_source for my-bucket missing id or secret"
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_secret
    Gem.configuration[:s3_source] = { "my-bucket" => { :id => "testuser" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "s3_source for my-bucket missing id or secret"
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_observe_no_proxy_env_single_host
    use_ui @stub_ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = URI.parse(@server_uri).host
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_observe_no_proxy_env_list
    use_ui @stub_ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = "fakeurl.com, #{URI.parse(@server_uri).host}"
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_request_block
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    assert_throws :block_called do
      fetcher.request URI("http://example"), Net::HTTP::Get do |req|
        assert_kind_of Net::HTTPGenericRequest, req
        throw :block_called
      end
    end
  end

  def test_yaml_error_on_size
    use_ui @stub_ui do
      self.enable_yaml = false
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_error { fetcher.size }
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
      { :SSLVerifyClient => OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" +
      ":ssl_client_cert: #{temp_client_cert}\n"
    ) do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_do_not_allow_invalid_client_cert_auth_connection
    ssl_server = start_ssl_server(
      { :SSLVerifyClient => OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT }
    )

    temp_ca_cert = File.join(__dir__, "ca_cert.pem")
    temp_client_cert = File.join(__dir__, "invalid_client.pem")

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" +
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

  def assert_error(exception_class=Exception)
    got_exception = false

    begin
      yield
    rescue exception_class
      got_exception = true
    end

    assert got_exception, "Expected exception conforming to #{exception_class}"
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
    utils = WEBrick::Utils # TimeoutHandler is since 1.9
    utils::TimeoutHandler.terminate if defined?(utils::TimeoutHandler.terminate)
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
      :Port => 0,
      :Logger => null_logger,
      :AccessLog => [],
      :SSLEnable => true,
      :SSLCACertificateFile => File.join(__dir__, "ca_cert.pem"),
      :SSLCertificate => cert("ssl_cert.pem"),
      :SSLPrivateKey => key("ssl_key.pem"),
      :SSLVerifyClient => nil,
      :SSLCertName => nil,
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
      :Port => 0,
      :DocumentRoot => nil,
      :Logger => null_logger,
      :AccessLog => null_logger
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
