# frozen_string_literal: true

require_relative "helper"

require "socket"

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

    @server_uri = "http://localhost:#{@normal_server[:server].addr[1]}" + "/yaml"
    @proxy_uri = "http://localhost:#{@proxy_server[:server].addr[1]}"

    Gem::RemoteFetcher.fetcher = nil
    @stub_ui = Gem::MockGemUi.new
    @fetcher = Gem::RemoteFetcher.fetcher
  end

  def teardown
    @fetcher&.close_all

    if @normal_server
      @normal_server.kill.join
      @normal_server = nil
    end
    if @proxy_server
      @proxy_server.kill.join
      @proxy_server = nil
    end

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

  def assert_data_from_server(data)
    assert_match(/0\.4\.11/, data, "Data is not from server")
  end

  def assert_data_from_proxy(data)
    assert_match(/0\.4\.2/, data, "Data is not from proxy")
  end

  def start_server(data)
    server = TCPServer.new("localhost", 0)
    thread = Thread.new do
      loop do
        client = server.accept
        handle_request(client, data)
      end
    end
    thread[:server] = server
    thread
  end

  def handle_request(client, data)
    request_line = client.gets
    headers = {}
    while (line = client.gets) && line != "\r\n"
      key, value = line.split(": ", 2)
      headers[key] = value.strip
    end

    if request_line.start_with?("GET /yaml")
      response = headers["X-Captain"] ? headers["X-Captain"] : data
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{response.size}\r\n\r\n#{response}"
    elsif request_line.start_with?("HEAD /yaml") || request_line.start_with?("GET http://") && request_line.include?("/yaml")
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{data.size}\r\n\r\n#{data}"
    else
      client.print "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\n\r\n<h1>NOT FOUND</h1>"
    end
    client.close
  end
end
