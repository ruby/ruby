# frozen_string_literal: false
require 'rubygems/test_case'

require 'webrick'
begin
  require 'webrick/https'
rescue LoadError => e
  raise unless (e.respond_to?(:path) && e.path == 'openssl') ||
               e.message =~ / -- openssl$/
end

require 'rubygems/remote_fetcher'
require 'rubygems/package'
require 'minitest/mock'

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
    rubyforge_project: rake
    description: Rake is a Make-like program implemented in Ruby. Tasks and dependencies are specified in standard Ruby syntax.
    autorequire:
    default_executable: rake
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

  PROXY_DATA = SERVER_DATA.gsub(/0.4.11/, '0.4.2')

  DIR = File.expand_path(File.dirname(__FILE__))

  # Generated via:
  #   x = OpenSSL::PKey::DH.new(2048) # wait a while...
  #   x.to_s => pem
  #   x.priv_key.to_s => hex for OpenSSL::BN.new
  TEST_KEY_DH2048 =  OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA3Ze2EHSfYkZLUn557torAmjBgPsqzbodaRaGZtgK1gEU+9nNJaFV
G1JKhmGUiEDyIW7idsBpe4sX/Wqjnp48Lr8IeI/SlEzLdoGpf05iRYXC8Cm9o8aM
cfmVgoSEAo9YLBpzoji2jHkO7Q5IPt4zxbTdlmmGFLc/GO9q7LGHhC+rcMcNTGsM
49AnILNn49pq4Y72jSwdmvq4psHZwwFBbPwLdw6bLUDDCN90jfqvYt18muwUxDiN
NP0fuvVAIB158VnQ0liHSwcl6+9vE1mL0Jo/qEXQxl0+UdKDjaGfTsn6HIrwTnmJ
PeIQQkFng2VVot/WAQbv3ePqWq07g1BBcwIBAg==
-----END DH PARAMETERS-----
    _end_of_pem_

  TEST_KEY_DH2048.priv_key = OpenSSL::BN.new("108911488509734781344423639" \
     "5585749502236089033416160524030987005037540379474123441273555416835" \
     "4725688238369352738266590757370603937618499698665047757588998555345" \
     "3446251978586372525530219375408331096098220027413238477359960428372" \
     "0195464393332338164504352015535549496585792320286513563739305843396" \
     "9294344974028713065472959376197728193162272314514335882399554394661" \
     "5306385003430991221886779612878793446851681835397455333989268503748" \
     "7862488679178398716189205737442996155432191656080664090596502674943" \
     "7902481557157485795980326766117882761941455140582265347052939604724" \
     "964857770053363840471912215799994973597613931991572884", 16)

  def setup
    @proxies = %w[https_proxy http_proxy HTTP_PROXY http_proxy_user HTTP_PROXY_USER http_proxy_pass HTTP_PROXY_PASS no_proxy NO_PROXY]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }

    super
    self.class.start_servers
    self.class.enable_yaml = true
    self.class.enable_zip = false

    base_server_uri = "http://localhost:#{self.class.normal_server_port}"
    @proxy_uri = "http://localhost:#{self.class.proxy_server_port}"

    @server_uri = base_server_uri + "/yaml"
    @server_z_uri = base_server_uri + "/yaml.Z"

    # REFACTOR: copied from test_gem_dependency_installer.rb
    @gems_dir = File.join @tempdir, 'gems'
    @cache_dir = File.join @gemhome, "cache"
    FileUtils.mkdir @gems_dir

    # TODO: why does the remote fetcher need it written to disk?
    @a1, @a1_gem = util_gem 'a', '1' do |s| s.executables << 'a_bin' end
    @a1.loaded_from = File.join(@gemhome, 'specifications', @a1.full_name)

    Gem::RemoteFetcher.fetcher = nil

    @fetcher = Gem::RemoteFetcher.fetcher
  end

  def teardown
    @fetcher.close_all
    self.class.stop_servers
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
    proxy_uri = 'http://proxy.example.com'
    Gem.configuration[:http_proxy] = proxy_uri
    Gem::RemoteFetcher.fetcher = nil

    fetcher = Gem::RemoteFetcher.fetcher

    refute_nil fetcher
    assert_kind_of Gem::RemoteFetcher, fetcher
    assert_equal proxy_uri, fetcher.instance_variable_get(:@proxy).to_s
  end

  def test_fetch_size_bad_uri
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raises ArgumentError do
      fetcher.fetch_size 'gems.example.com/yaml'
    end

    assert_equal 'uri scheme is invalid: nil', e.message
  end

  def test_fetch_size_socket_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    def fetcher.request(uri, request_class, last_modified = nil)
      raise SocketError, "tarded"
    end

    uri = 'http://gems.example.com/yaml'
    e = assert_raises Gem::RemoteFetcher::FetchError do
      fetcher.fetch_size uri
    end

    assert_equal "SocketError: tarded (#{uri})", e.message
  end

  def test_no_proxy
    use_ui @ui do
      assert_data_from_server @fetcher.fetch_path(@server_uri)
      assert_equal SERVER_DATA.size, @fetcher.fetch_size(@server_uri)
    end
  end

  def test_api_endpoint
    uri = URI.parse "http://example.com/foo"
    target = MiniTest::Mock.new
    target.expect :target, "gems.example.com"

    dns = MiniTest::Mock.new
    dns.expect :getresource, target, [String, Object]

    fetch = Gem::RemoteFetcher.new nil, dns
    assert_equal URI.parse("http://gems.example.com/foo"), fetch.api_endpoint(uri)

    target.verify
    dns.verify
  end

  def test_api_endpoint_ignores_trans_domain_values
    uri = URI.parse "http://gems.example.com/foo"
    target = MiniTest::Mock.new
    target.expect :target, "blah.com"

    dns = MiniTest::Mock.new
    dns.expect :getresource, target, [String, Object]

    fetch = Gem::RemoteFetcher.new nil, dns
    assert_equal URI.parse("http://gems.example.com/foo"), fetch.api_endpoint(uri)

    target.verify
    dns.verify
  end

  def test_api_endpoint_ignores_trans_domain_values_that_starts_with_original
    uri = URI.parse "http://example.com/foo"
    target = MiniTest::Mock.new
    target.expect :target, "example.combadguy.com"

    dns = MiniTest::Mock.new
    dns.expect :getresource, target, [String, Object]

    fetch = Gem::RemoteFetcher.new nil, dns
    assert_equal URI.parse("http://example.com/foo"), fetch.api_endpoint(uri)

    target.verify
    dns.verify
  end

  def test_api_endpoint_ignores_trans_domain_values_that_end_with_original
    uri = URI.parse "http://example.com/foo"
    target = MiniTest::Mock.new
    target.expect :target, "badexample.com"

    dns = MiniTest::Mock.new
    dns.expect :getresource, target, [String, Object]

    fetch = Gem::RemoteFetcher.new nil, dns
    assert_equal URI.parse("http://example.com/foo"), fetch.api_endpoint(uri)

    target.verify
    dns.verify
  end

  def test_api_endpoint_timeout_warning
    uri = URI.parse "http://gems.example.com/foo"

    dns = MiniTest::Mock.new
    def dns.getresource arg, *rest
      raise Resolv::ResolvError.new('timeout!')
    end

    fetch = Gem::RemoteFetcher.new nil, dns
    begin
      old_verbose, Gem.configuration.verbose = Gem.configuration.verbose, 1
      endpoint = use_ui @ui do
        fetch.api_endpoint(uri)
      end
    ensure
      Gem.configuration.verbose = old_verbose
    end

    assert_equal uri, endpoint

    assert_equal "Getting SRV record failed: timeout!\n", @ui.output

    dns.verify
  end

  def test_cache_update_path
    uri = URI 'http://example/file'
    path = File.join @tempdir, 'file'

    fetcher = util_fuck_with_fetcher 'hello'

    data = fetcher.cache_update_path uri, path

    assert_equal 'hello', data

    assert_equal 'hello', File.read(path)
  end

  def test_cache_update_path_no_update
    uri = URI 'http://example/file'
    path = File.join @tempdir, 'file'

    fetcher = util_fuck_with_fetcher 'hello'

    data = fetcher.cache_update_path uri, path, false

    assert_equal 'hello', data

    refute_path_exists path
  end

  def util_fuck_with_fetcher data, blow = false
    fetcher = Gem::RemoteFetcher.fetcher
    fetcher.instance_variable_set :@test_data, data

    unless blow then
      def fetcher.fetch_path arg, *rest
        @test_arg = arg
        @test_data
      end
    else
      def fetcher.fetch_path arg, *rest
        # OMG I'm such an ass
        class << self; remove_method :fetch_path; end
        def self.fetch_path arg, *rest
          @test_arg = arg
          @test_data
        end

        raise Gem::RemoteFetcher::FetchError.new("haha!", nil)
      end
    end

    fetcher
  end

  def test_download
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, 'http://gems.example.com')
    assert_equal("http://gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_auth
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, 'http://user:password@gems.example.com')
    assert_equal("http://user:password@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_with_encoded_auth
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    a1_cache_gem = @a1.cache_file
    assert_equal a1_cache_gem, fetcher.download(@a1, 'http://user:%25pas%25sword@gems.example.com')
    assert_equal("http://user:%25pas%25sword@gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)
    assert File.exist?(a1_cache_gem)
  end

  def test_download_cached
    FileUtils.mv @a1_gem, @cache_dir

    inst = Gem::RemoteFetcher.fetcher

    assert_equal @a1.cache_file, inst.download(@a1, 'http://gems.example.com')
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
    space_path = File.join @tempdir, 'space path'
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
    a1_data = File.open @a1_gem, 'rb' do |fp|
      fp.read
    end

    fetcher = util_fuck_with_fetcher a1_data

    install_dir = File.join @tempdir, 'more_gems'

    a1_cache_gem = File.join install_dir, "cache", @a1.file_name
    FileUtils.mkdir_p(File.dirname(a1_cache_gem))
    actual = fetcher.download(@a1, 'http://gems.example.com', install_dir)

    assert_equal a1_cache_gem, actual
    assert_equal("http://gems.example.com/gems/a-1.gem",
                 fetcher.instance_variable_get(:@test_arg).to_s)

    assert File.exist?(a1_cache_gem)
  end

  unless win_platform? # File.chmod doesn't work
    def test_download_local_read_only
      FileUtils.mv @a1_gem, @tempdir
      local_path = File.join @tempdir, @a1.file_name
      inst = nil
      FileUtils.chmod 0555, @a1.cache_dir

      Dir.chdir @tempdir do
        inst = Gem::RemoteFetcher.fetcher
      end

      assert_equal(File.join(@tempdir, @a1.file_name),
                   inst.download(@a1, local_path))
    ensure
      FileUtils.chmod 0755, @a1.cache_dir
    end

    def test_download_read_only
      FileUtils.chmod 0555, @a1.cache_dir
      FileUtils.chmod 0555, @gemhome

      fetcher = util_fuck_with_fetcher File.read(@a1_gem)
      fetcher.download(@a1, 'http://gems.example.com')
      a1_cache_gem = File.join Gem.user_dir, "cache", @a1.file_name
      assert File.exist? a1_cache_gem
    ensure
      FileUtils.chmod 0755, @gemhome
      FileUtils.chmod 0755, @a1.cache_dir
    end
  end

  def test_download_platform_legacy
    original_platform = 'old-platform'

    e1, e1_gem = util_gem 'e', '1' do |s|
      s.platform = Gem::Platform::CURRENT
      s.instance_variable_set :@original_platform, original_platform
    end
    e1.loaded_from = File.join(@gemhome, 'specifications', e1.full_name)

    e1_data = nil
    File.open e1_gem, 'rb' do |fp|
      e1_data = fp.read
    end

    fetcher = util_fuck_with_fetcher e1_data, :blow_chunks

    e1_cache_gem = e1.cache_file

    assert_equal e1_cache_gem, fetcher.download(e1, 'http://gems.example.com')

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

    e = assert_raises ArgumentError do
      inst.download @a1, 'ftp://gems.rubyforge.org'
    end

    assert_equal 'unsupported URI scheme ftp', e.message
  end

  def test_download_to_cache
    @a2, @a2_gem = util_gem 'a', '2'

    util_setup_spec_fetcher @a1, @a2
    @fetcher.instance_variable_set :@a1, @a1
    @fetcher.instance_variable_set :@a2, @a2
    def @fetcher.fetch_path uri, mtime = nil, head = false
      case uri.request_uri
      when /#{@a1.spec_name}/ then
        Gem.deflate Marshal.dump @a1
      when /#{@a2.spec_name}/ then
        Gem.deflate Marshal.dump @a2
      else
        uri.to_s
      end
    end

    gem = Gem::RemoteFetcher.fetcher.download_to_cache dep 'a'

    assert_equal @a2.file_name, File.basename(gem)
  end

  def test_fetch_path_gzip
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      Gem.gzip 'foo'
    end

    assert_equal 'foo', fetcher.fetch_path(@uri + 'foo.gz')
  end

  def test_fetch_path_gzip_unmodified
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      nil
    end

    assert_equal nil, fetcher.fetch_path(@uri + 'foo.gz', Time.at(0))
  end

  def test_fetch_path_io_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(*)
      raise EOFError
    end

    url = 'http://example.com/uri'

    e = assert_raises Gem::RemoteFetcher::FetchError do
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

    url = 'http://example.com/uri'

    e = assert_raises Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_equal "SocketError: SocketError (#{url})", e.message
    assert_equal url, e.uri
  end

  def test_fetch_path_system_call_error
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime = nil, head = nil)
      raise Errno::ECONNREFUSED, 'connect(2)'
    end

    url = 'http://example.com/uri'

    e = assert_raises Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_match %r|ECONNREFUSED:.*connect\(2\) \(#{Regexp.escape url}\)\z|,
                 e.message
    assert_equal url, e.uri
  end

  def test_fetch_path_unmodified
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    def fetcher.fetch_http(uri, mtime, head = nil)
      nil
    end

    assert_equal nil, fetcher.fetch_path(URI.parse(@gem_repo), Time.at(0))
  end

  def test_implicit_no_proxy
    use_ui @ui do
      ENV['http_proxy'] = 'http://fakeurl:12345'
      fetcher = Gem::RemoteFetcher.new :no_proxy
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_proxy
    use_ui @ui do
      ENV['http_proxy'] = @proxy_uri
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_proxy fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_upper_case_proxy
    use_ui @ui do
      ENV['HTTP_PROXY'] = @proxy_uri
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_proxy fetcher.fetch_path(@server_uri)
    end
  end

  def test_implicit_proxy_no_env
    use_ui @ui do
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_fetch_http
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = 'http://gems.example.com/redirect'

    def fetcher.request(uri, request_class, last_modified = nil)
      url = 'http://gems.example.com/redirect'
      unless defined? @requested then
        @requested = true
        res = Net::HTTPMovedPermanently.new nil, 301, nil
        res.add_field 'Location', url
        res
      else
        res = Net::HTTPOK.new nil, 200, nil
        def res.body() 'real_path' end
        res
      end
    end

    data = fetcher.fetch_http URI.parse(url)

    assert_equal 'real_path', data
  end

  def test_fetch_http_redirects
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = 'http://gems.example.com/redirect'

    def fetcher.request(uri, request_class, last_modified = nil)
      url = 'http://gems.example.com/redirect'
      res = Net::HTTPMovedPermanently.new nil, 301, nil
      res.add_field 'Location', url
      res
    end

    e = assert_raises Gem::RemoteFetcher::FetchError do
      fetcher.fetch_http URI.parse(url)
    end

    assert_equal "too many redirects (#{url})", e.message
  end

  def test_fetch_http_with_additional_headers
    ENV["http_proxy"] = @proxy_uri
    ENV["no_proxy"] = URI::parse(@server_uri).host
    fetcher = Gem::RemoteFetcher.new nil, nil, {"X-Captain" => "murphy"}
    @fetcher = fetcher
    assert_equal "murphy", fetcher.fetch_path(@server_uri)
  end

  def test_fetch_s3
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = 's3://testuser:testpass@my-bucket/gems/specs.4.8.gz'
    $fetched_uri = nil

    def fetcher.request(uri, request_class, last_modified = nil)
      $fetched_uri = uri
      res = Net::HTTPOK.new nil, 200, nil
      def res.body() 'success' end
      res
    end

    def fetcher.s3_expiration
      1395098371
    end

    data = fetcher.fetch_s3 URI.parse(url)

    assert_equal 'https://my-bucket.s3.amazonaws.com/gems/specs.4.8.gz?AWSAccessKeyId=testuser&Expires=1395098371&Signature=eUTr7NkpZEet%2BJySE%2BfH6qukroI%3D', $fetched_uri.to_s
    assert_equal 'success', data
  ensure
    $fetched_uri = nil
  end

  def test_fetch_s3_no_creds
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = 's3://my-bucket/gems/specs.4.8.gz'
    e = assert_raises Gem::RemoteFetcher::FetchError do
      fetcher.fetch_s3 URI.parse(url)
    end

    assert_match "credentials needed", e.message
  end

  def test_observe_no_proxy_env_single_host
    use_ui @ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = URI::parse(@server_uri).host
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_observe_no_proxy_env_list
    use_ui @ui do
      ENV["http_proxy"] = @proxy_uri
      ENV["no_proxy"] = "fakeurl.com, #{URI::parse(@server_uri).host}"
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_data_from_server fetcher.fetch_path(@server_uri)
    end
  end

  def test_request_block
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    assert_throws :block_called do
      fetcher.request URI('http://example'), Net::HTTP::Get do |req|
        assert_kind_of Net::HTTPGenericRequest, req
        throw :block_called
      end
    end
  end

  def test_yaml_error_on_size
    use_ui @ui do
      self.class.enable_yaml = false
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_error { fetcher.size }
    end
  end

  def test_ssl_connection
    ssl_server = self.class.start_ssl_server
    temp_ca_cert = File.join(DIR, 'ca_cert.pem')
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_ssl_client_cert_auth_connection
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    ssl_server = self.class.start_ssl_server({
      :SSLVerifyClient =>
        OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT})

    temp_ca_cert = File.join(DIR, 'ca_cert.pem')
    temp_client_cert = File.join(DIR, 'client.pem')

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" +
      ":ssl_client_cert: #{temp_client_cert}\n") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_do_not_allow_invalid_client_cert_auth_connection
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    ssl_server = self.class.start_ssl_server({
      :SSLVerifyClient =>
        OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT})

    temp_ca_cert = File.join(DIR, 'ca_cert.pem')
    temp_client_cert = File.join(DIR, 'invalid_client.pem')

    with_configured_fetcher(
      ":ssl_ca_cert: #{temp_ca_cert}\n" +
      ":ssl_client_cert: #{temp_client_cert}\n") do |fetcher|
        assert_raises Gem::RemoteFetcher::FetchError do
          fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
        end
    end
  end

  def test_do_not_allow_insecure_ssl_connection_by_default
    ssl_server = self.class.start_ssl_server
    with_configured_fetcher do |fetcher|
      assert_raises Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
      end
    end
  end

  def test_ssl_connection_allow_verify_none
    ssl_server = self.class.start_ssl_server
    with_configured_fetcher(":ssl_verify_mode: 0") do |fetcher|
      fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/yaml")
    end
  end

  def test_do_not_follow_insecure_redirect
    ssl_server = self.class.start_ssl_server
    temp_ca_cert = File.join(DIR, 'ca_cert.pem'),
    with_configured_fetcher(":ssl_ca_cert: #{temp_ca_cert}") do |fetcher|
      assert_raises Gem::RemoteFetcher::FetchError do
        fetcher.fetch_path("https://localhost:#{ssl_server.config[:Port]}/insecure_redirect?to=#{@server_uri}")
      end
    end
  end

  def with_configured_fetcher(config_str = nil, &block)
    if config_str
      temp_conf = File.join @tempdir, '.gemrc'
      File.open temp_conf, 'w' do |fp|
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
    def log(level, data) #Do nothing
    end
  end

  class << self
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

    DIR = File.expand_path(File.dirname(__FILE__))

    def start_ssl_server(config = {})
      raise MiniTest::Skip, 'openssl not installed' unless
        defined?(OpenSSL::SSL)

      null_logger = NilLog.new
      server = WEBrick::HTTPServer.new({
        :Port => 0,
        :Logger => null_logger,
        :AccessLog => [],
        :SSLEnable => true,
        :SSLCACertificateFile => File.join(DIR, 'ca_cert.pem'),
        :SSLCertificate => cert('ssl_cert.pem'),
        :SSLPrivateKey => key('ssl_key.pem'),
        :SSLVerifyClient => nil,
        :SSLCertName => nil
      }.merge(config))
      server.mount_proc("/yaml") { |req, res|
        res.body = "--- true\n"
      }
      server.mount_proc("/insecure_redirect") { |req, res|
        res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, req.query['to'])
      }
      server.ssl_context.tmp_dh_callback = proc { TEST_KEY_DH2048 }
      t = Thread.new do
        begin
          server.start
        rescue Exception => ex
          abort ex.message
          puts "ERROR during server thread: #{ex.message}"
        ensure
          server.shutdown
        end
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

    private

    def start_server(data)
      null_logger = NilLog.new
      s = WEBrick::HTTPServer.new(
        :Port            => 0,
        :DocumentRoot    => nil,
        :Logger          => null_logger,
        :AccessLog       => null_logger
        )
      s.mount_proc("/kill") { |req, res| s.shutdown }
      s.mount_proc("/yaml") { |req, res|
        if req["X-Captain"]
          res.body = req["X-Captain"]
        elsif @enable_yaml
          res.body = data
          res['Content-Type'] = 'text/plain'
          res['content-length'] = data.size
        else
          res.status = "404"
          res.body = "<h1>NOT FOUND</h1>"
          res['Content-Type'] = 'text/html'
        end
      }
      s.mount_proc("/yaml.Z") { |req, res|
        if @enable_zip
          res.body = Zlib::Deflate.deflate(data)
          res['Content-Type'] = 'text/plain'
        else
          res.status = "404"
          res.body = "<h1>NOT FOUND</h1>"
          res['Content-Type'] = 'text/html'
        end
      }
      th = Thread.new do
        begin
          s.start
        rescue Exception => ex
          abort "ERROR during server thread: #{ex.message}"
        ensure
          s.shutdown
        end
      end
      th[:server] = s
      th
    end

    def cert(filename)
      OpenSSL::X509::Certificate.new(File.read(File.join(DIR, filename)))
    end

    def key(filename)
      OpenSSL::PKey::RSA.new(File.read(File.join(DIR, filename)))
    end
  end

  def test_correct_for_windows_path
    path = "/C:/WINDOWS/Temp/gems"
    assert_equal "C:/WINDOWS/Temp/gems", @fetcher.correct_for_windows_path(path)

    path = "/home/skillet"
    assert_equal "/home/skillet", @fetcher.correct_for_windows_path(path)
  end

end

