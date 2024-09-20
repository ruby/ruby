# frozen_string_literal: true

require_relative "helper"

require "rubygems/remote_fetcher"
require "rubygems/package"

class TestGemRemoteFetcher < Gem::TestCase
  include Gem::DefaultUserInteraction

  def setup
    super

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
  ensure
    Gem.configuration[:http_proxy] = nil
  end

  def test_fetch_path_bad_uri
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raise ArgumentError do
      @fetcher.fetch_path("gems.example.com/yaml", nil, true)
    end

    assert_equal "uri scheme is invalid: nil", e.message
  end

  def test_cache_update_path
    uri = Gem::URI "http://example/file"
    path = File.join @tempdir, "file"

    fetcher = util_fuck_with_fetcher "hello"

    data = fetcher.cache_update_path uri, path

    assert_equal "hello", data

    assert_equal "hello", File.read(path)
  end

  def test_cache_update_path_with_utf8_internal_encoding
    with_internal_encoding("UTF-8") do
      uri = Gem::URI "http://example/file"
      path = File.join @tempdir, "file"
      data = String.new("\xC8").force_encoding(Encoding::BINARY)

      fetcher = util_fuck_with_fetcher data

      written_data = fetcher.cache_update_path uri, path

      assert_equal data, written_data
      assert_equal data, File.binread(path)
    end
  end

  def test_cache_update_path_no_update
    uri = Gem::URI "http://example/file"
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
    omit "doesn't work if tempdir has +" if @tempdir.include?("+")
    FileUtils.mv @a1_gem, @tempdir
    local_path = File.join @tempdir, @a1.file_name
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::RemoteFetcher.fetcher
    end

    assert_equal @a1.cache_file, inst.download(@a1, local_path)
  end

  def test_download_local_space
    omit "doesn't work if tempdir has +" if @tempdir.include?("+")
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
      omit "doesn't work if tempdir has +" if @tempdir.include?("+")
      FileUtils.mv @a1_gem, @tempdir
      local_path = File.join @tempdir, @a1.file_name
      inst = nil
      FileUtils.chmod 0o555, @a1.cache_dir
      begin
        FileUtils.mkdir_p File.join(Gem.user_dir, "cache")
      rescue StandardError
        nil
      end
      FileUtils.chmod 0o555, File.join(Gem.user_dir, "cache")

      Dir.chdir @tempdir do
        inst = Gem::RemoteFetcher.fetcher
      end

      assert_equal(File.join(@tempdir, @a1.file_name),
                   inst.download(@a1, local_path))
    ensure
      if local_path
        FileUtils.chmod 0o755, File.join(Gem.user_dir, "cache")
        FileUtils.chmod 0o755, @a1.cache_dir
      end
    end

    def test_download_read_only
      FileUtils.chmod 0o555, @a1.cache_dir
      FileUtils.chmod 0o555, @gemhome

      fetcher = util_fuck_with_fetcher File.read(@a1_gem)
      fetcher.download(@a1, "http://gems.example.com")
      a1_cache_gem = File.join Gem.user_dir, "cache", @a1.file_name
      assert File.exist? a1_cache_gem
    ensure
      FileUtils.chmod 0o755, @gemhome
      FileUtils.chmod 0o755, @a1.cache_dir
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
    omit "doesn't work if tempdir has +" if @tempdir.include?("+")
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
      raise Gem::Timeout::Error, "timed out"
    end

    url = "http://example.com/uri"

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_path url
    end

    assert_match(/Gem::Timeout::Error: timed out \(#{Regexp.escape url}\)\z/,
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

    assert_nil fetcher.fetch_path(Gem::URI.parse(@gem_repo), Time.at(0))
  end

  def test_fetch_http
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      url = "http://gems.example.com/redirect"
      if defined? @requested
        res = Gem::Net::HTTPOK.new nil, 200, nil
        def res.body
          "real_path"
        end
      else
        @requested = true
        res = Gem::Net::HTTPMovedPermanently.new nil, 301, nil
        res.add_field "Location", url
      end
      res
    end

    data = fetcher.fetch_http Gem::URI.parse(url)

    assert_equal "real_path", data
  end

  def test_fetch_http_redirects
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      url = "http://gems.example.com/redirect"
      res = Gem::Net::HTTPMovedPermanently.new nil, 301, nil
      res.add_field "Location", url
      res
    end

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_http Gem::URI.parse(url)
    end

    assert_equal "too many redirects (#{url})", e.message
  end

  def test_fetch_http_redirects_without_location
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    url = "http://gems.example.com/redirect"

    def fetcher.request(uri, request_class, last_modified = nil)
      res = Gem::Net::HTTPMovedPermanently.new nil, 301, nil
      res
    end

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_http Gem::URI.parse(url)
    end

    assert_equal "redirecting but no redirect location was given (#{url})", e.message
  end

  def test_request_block
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    assert_throws :block_called do
      fetcher.request Gem::URI("http://example"), Gem::Net::HTTP::Get do |req|
        assert_kind_of Gem::Net::HTTPGenericRequest, req
        throw :block_called
      end
    end
  end

  def test_yaml_error_on_size
    use_ui @stub_ui do
      fetcher = Gem::RemoteFetcher.new nil
      @fetcher = fetcher
      assert_error { fetcher.size }
    end
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
end
