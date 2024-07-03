# frozen_string_literal: true

require_relative "helper"

require "webrick"

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

  def setup
    @proxies = %w[https_proxy http_proxy HTTP_PROXY http_proxy_user HTTP_PROXY_USER http_proxy_pass HTTP_PROXY_PASS no_proxy NO_PROXY]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }

    super

    @normal_server ||= start_server(SERVER_DATA)
    @proxy_server  ||= start_server(PROXY_DATA)
    self.enable_yaml = true
    self.enable_zip = false

    base_server_uri = "http://localhost:#{@normal_server[:server].config[:Port]}"
    @proxy_uri = "http://localhost:#{@proxy_server[:server].config[:Port]}"

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

    if @normal_server
      @normal_server.kill.join
      @normal_server = nil
    end
    if @proxy_server
      @proxy_server.kill.join
      @proxy_server = nil
    end
    WEBrick::Utils::TimeoutHandler.terminate

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

  private

  attr_reader :normal_server, :proxy_server
  attr_accessor :enable_zip, :enable_yaml

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
end
